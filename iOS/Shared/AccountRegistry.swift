import Foundation
import Darwin
import MobileAccessCore
import Security

struct AccountProfile: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let service: QuotaService
    var label: String
    var providerIdentity: String?
    let isLegacy: Bool
    var suggestedNamePending: Bool?

    init(id: String, service: QuotaService, label: String, providerIdentity: String? = nil,
         isLegacy: Bool, suggestedNamePending: Bool? = nil) {
        self.id = id
        self.service = service
        self.label = label
        self.providerIdentity = providerIdentity
        self.isLegacy = isLegacy
        self.suggestedNamePending = suggestedNamePending
    }

    /// Stable identity used when ordering profiles across services. Profile IDs
    /// are only unique within a service because both legacy profiles can be
    /// named `live`.
    var orderKey: String { "\(service.rawValue)\u{0}\(id)" }
}

/// App-group account metadata shared by the app and widgets.
///
/// Every read and read-modify-write operation holds the same cross-process file
/// lock. The first access also records legacy migration, including the empty
/// result on a genuinely new install, so later reads cannot invent accounts.
enum AccountRegistry {
    private struct State: Codable, Equatable {
        var version = 2
        var profiles: [AccountProfile]
        var defaults: [String: String]
        var serviceOrder: [QuotaService]
        /// Optional so version 1 files decode and can derive the original
        /// service-grouped presentation order during normalization.
        var accountOrder: [String]?

        static func migrated(legacyServices: Set<QuotaService>) -> Self {
            let profiles = QuotaService.allCases.compactMap { service in
                legacyServices.contains(service)
                    ? AccountProfile(id: "live", service: service, label: "Account 1", isLegacy: true)
                    : nil
            }
            return Self(
                profiles: profiles,
                defaults: Dictionary(uniqueKeysWithValues: profiles.map { ($0.service.rawValue, $0.id) }),
                serviceOrder: QuotaService.allCases,
                accountOrder: profiles.map(\.orderKey)
            )
        }

        mutating func normalize() {
            version = 2
            var seen = Set<String>()
            profiles = profiles.filter { seen.insert($0.orderKey).inserted }

            for service in QuotaService.allCases {
                let values = profiles.filter { $0.service == service }
                if let id = defaults[service.rawValue], values.contains(where: { $0.id == id }) { continue }
                if let first = values.first { defaults[service.rawValue] = first.id }
                else { defaults.removeValue(forKey: service.rawValue) }
            }

            var ordered = Set<QuotaService>()
            serviceOrder = serviceOrder.filter { ordered.insert($0).inserted }
            serviceOrder.append(contentsOf: QuotaService.allCases.filter { !ordered.contains($0) })

            let profileKeys = profiles.map(\.orderKey)
            let validKeys = Set(profileKeys)
            let proposedOrder = accountOrder ?? serviceOrder.flatMap { service in
                profiles.lazy.filter { $0.service == service }.map(\.orderKey)
            }
            var seenKeys = Set<String>()
            accountOrder = proposedOrder.filter {
                validKeys.contains($0) && seenKeys.insert($0).inserted
            }
            accountOrder?.append(contentsOf: profileKeys.filter { seenKeys.insert($0).inserted })
        }
    }

    /// Injectable storage used by focused tests. Production callers use the
    /// static facade below, which points at the shared app-group container.
    struct Store: Sendable {
        let root: URL?
        let legacyServices: Set<QuotaService>
        let persistEmptyMigration: Bool

        init(root: URL?, legacyServices: Set<QuotaService>, persistEmptyMigration: Bool = true) {
            self.root = root
            self.legacyServices = legacyServices
            self.persistEmptyMigration = persistEmptyMigration
        }

        func all() -> [AccountProfile] { transaction { state in state.profiles } }
        func profiles(for service: QuotaService) -> [AccountProfile] {
            transaction { state in state.profiles.filter { $0.service == service } }
        }
        func defaultProfile(for service: QuotaService) -> AccountProfile? {
            transaction { state in
                let values = state.profiles.filter { $0.service == service }
                guard let id = state.defaults[service.rawValue] else { return values.first }
                return values.first(where: { $0.id == id }) ?? values.first
            }
        }
        func add(service: QuotaService, label requestedLabel: String? = nil, suggestedNamePending: Bool = true) -> AccountProfile {
            transaction { state in
                let count = state.profiles.lazy.filter { $0.service == service }.count
                let suggested = AccountNameSuggestion.make(service: service.name, plan: nil,
                    existingLabels: state.profiles.filter { $0.service == service }.map(\.label))
                let label = requestedLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
                let profile = AccountProfile(
                    id: count == 0 ? "live" : UUID().uuidString,
                    service: service,
                    label: label.flatMap { $0.isEmpty ? nil : $0 } ?? suggested,
                    isLegacy: count == 0,
                    suggestedNamePending: suggestedNamePending
                )
                state.profiles.append(profile)
                if state.defaults[service.rawValue] == nil { state.defaults[service.rawValue] = profile.id }
                return profile
            }
        }
        func rename(id: String, label: String) {
            transaction { state in
                let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !label.isEmpty else { return }
                for index in state.profiles.indices where state.profiles[index].id == id {
                    state.profiles[index].label = label
                    state.profiles[index].suggestedNamePending = false
                }
            }
        }
        func rename(service: QuotaService, id: String, label: String) {
            transaction { state in
                let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !label.isEmpty,
                      let index = state.profiles.firstIndex(where: { $0.service == service && $0.id == id }) else { return }
                state.profiles[index].label = label
                state.profiles[index].suggestedNamePending = false
            }
        }
        func applySuggestedPlan(service: QuotaService, id: String, plan: String) {
            transaction { state in
                let plan = plan.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !plan.isEmpty, plan.caseInsensitiveCompare("Unknown") != .orderedSame else { return }
                guard let index = state.profiles.firstIndex(where: { $0.service == service && $0.id == id }),
                      state.profiles[index].suggestedNamePending == true else { return }
                let existing = state.profiles.filter { $0.service == service && $0.id != id }.map(\.label)
                state.profiles[index].label = AccountNameSuggestion.make(
                    service: service.name, plan: plan, existingLabels: existing)
                state.profiles[index].suggestedNamePending = false
            }
        }
        func remove(id: String) {
            transaction { state in state.profiles.removeAll { $0.id == id } }
        }
        func remove(service: QuotaService, id: String) {
            transaction { state in state.profiles.removeAll { $0.service == service && $0.id == id } }
        }
        func setDefault(id: String) {
            transaction { state in
                for profile in state.profiles where profile.id == id {
                    state.defaults[profile.service.rawValue] = id
                }
            }
        }
        func setDefault(service: QuotaService, id: String) {
            transaction { state in
                guard state.profiles.contains(where: { $0.service == service && $0.id == id }) else { return }
                state.defaults[service.rawValue] = id
            }
        }
        func setProviderIdentity(service: QuotaService, id: String, identity: String) {
            transaction { state in
                guard let index = state.profiles.firstIndex(where: { $0.service == service && $0.id == id }) else { return }
                let value = identity.trimmingCharacters(in: .whitespacesAndNewlines)
                state.profiles[index].providerIdentity = value.isEmpty ? nil : value
            }
        }
        func serviceOrder() -> [QuotaService] { transaction { state in state.serviceOrder } }
        func setServiceOrder(_ order: [QuotaService]) {
            transaction { state in state.serviceOrder = order }
        }
        func accountOrder() -> [String] { transaction { state in state.accountOrder ?? [] } }
        func setAccountOrder(_ keys: [String]) {
            transaction { state in state.accountOrder = keys }
        }

        private var dataURL: URL? { root?.appendingPathComponent("account-registry-v1.json") }
        private var lockURL: URL? { root?.appendingPathComponent("account-registry-v1.lock") }

        private func transaction<T>(_ body: (inout State) -> T) -> T {
            guard let root, let dataURL, let lockURL else {
                return transient(body)
            }
            do { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
            catch { return transient(body) }
            let fd = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
            guard fd >= 0 else { return transient(body) }
            defer { close(fd) }
            while flock(fd, LOCK_EX) != 0 {
                guard errno == EINTR else { return transient(body) }
            }
            defer { flock(fd, LOCK_UN) }
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: lockURL.path
            )

            let existed = FileManager.default.fileExists(atPath: dataURL.path)
            var state: State
            if existed, let data = try? Data(contentsOf: dataURL), let decoded = try? JSONDecoder().decode(State.self, from: data) {
                state = decoded
            } else {
                if existed {
                    let backup = root.appendingPathComponent("account-registry-v1.corrupt-\(UUID().uuidString).json")
                    try? FileManager.default.copyItem(at: dataURL, to: backup)
                }
                state = .migrated(legacyServices: legacyServices)
            }
            state.normalize()
            let before = try? JSONEncoder().encode(state)
            let result = body(&state)
            state.normalize()
            if let after = try? JSONEncoder().encode(state),
               existed || persistEmptyMigration || !state.profiles.isEmpty || before != after {
                try? after.write(to: dataURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            return result
        }

        private func transient<T>(_ body: (inout State) -> T) -> T {
            var state = State.migrated(legacyServices: legacyServices)
            let result = body(&state)
            state.normalize()
            return result
        }
    }

    private static var store: Store {
        Store(
            root: WidgetStore.directory,
            legacyServices: legacyServices(),
            // An extension cannot see the app's old private Keychain. It may
            // read an existing registry, but must not finalize an empty
            // migration before the app has a chance to inspect legacy stores.
            persistEmptyMigration: Bundle.main.bundleURL.pathExtension != "appex"
        )
    }

    static func all() -> [AccountProfile] { store.all() }
    static func profiles(for service: QuotaService) -> [AccountProfile] { store.profiles(for: service) }
    static func defaultProfile(for service: QuotaService) -> AccountProfile? { store.defaultProfile(for: service) }
    static func add(service: QuotaService, label: String? = nil, suggestedNamePending: Bool = true) -> AccountProfile {
        store.add(service: service, label: label, suggestedNamePending: suggestedNamePending)
    }
    static func applySuggestedPlan(service: QuotaService, id: String, plan: String) {
        store.applySuggestedPlan(service: service, id: id, plan: plan)
    }
    static func rename(id: String, label: String) { store.rename(id: id, label: label) }
    static func rename(service: QuotaService, id: String, label: String) { store.rename(service: service, id: id, label: label) }
    static func remove(id: String) { store.remove(id: id) }
    static func remove(service: QuotaService, id: String) { store.remove(service: service, id: id) }
    static func setDefault(id: String) { store.setDefault(id: id) }
    static func setDefault(service: QuotaService, id: String) { store.setDefault(service: service, id: id) }
    static func setProviderIdentity(service: QuotaService, id: String, identity: String) {
        store.setProviderIdentity(service: service, id: id, identity: identity)
    }
    static func serviceOrder() -> [QuotaService] { store.serviceOrder() }
    static func setServiceOrder(_ order: [QuotaService]) { store.setServiceOrder(order) }
    static func accountOrder() -> [String] { store.accountOrder() }
    static func setAccountOrder(_ keys: [String]) { store.setAccountOrder(keys) }

    private static func legacyServices() -> Set<QuotaService> {
        Set(QuotaService.allCases.filter { service in
            let shared = SharedQuotaStore(service)
            if shared.reading() != nil { return true }
            switch service {
            case .codex:
                return sharedCredentials(CodexTokens.self, store: shared)
                    || legacyPrivateCredentials(CodexTokens.self, service: service)
            case .claude:
                return sharedCredentials(ClaudeTokens.self, store: shared)
                    || legacyPrivateCredentials(ClaudeTokens.self, service: service)
            }
        })
    }

    private static func sharedCredentials<T: QuotaCredentials>(_ type: T.Type, store: SharedQuotaStore) -> Bool {
        do { return try store.load(type) != nil }
        catch { return false }
    }

    private static func legacyPrivateCredentials<T: Decodable>(_ type: T.Type, service: QuotaService) -> Bool {
        let serviceName = service == .codex
            ? "com.niederme.AIQuota.MobileAccessProbe"
            : "com.niederme.AIQuota.MobileAccessProbe.Claude"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: service.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return false }
        return (try? JSONDecoder().decode(type, from: data)) != nil
    }
}

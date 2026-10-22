import Foundation
import Security
import Darwin
import MobileAccessCore

enum QuotaService: String, Codable, CaseIterable, Sendable {
    case codex, claude
    var name: String { self == .codex ? "Codex" : "Claude" }
    var logo: String { self == .codex ? "logo-openai" : "logo-claude" }
    var url: URL { URL(string: "aiquota-probe://\(rawValue)")! }
}
protocol QuotaCredentials: Codable, Sendable {
    func needsRefresh(at date: Date) -> Bool
}
extension CodexTokens: QuotaCredentials {}
extension ClaudeTokens: QuotaCredentials {}

/// Both processes use this one credential authority and lock across renewal AND persistence.
/// The OS releases the file lease if a process exits. The main actor never waits synchronously.
struct SharedQuotaStore: Sendable {
    let service: QuotaService
    let root: URL?
    let namespace: String
    init(_ service: QuotaService, root: URL? = WidgetStore.directory, namespace: String = "live") {
        self.service = service; self.root = root; self.namespace = namespace
    }
    init(_ profile: AccountProfile, root: URL? = WidgetStore.directory) {
        self.init(profile.service, root: root, namespace: profile.id)
    }
    private var fileNamespace: String {
        let value = namespace.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar.value == 45 || scalar.value == 95
                ? Character(String(scalar)) : "_"
        }
        let result = String(value)
        return result.isEmpty ? "profile" : result
    }
    private func namespacedFile(_ liveName: String) -> String {
        namespace == "live" ? liveName : "\(fileNamespace)-\(liveName)"
    }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "AIQuota.SharedSession.v2",
         kSecAttrAccount as String: "\(namespace).\(service.rawValue)",
         kSecAttrAccessGroup as String: Bundle.main.object(forInfoDictionaryKey: "WidgetKeychainGroup") as? String ?? ""]
    }
    var readingURL: URL? { root?.appendingPathComponent(namespacedFile("\(service.rawValue)-v2.json")) }
    func load<T: QuotaCredentials>(_ type: T.Type) throws -> T? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw AccessError.storage }
        return try JSONDecoder().decode(type, from: data)
    }
    // Mutation methods are called only inside withLease, including migration and disconnect.
    func saveCredentials<T: QuotaCredentials>(_ credentials: T) throws {
        let attributes: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(credentials),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) }
        guard status == errSecSuccess else { throw AccessError.storage }
    }
    func reading() -> QuotaReading? {
        guard let url = readingURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(QuotaReading.self, from: data)
    }
    private func saveReading(_ reading: QuotaReading) throws {
        guard let url = readingURL else { throw AccessError.storage }
        try JSONEncoder().encode(reading).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AccessError.storage }
        if let url = readingURL, FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        saveFailure(nil)
        if let url = cooldownURL, FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        MobileResetNotifications.cancel(service, namespace: namespace)
        for window in ["5h", "7d"] {
            MobileResetNotifications.defaults.removeObject(
                forKey: MobileResetNotifications.windowPrefix(service, window, namespace: namespace) + "usageState"
            )
        }
        log("app", "disconnected")
    }
    func withLease<T: Sendable>(_ action: @Sendable () async throws -> T) async throws -> T {
        guard let root else { throw AccessError.storage }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let path = root.appendingPathComponent(namespacedFile("\(service.rawValue)-session.lock")).path
        let fd = open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw AccessError.storage }
        defer { close(fd) }
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: path)
        let deadline = ContinuousClock.now.advanced(by: .seconds(35))
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK, ContinuousClock.now < deadline else { throw AccessError.storage }
            try await Task.sleep(for: .milliseconds(100))
        }
        defer { flock(fd, LOCK_UN) }
        try Task.checkCancellation()
        return try await action()
    }
    func fetch<T: QuotaCredentials>(
        _ type: T.Type, source: String, forceRenewal: Bool = false, minimumAge: TimeInterval = 0,
        renew: @Sendable (T) async throws -> T, usage: @Sendable (T) async throws -> QuotaReading
    ) async throws -> QuotaReading {
        try await withLease {
            // A widget can refresh after disconnect/reset. No credentials means signed
            // out, not a broken connection; do not persist a reconnect warning.
            guard var credentials = try load(type) else {
                saveFailure(nil)
                throw AccessError.expired
            }
            // Shared across app, widget and launches. Suppressed attempts must not extend the cooldown.
            if service == .claude, let url = cooldownURL,
               let data = try? Data(contentsOf: url),
               let until = try? JSONDecoder().decode(Date.self, from: data), until > .now {
                throw ClaudeAccessError.requestFailed(stage: "usage update", status: 429)
            }
            do {
                if !forceRenewal, !credentials.needsRefresh(at: .now), let cached = reading(),
                   !WidgetFreshness.isOld(cached, at: .now), Date.now.timeIntervalSince(cached.fetchedAt) < minimumAge {
                    log(source, "reused", reading: cached)
                    return cached
                }
                let previousPlan = reading()?.metadata?.plan
                log(source, "attempt", reading: reading())
                let renewedBeforeUsage = forceRenewal || credentials.needsRefresh(at: .now)
                if renewedBeforeUsage {
                    credentials = try await renew(credentials)
                    // Persist rotated refresh credentials even if the caller was cancelled meanwhile.
                    try saveCredentials(credentials)
                    log(source, "renewed", reading: reading())
                }
                try Task.checkCancellation()
                let value: QuotaReading
                do {
                    value = try await usage(credentials)
                } catch {
                    let unauthorized = (error as? AccessError) == .http(401) ||
                        ((error as? ClaudeAccessError).map {
                            if case .requestFailed(_, 401) = $0 { return true }
                            return false
                        } ?? false)
                    guard unauthorized, !renewedBeforeUsage else { throw error }
                    // A plan change can invalidate an otherwise unexpired access token.
                    // Keep recovery under the app/widget lease and retry only once.
                    credentials = try await renew(credentials)
                    try saveCredentials(credentials)
                    log(source, "renewed_after_401", reading: reading())
                    try Task.checkCancellation()
                    value = try await usage(credentials)
                }
                try Task.checkCancellation()
                try saveReading(value)
                saveFailure(nil)
                await MobileResetNotifications.update(service, reading: value, evaluateUsage: true, namespace: namespace)
                await MobileResetNotifications.planChanged(
                    service, previous: previousPlan, current: value.metadata?.plan, namespace: namespace
                )
                log(source, "success", reading: value)
                return value
            } catch {
                if service == .claude,
                   case .requestFailed(_, 429) = error as? ClaudeAccessError,
                   let url = cooldownURL {
                    try? JSONEncoder().encode(Date.now.addingTimeInterval(300)).write(to: url, options: .atomic)
                }
                if !(error is CancellationError) {
                    saveFailure(Failure.classify(error))
                    MobileResetNotifications.cancel(service, namespace: namespace)
                }
                log(source, Self.safeFailureCode(error), reading: reading())
                throw error
            }
        }
    }
    func fetch(source: String, forceRenewal: Bool = false, minimumAge: TimeInterval = 0) async throws -> QuotaReading {
        switch service {
        case .codex:
            let api = CodexAPI()
            return try await fetch(CodexTokens.self, source: source, forceRenewal: forceRenewal, minimumAge: minimumAge,
                                   renew: { try await api.renew($0) }, usage: { try await api.usage($0, includeSpending: source == "app") })
        case .claude:
            let api = ClaudeAPI()
            return try await fetch(ClaudeTokens.self, source: source, forceRenewal: forceRenewal, minimumAge: minimumAge,
                                   renew: { try await api.renew($0) }, usage: { try await api.usage($0) })
        }
    }
    static func safeFailureCode(_ error: Error) -> String {
        if let error = error as? ClaudeAccessError {
            switch error {
            case .reconnectRequired: return "renewal.invalid_grant"
            case let .renewalRejected(status, reason):
                let allowed = ["invalid_scope", "invalid_request", "invalid_client", "unauthorized_client", "unsupported_grant_type"]
                return "renewal.http\(status)." + (reason.flatMap { allowed.contains($0) ? $0 : nil } ?? "unknown")
            case let .requestFailed(stage, status):
                let safeStage = ["sign-in", "sign-in renewal", "usage update"].contains(stage) ? stage : "request"
                return "\(safeStage).http\(status)"
            default: return "sign-in.invalid_or_expired_code"
            }
        }
        return Failure.classify(error).rawValue
    }
    enum Failure: String, Codable, Sendable {
        case reconnect, renewal, temporary
        static func classify(_ error: Error) -> Self {
            if (error as? ClaudeAccessError)?.requiresReconnect == true || (error as? AccessError) == .expired || (error as? AccessError) == .http(401) { return .reconnect }
            if case .renewalRejected = error as? ClaudeAccessError { return .renewal }
            return .temporary
        }
    }
    var updatesPaused: Bool {
        guard let url = cooldownURL, let data = try? Data(contentsOf: url),
              let until = try? JSONDecoder().decode(Date.self, from: data) else { return false }
        return until > .now
    }
    var cooldownURL: URL? { root?.appendingPathComponent(namespacedFile("\(service.rawValue)-cooldown.json")) }
    var failureURL: URL? { root?.appendingPathComponent(namespacedFile("\(service.rawValue)-failure.json")) }
    func failure() -> Failure? {
        guard let url = failureURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Failure.self, from: data)
    }
    private func saveFailure(_ value: Failure?) {
        guard let url = failureURL else { return }
        if let value { try? JSONEncoder().encode(value).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        else { try? FileManager.default.removeItem(at: url) }
    }
    func log(_ source: String, _ result: String, reading: QuotaReading? = nil, entryDates: [Date] = []) {
        guard var directory = root?.appendingPathComponent("widget-diagnostics") else { return }
        if namespace != "live" { directory.appendPathComponent(fileNamespace, isDirectory: true) }
        struct Event: Encodable { let date: Date; let provider: String; let source: String; let result: String; let readingDate: Date?; let entryDates: [Date] }
        struct ProfileEvent: Encodable { let date: Date; let provider: String; let profile: String; let source: String; let result: String; let readingDate: Date?; let entryDates: [Date] }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data: Data
            if namespace == "live" {
                data = try JSONEncoder().encode(Event(date: .now, provider: service.rawValue, source: source,
                    result: result, readingDate: reading?.fetchedAt, entryDates: entryDates))
            } else {
                data = try JSONEncoder().encode(ProfileEvent(date: .now, provider: service.rawValue, profile: namespace,
                    source: source, result: result, readingDate: reading?.fetchedAt, entryDates: entryDates))
            }
            try data.write(to: directory.appendingPathComponent(UUID().uuidString + ".json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { /* Missing diagnostics intervals remain unknown, never counted as fresh. */ }
    }
}

import UserNotifications

/// Scheduled reset estimates only. Delivery does not confirm renewed availability.
enum MobileResetNotifications {
    static var defaults: UserDefaults { UserDefaults(suiteName: WidgetStore.group) ?? .standard }
    private static func displayName(_ service: QuotaService, namespace: String) -> String {
        let profiles = AccountRegistry.profiles(for: service)
        guard profiles.count > 1,
              let profile = profiles.first(where: { $0.id == namespace }) else { return service.name }
        return "\(service.name) · \(profile.label)"
    }
    // An absent preference means enabled; an explicit opt-out must survive re-enabling notifications.
    static func alertEnabled(_ key: String, store: UserDefaults = defaults) -> Bool {
        store.object(forKey: key) as? Bool ?? true
    }
    static func identifier(_ service: QuotaService, _ window: String, namespace: String = "live") -> String {
        namespace == "live"
            ? "quota.reset.\(service.rawValue).\(window)"
            : "quota.reset.\(service.rawValue).\(namespace).\(window)"
    }
    static func windowPrefix(_ service: QuotaService, _ window: String, namespace: String = "live") -> String {
        namespace == "live"
            ? "notifications.\(service.rawValue).\(window)."
            : "notifications.\(service.rawValue).\(namespace).\(window)."
    }
    static func servicePreferenceKey(_ service: QuotaService, namespace: String) -> String {
        namespace == "live" ? "notifications.\(service.rawValue)" : "notifications.\(service.rawValue).\(namespace)"
    }
    static func usageThreshold(_ service: QuotaService, namespace: String = "live", store: UserDefaults = defaults) -> Double {
        let key = servicePreferenceKey(service, namespace: namespace) + ".usageThreshold"
        if let value = store.object(forKey: key) as? Double { return min(100, max(5, value.isFinite ? value : 90)) }
        // Preserve an explicitly stored threshold. When old windows differ, use the earlier alert.
        let previous = ["5h", "7d"].compactMap { store.object(forKey: windowPrefix(service, $0, namespace: namespace) + "usageThreshold") as? Double }.filter(\.isFinite)
        let value = min(100, max(5, previous.min() ?? 90))
        store.set(value, forKey: key)
        return value
    }

    private static func errorKey(_ service: QuotaService, namespace: String) -> String {
        namespace == "live" ? "notifications.error" : "notifications.error.\(service.rawValue).\(namespace)"
    }
    private static func usageIdentifier(_ service: QuotaService, _ window: String, namespace: String) -> String {
        namespace == "live"
            ? "quota.usage.\(service.rawValue).\(window)"
            : "quota.usage.\(service.rawValue).\(namespace).\(window)"
    }
    private static func planIdentifier(_ service: QuotaService, namespace: String) -> String {
        namespace == "live" ? "quota.plan.\(service.rawValue)" : "quota.plan.\(service.rawValue).\(namespace)"
    }
    static func planned(_ reading: QuotaReading?, now: Date, rules: [String: ResetAlertRule] = [:]) -> [(String, Date)] {
        guard let reading, !WidgetFreshness.isOld(reading, at: now) else { return [] }
        return [("5h", reading.shortTerm), ("7d", reading.weekly)].compactMap { label, window in
            guard let window, (rules[label] ?? ResetAlertRule()).allows(usedPercent: window.usedPercent), let reset = window.resetsAt, reset > now else { return nil }
            return (label, reset)
        }
    }
    static func rules(_ service: QuotaService, store: UserDefaults = defaults, namespace: String = "live") -> [String: ResetAlertRule] {
        Dictionary(uniqueKeysWithValues: ["5h", "7d"].map { window in
            let key = windowPrefix(service, window, namespace: namespace)
            let mode = ResetAlertRule.Mode(rawValue: store.string(forKey: key + "resetMode") ?? "") ?? .nearLimit
            let threshold = store.object(forKey: key + "resetThreshold") as? Double ?? 90
            return (window, ResetAlertRule(mode: mode, threshold: threshold))
        })
    }
    static func cancel(_ service: QuotaService, namespace: String = "live") {
        var identifiers = [
            identifier(service, "5h", namespace: namespace),
            identifier(service, "7d", namespace: namespace),
            usageIdentifier(service, "5h", namespace: namespace),
            usageIdentifier(service, "7d", namespace: namespace)
        ]
        // Preserve the legacy live cancellation set exactly. New profiles own
        // their plan-change request as part of their isolated notification set.
        if namespace != "live" { identifiers.append(planIdentifier(service, namespace: namespace)) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    static func planChanged(_ service: QuotaService, previous: String?, current: String?, namespace: String = "live") async {
        guard let change = PlanChange(previous: previous, current: current),
              defaults.bool(forKey: "notifications.enabled"),
              defaults.object(forKey: servicePreferenceKey(service, namespace: namespace)) as? Bool ?? true else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(displayName(service, namespace: namespace)) plan changed to \(change.current)"
        content.body = "Previously \(change.previous). Connection checked and usage is up to date."
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: planIdentifier(service, namespace: namespace), content: content, trigger: nil))
    }

    // Call under the provider lease so app and widget do not race scheduling or disconnect.
    static func update(_ service: QuotaService, reading: QuotaReading?, evaluateUsage: Bool = false, namespace: String = "live") async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard defaults.bool(forKey: "notifications.enabled"),
              defaults.object(forKey: servicePreferenceKey(service, namespace: namespace)) as? Bool ?? true,
              settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            cancel(service, namespace: namespace); return
        }
        do {
            try await apply(service, plan: planned(reading, now: .now, rules: rules(service, namespace: namespace)), namespace: namespace, remove: { id in
                center.removePendingNotificationRequests(withIdentifiers: [id])
            }, schedule: { id, label, reset in
                let content = UNMutableNotificationContent()
                let window = label == "5h" ? reading?.shortTerm : reading?.weekly
                content.title = "\(displayName(service, namespace: namespace)) \(window?.resetLabel ?? label) reset expected"
                content.body = "Your last reading reported a reset now. Open AIQuota to check current usage."
                content.sound = .default
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reset)
                try await center.add(UNNotificationRequest(identifier: id, content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
            })
            if evaluateUsage { try await usageAlerts(service, reading: reading, namespace: namespace) }
            defaults.removeObject(forKey: errorKey(service, namespace: namespace))
        } catch {
            defaults.set("Couldn’t schedule reset alerts. Try again.", forKey: errorKey(service, namespace: namespace))
        }
    }
    private static func usageAlerts(_ service: QuotaService, reading: QuotaReading?, namespace: String) async throws {
        guard let reading, !WidgetFreshness.isOld(reading, at: .now) else { return }
        for (label, window) in [("5h", reading.shortTerm), ("7d", reading.weekly)] {
            guard let window, let end = window.resetsAt, end > .now else { continue }
            let prefix = windowPrefix(service, label, namespace: namespace)
            var state = defaults.data(forKey: prefix + "usageState").flatMap { try? JSONDecoder().decode(UsageAlertState.self, from: $0) }
                ?? UsageAlertState(windowEnd: end)
            state.updateWindow(end: end, now: .now)
            defaults.set(try JSONEncoder().encode(state), forKey: prefix + "usageState")
            guard let level = state.next(used: window.usedPercent, now: .now,
                enabled: alertEnabled(prefix + "usageEnabled"),
                threshold: usageThreshold(service, namespace: namespace)) else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(displayName(service, namespace: namespace)) \(window.resetLabel) "
                + (level == 100 ? "limit reached" : "usage high")
            content.body = "\(Int(window.usedPercent.rounded()))% used. Open AIQuota for current usage."
            content.sound = .default
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(
                identifier: usageIdentifier(service, label, namespace: namespace), content: content, trigger: nil
            ))
            state.highestNotified = level
            defaults.set(try JSONEncoder().encode(state), forKey: prefix + "usageState")
        }
    }
    static func apply(_ service: QuotaService, plan: [(String, Date)], namespace: String = "live",
        remove: (String) async -> Void, schedule: (String, String, Date) async throws -> Void) async throws {
        for label in ["5h", "7d"] {
            let id = identifier(service, label, namespace: namespace)
            if let reset = plan.first(where: { $0.0 == label })?.1 { try await schedule(id, label, reset) }
            else { await remove(id) }
        }
    }
    static func reconcile() async {
        for profile in AccountRegistry.all() {
            let store = SharedQuotaStore(profile)
            try? await store.withLease {
                await update(
                    profile.service,
                    reading: store.failure() == nil ? store.reading() : nil,
                    namespace: profile.id
                )
            }
        }
    }
}

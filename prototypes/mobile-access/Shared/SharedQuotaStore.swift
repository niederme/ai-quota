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
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "AIQuota.SharedSession.v2",
         kSecAttrAccount as String: "\(namespace).\(service.rawValue)",
         kSecAttrAccessGroup as String: Bundle.main.object(forInfoDictionaryKey: "WidgetKeychainGroup") as? String ?? ""]
    }
    private var readingURL: URL? { root?.appendingPathComponent("\(service.rawValue)-v2.json") }
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
        if namespace == "live" { MobileResetNotifications.cancel(service) }
        log("app", "disconnected")
    }
    func withLease<T: Sendable>(_ action: @Sendable () async throws -> T) async throws -> T {
        guard let root else { throw AccessError.storage }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let path = root.appendingPathComponent("\(service.rawValue)-session.lock").path
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
            do {
                guard var credentials = try load(type) else { throw AccessError.expired }
                if !forceRenewal, !credentials.needsRefresh(at: .now), let cached = reading(),
                   !WidgetFreshness.isOld(cached, at: .now), Date.now.timeIntervalSince(cached.fetchedAt) < minimumAge {
                    log(source, "reused", reading: cached)
                    return cached
                }
                log(source, "attempt", reading: reading())
                if forceRenewal || credentials.needsRefresh(at: .now) {
                    credentials = try await renew(credentials)
                    // Persist rotated refresh credentials even if the caller was cancelled meanwhile.
                    try saveCredentials(credentials)
                    log(source, "renewed", reading: reading())
                }
                try Task.checkCancellation()
                let value = try await usage(credentials)
                try Task.checkCancellation()
                try saveReading(value)
                saveFailure(nil)
                if namespace == "live" { await MobileResetNotifications.update(service, reading: value) }
                log(source, "success", reading: value)
                return value
            } catch {
                if !(error is CancellationError) {
                    saveFailure(Failure.classify(error))
                    if namespace == "live" { MobileResetNotifications.cancel(service) }
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
    private var failureURL: URL? { root?.appendingPathComponent("\(service.rawValue)-failure.json") }
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
        guard let directory = root?.appendingPathComponent("widget-diagnostics") else { return }
        struct Event: Encodable { let date: Date; let provider: String; let source: String; let result: String; let readingDate: Date?; let entryDates: [Date] }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let value = Event(date: .now, provider: service.rawValue, source: source, result: result, readingDate: reading?.fetchedAt, entryDates: entryDates)
            try JSONEncoder().encode(value).write(to: directory.appendingPathComponent(UUID().uuidString + ".json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { /* Missing diagnostics intervals remain unknown, never counted as fresh. */ }
    }
}

import UserNotifications

/// Scheduled reset estimates only. Delivery does not confirm renewed availability.
enum MobileResetNotifications {
    static var defaults: UserDefaults { UserDefaults(suiteName: WidgetStore.group) ?? .standard }
    static func identifier(_ service: QuotaService, _ window: String) -> String { "quota.reset.\(service.rawValue).\(window)" }
    static func planned(_ reading: QuotaReading?, now: Date) -> [(String, Date)] {
        guard let reading, !WidgetFreshness.isOld(reading, at: now) else { return [] }
        return [("5h", reading.shortTerm), ("7d", reading.weekly)].compactMap { label, window in
            guard let window, window.usedPercent > 0, let reset = window.resetsAt, reset > now else { return nil }
            return (label, reset)
        }
    }
    static func cancel(_ service: QuotaService) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier(service, "5h"), identifier(service, "7d")])
    }
    // Call under the provider lease so app and widget do not race scheduling or disconnect.
    static func update(_ service: QuotaService, reading: QuotaReading?) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard defaults.bool(forKey: "notifications.enabled"),
              defaults.object(forKey: "notifications.\(service.rawValue)") as? Bool ?? true,
              settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            cancel(service); return
        }
        do {
            try await apply(service, plan: planned(reading, now: .now), remove: { id in
                center.removePendingNotificationRequests(withIdentifiers: [id])
            }, schedule: { id, label, reset in
                let content = UNMutableNotificationContent()
                content.title = "\(service.name) \(label) reset expected"
                content.body = "Your last reading reported a reset now. Open AIQuota to check current usage."
                content.sound = .default
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reset)
                try await center.add(UNNotificationRequest(identifier: id, content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
            })
            defaults.removeObject(forKey: "notifications.error")
        } catch { defaults.set("Couldn’t schedule reset alerts. Try again.", forKey: "notifications.error") }
    }
    static func apply(_ service: QuotaService, plan: [(String, Date)],
        remove: (String) async -> Void, schedule: (String, String, Date) async throws -> Void) async throws {
        for label in ["5h", "7d"] {
            let id = identifier(service, label)
            if let reset = plan.first(where: { $0.0 == label })?.1 { try await schedule(id, label, reset) }
            else { await remove(id) }
        }
    }
    static func reconcile() async {
        for service in QuotaService.allCases {
            let store = SharedQuotaStore(service)
            try? await store.withLease {
                await update(service, reading: store.failure() == nil ? store.reading() : nil)
            }
        }
    }
}

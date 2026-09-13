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
                log(source, "success", reading: value)
                return value
            } catch {
                log(source, "failed", reading: reading())
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

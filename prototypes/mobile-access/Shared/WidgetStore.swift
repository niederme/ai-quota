import Foundation
import Security
import Darwin
import MobileAccessCore

/// Only access credentials are shared. Refresh credentials remain in the app's private Keychain.
enum WidgetStore {
    static let group = "group.com.niederme.AIQuota.MobileAccessProbe"
    static var directory: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) }
    private static func query(account: String = "codex") -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "AIQuota.WidgetAccess",
         kSecAttrAccount as String: account,
         kSecAttrAccessGroup as String: Bundle.main.object(forInfoDictionaryKey: "WidgetKeychainGroup") as? String ?? ""]
    }
    private static func locked<T>(_ action: () throws -> T) throws -> T {
        guard let path = directory?.appendingPathComponent("store.lock").path else { throw AccessError.storage }
        let fd = open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw AccessError.storage }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw AccessError.storage }
        defer { flock(fd, LOCK_UN) }
        return try action()
    }
    static func publish(_ tokens: CodexTokens, account: String = "codex") throws {
        try locked { try publishUnlocked(tokens, account: account) }
    }
    static func accessOnlyData(_ tokens: CodexTokens) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(tokens)) as! [String: Any]
        object.removeValue(forKey: "refreshToken")
        return try JSONSerialization.data(withJSONObject: object)
    }
    private static func publishUnlocked(_ tokens: CodexTokens, account: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: try accessOnlyData(tokens),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query(account: account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query(account: account).merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AccessError.storage }
    }
    static func tokens(account: String = "codex") throws -> CodexTokens? {
        var q = query(account: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw AccessError.storage }
        return try JSONDecoder().decode(CodexTokens.self, from: data)
    }
    static func clear() throws {
        try locked { try clearUnlocked() }
    }
    private static func clearUnlocked() throws {
        try clearAccess()
        if let url = directory?.appendingPathComponent("reading.json"), FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        log("app", "disconnected")
    }
    static func clearAccess(account: String = "codex") throws {
        let status = SecItemDelete(query(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AccessError.storage }
    }
    static func reading() -> QuotaReading? {
        guard let url = directory?.appendingPathComponent("reading.json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(QuotaReading.self, from: data)
    }
    static func save(_ reading: QuotaReading, matching token: CodexTokens) throws -> QuotaReading? {
        try locked {
            guard let latest = try tokens(), latest.accessToken == token.accessToken else { return nil }
            if let saved = self.reading(), saved.fetchedAt > reading.fetchedAt { return saved }
            try saveUnlocked(reading)
            return reading
        }
    }
    private static func saveUnlocked(_ reading: QuotaReading) throws {
        guard let url = directory?.appendingPathComponent("reading.json") else { throw AccessError.storage }
        try JSONEncoder().encode(reading).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    /// One file per event avoids app/extension append races. No provider bodies or credentials.
    static func log(_ source: String, _ result: String, reading: QuotaReading? = nil, entryDates: [Date] = []) {
        guard let root = directory?.appendingPathComponent("widget-diagnostics", isDirectory: true) else { return }
        struct Event: Encodable { let date: Date; let source: String; let result: String; let readingDate: Date?; let entryDates: [Date] }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let event = Event(date: .now, source: source, result: result, readingDate: reading?.fetchedAt, entryDates: entryDates)
            try JSONEncoder().encode(event).write(to: root.appendingPathComponent(UUID().uuidString + ".json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { /* Diagnostics failure must not expose or replace credential errors. */ }
    }
}

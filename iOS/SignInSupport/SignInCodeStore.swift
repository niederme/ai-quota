import Foundation
import Security

/// This separate access group exposes only the short-lived code, never account tokens.
enum SignInCodeStore {
    struct Entry: Codable {
        let code: String
        let expiresAt: Date
    }
    enum Failure: Error { case storage }
    private static func query(account: String) throws -> [String: Any] {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "SignInCodeKeychainGroup") as? String,
              !group.isEmpty else { throw Failure.storage }
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.niederme.AIQuota.signInCode",
                kSecAttrAccount as String: account,
                kSecAttrAccessGroup as String: group]
    }
    static func save(code: String, expiresAt: Date, account: String = "codex") throws {
        let data = try JSONEncoder().encode(Entry(code: code, expiresAt: expiresAt))
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let query = try query(account: account)
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, value in value } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Failure.storage }
    }
    static func load(at date: Date = .now, account: String = "codex") throws -> Entry? {
        var query = try query(account: account)
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw Failure.storage }
        let entry = try JSONDecoder().decode(Entry.self, from: data)
        guard entry.expiresAt > date else { try clear(account: account); return nil }
        return entry
    }
    static func clear(account: String = "codex") throws {
        let status = SecItemDelete(try query(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.storage }
    }
}

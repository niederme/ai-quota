import Foundation
import Security
import MobileAccessCore

enum ClaudeTokenStore {
    private static func query(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.niederme.AIQuota.MobileAccessProbe.Claude",
         kSecAttrAccount as String: account]
    }
    static func load(account: String = "claude") throws -> ClaudeTokens? {
        var q = query(account: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw AccessError.storage }
        return try JSONDecoder().decode(ClaudeTokens.self, from: data)
    }
    static func save(_ tokens: ClaudeTokens, account: String = "claude") throws {
        let data = try JSONEncoder().encode(tokens)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query(account: account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query(account: account).merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AccessError.storage }
    }
    static func clear(account: String = "claude") throws {
        let status = SecItemDelete(query(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AccessError.storage }
    }
}

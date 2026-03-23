import Foundation
import Security

public enum KeychainStore {
    private static let service = "com.niederme.AIQuota"

    // kSecUseDataProtectionKeychain = true stores items in the modern per-app data
    // protection keychain rather than the legacy login keychain. The login keychain
    // uses ACL-based access control and shows a "password required" dialog whenever
    // the app's code signature changes (every Xcode build, every update). The data
    // protection keychain is tied to the app's bundle ID and never prompts the user.
    // Available on macOS 10.15+.

    public static func save(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecUseDataProtectionKeychain: true,
        ]
        SecItemDelete(query as CFDictionary)
        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
            kSecUseDataProtectionKeychain: true,
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    public static func load(forKey key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    public static func delete(forKey key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecUseDataProtectionKeychain: true,
        ]
        SecItemDelete(query as CFDictionary)
    }

    public static func deleteAll() {
        for key in ["accessToken", "refreshToken", "tokenExpiry"] {
            delete(forKey: key)
        }
    }
}

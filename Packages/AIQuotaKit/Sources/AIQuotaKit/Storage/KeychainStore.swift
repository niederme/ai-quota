import Foundation
import Security

public enum KeychainStore {
    private static let service = "com.niederme.AIQuota"

    private static var sharedAccessGroup: String? {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "keychain-access-groups" as CFString, nil)
        else { return nil }
        return (value as? [String])?.first
    }

    // kSecUseDataProtectionKeychain = true stores items in the modern per-app data
    // protection keychain rather than the legacy login keychain. The login keychain
    // uses ACL-based access control and shows a "password required" dialog whenever
    // the app's code signature changes (every Xcode build, every update). The data
    // protection keychain is tied to the app's bundle ID and never prompts the user.
    // Available on macOS 10.15+.

    public static func save(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        save(data, forKey: key)
    }

    public static func save(_ data: Data, forKey key: String) {
        delete(forKey: key)

        var attributes = primaryQuery(forKey: key)
        attributes.merge([
            kSecClass: kSecClassGenericPassword,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
        ]) { _, new in new }
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard shouldFallback(from: status) else { return }

        var fallbackAttributes = fallbackQuery(forKey: key)
        fallbackAttributes.merge([
            kSecClass: kSecClassGenericPassword,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
        ]) { _, new in new }
        SecItemAdd(fallbackAttributes as CFDictionary, nil)
    }

    public static func load(forKey key: String) -> String? {
        guard let data = loadData(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func loadData(forKey key: String) -> Data? {
        var query = primaryQuery(forKey: key)
        query.merge([
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]) { _, new in new }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status != errSecSuccess {
            var fallback = fallbackQuery(forKey: key)
            fallback.merge([
                kSecReturnData: true,
                kSecMatchLimit: kSecMatchLimitOne,
            ]) { _, new in new }
            let fallbackStatus = SecItemCopyMatching(fallback as CFDictionary, &result)
            guard fallbackStatus == errSecSuccess else { return nil }
            return result as? Data
        }
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    public static func delete(forKey key: String) {
        SecItemDelete(primaryQuery(forKey: key) as CFDictionary)
        SecItemDelete(fallbackQuery(forKey: key) as CFDictionary)
    }

    public static func save<T: Encodable>(_ value: T, forKey key: String, encoder: JSONEncoder = JSONEncoder()) {
        guard let data = try? encoder.encode(value) else { return }
        save(data, forKey: key)
    }

    public static func load<T: Decodable>(_ type: T.Type, forKey key: String, decoder: JSONDecoder = JSONDecoder()) -> T? {
        guard let data = loadData(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private static func primaryQuery(forKey key: String) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecUseDataProtectionKeychain: true,
        ]
        if let sharedAccessGroup {
            query[kSecAttrAccessGroup] = sharedAccessGroup
        }
        return query
    }

    private static func fallbackQuery(forKey key: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
    }

    private static func shouldFallback(from status: OSStatus) -> Bool {
        status == errSecMissingEntitlement || status == errSecParam
    }

    public static func deleteAll() {
        for key in ["accessToken", "refreshToken", "tokenExpiry"] {
            delete(forKey: key)
        }
    }
}

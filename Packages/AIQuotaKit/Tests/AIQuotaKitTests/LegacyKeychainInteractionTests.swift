import Foundation
import Security
import Testing
@testable import AIQuotaKit

// Uses disposable keychains and synthetic credentials, never the login keychain.
@Suite("Legacy keychain noninteractive access", .serialized)
struct LegacyKeychainInteractionTests {
    @Test("protected credentials return without prompting, including repeated reads")
    func protectedItem() throws {
        try withTemporaryKeychain(trustedApplications: []) { keychain in
            for _ in 0..<3 {
                let data = try ClaudeOAuthKeychainReader.readNoninteractively(service: "AIQuota-test", keychain: keychain)
                #expect(data == nil)
            }
        }
    }

    @Test("previously authorized credentials can still be read silently")
    func authorizedItem() throws {
        var application: SecTrustedApplication?
        try check(SecTrustedApplicationCreateFromPath(nil, &application))
        try withTemporaryKeychain(trustedApplications: [try #require(application)]) { keychain in
            let data = try ClaudeOAuthKeychainReader.readNoninteractively(service: "AIQuota-test", keychain: keychain)
            #expect(data == Data("synthetic-token".utf8))
        }
    }

    @Test("locked keychain does not open an unlock dialog")
    func lockedKeychain() throws {
        try withTemporaryKeychain(trustedApplications: []) { keychain in
            try check(SecKeychainLock(keychain))
            let data = try ClaudeOAuthKeychainReader.readNoninteractively(service: "AIQuota-test", keychain: keychain)
            #expect(data == nil)
        }
    }

    @Test("interaction setting is restored after both successful and failed operations")
    func restoresInteractionSetting() throws {
        var original: DarwinBoolean = false
        try check(SecKeychainGetUserInteractionAllowed(&original))
        defer { SecKeychainSetUserInteractionAllowed(original.boolValue) }
        for initial in [true, false] {
            try check(SecKeychainSetUserInteractionAllowed(initial))
            try LegacyKeychainInteraction.withoutUI {
                var inside: DarwinBoolean = true
                try check(SecKeychainGetUserInteractionAllowed(&inside))
                #expect(inside.boolValue == false)
            }
            enum Expected: Error { case failure }
            #expect(throws: Expected.self) {
                try LegacyKeychainInteraction.withoutUI { throw Expected.failure }
            }
            var after: DarwinBoolean = false
            try check(SecKeychainGetUserInteractionAllowed(&after))
            #expect(after.boolValue == initial)
        }
    }

    private func withTemporaryKeychain(
        trustedApplications: [SecTrustedApplication],
        body: (SecKeychain) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "aiquota-keychain-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appending(path: "test.keychain").path
        let password = UUID().uuidString
        var keychain: SecKeychain?
        try check(SecKeychainCreate(path, UInt32(password.utf8.count), password, false, nil, &keychain))
        let created = try #require(keychain)
        defer { SecKeychainDelete(created) }
        var access: SecAccess?
        try check(SecAccessCreate("AIQuota synthetic test" as CFString, trustedApplications as CFArray, &access))
        try check(SecItemAdd([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "AIQuota-test",
            kSecAttrAccount: "test",
            kSecValueData: Data("synthetic-token".utf8),
            kSecUseKeychain: created,
            kSecAttrAccess: try #require(access),
        ] as CFDictionary, nil))
        try body(created)
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}

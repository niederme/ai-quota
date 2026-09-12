import XCTest
import MobileAccessCore
@testable import AIQuota_iOS

private func credentials(expired: Bool = false) throws -> CodexTokens {
    let json = expired
        ? #"{"accessToken":"old-access","refreshToken":"old-refresh","expiresAt":0}"#
        : #"{"accessToken":"new-access","refreshToken":"new-refresh","expiresAt":1900000000}"#
    return try JSONDecoder().decode(CodexTokens.self, from: Data(json.utf8))
}
private func sample() throws -> QuotaReading {
    try QuotaReading.decode(Data(#"{"rate_limit":{"primary_window":{"used_percent":24,"limit_window_seconds":18000},"secondary_window":{"used_percent":50,"limit_window_seconds":604800}}}"#.utf8), now: .now)
}
private actor Calls {
    var renewals = 0
    var access: [String] = []
    func renew(_ old: CodexTokens) async throws -> CodexTokens {
        renewals += 1
        try await Task.sleep(for: .milliseconds(150))
        return try credentials()
    }
    func usage(_ token: CodexTokens) throws -> QuotaReading { access.append(token.accessToken); return try sample() }
}
final class SharedQuotaStoreTests: XCTestCase {
    private func store(_ service: QuotaService = .codex) -> SharedQuotaStore {
        let id = UUID().uuidString
        return SharedQuotaStore(service, root: FileManager.default.temporaryDirectory.appendingPathComponent(id), namespace: id)
    }
    private func clean(_ store: SharedQuotaStore) async throws {
        try await store.withLease { try store.clear() }
        if let root = store.root { try? FileManager.default.removeItem(at: root) }
    }
    func testConcurrentAppAndWidgetRenewOnlyOnce() async throws {
        let store = store(), calls = Calls()
        try await store.withLease { try store.saveCredentials(credentials(expired: true)) }
        async let first = store.fetch(CodexTokens.self, source: "app", renew: { try await calls.renew($0) }, usage: { try await calls.usage($0) })
        async let second = store.fetch(CodexTokens.self, source: "widget", renew: { try await calls.renew($0) }, usage: { try await calls.usage($0) })
        _ = try await [first, second]
        let renewals = await calls.renewals, access = await calls.access
        XCTAssertEqual(renewals, 1)
        XCTAssertEqual(access, ["new-access", "new-access"])
        XCTAssertEqual(try store.load(CodexTokens.self)?.refreshToken, "new-refresh")
        try await clean(store)
    }
    func testFailedFetchKeepsReadingAndRotatedCredential() async throws {
        let store = store()
        try await store.withLease { try store.saveCredentials(credentials()) }
        let original = try await store.fetch(CodexTokens.self, source: "app", renew: { $0 }, usage: { _ in try sample() })
        try await store.withLease { try store.saveCredentials(credentials(expired: true)) }
        do {
            _ = try await store.fetch(CodexTokens.self, source: "widget", renew: { _ in try credentials() }, usage: { _ in throw AccessError.http(503) })
            XCTFail("Expected provider failure")
        } catch { XCTAssertEqual(error as? AccessError, .http(503)) }
        XCTAssertEqual(store.reading(), original)
        XCTAssertEqual(try store.load(CodexTokens.self)?.refreshToken, "new-refresh")
        let folder = try XCTUnwrap(store.root?.appendingPathComponent("widget-diagnostics"))
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            let log = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(log.contains("new-access")); XCTAssertFalse(log.contains("new-refresh"))
        }
        try await clean(store)
    }
    func testDisconnectWaitsForInFlightRenewalAndRemovesResult() async throws {
        let store = store(), calls = Calls()
        try await store.withLease { try store.saveCredentials(credentials(expired: true)) }
        let fetch = Task { try await store.fetch(CodexTokens.self, source: "widget", renew: { try await calls.renew($0) }, usage: { try await calls.usage($0) }) }
        for _ in 0..<100 {
            if await calls.renewals > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try await store.withLease { try store.clear() }
        _ = try await fetch.value
        XCTAssertNil(try store.load(CodexTokens.self)); XCTAssertNil(store.reading())
        try await clean(store)
    }
    func testProviderIsolationAndRecentFetchReuse() async throws {
        let codex = store(), calls = Calls()
        let claude = SharedQuotaStore(.claude, root: codex.root, namespace: codex.namespace)
        let claudeToken = try JSONDecoder().decode(ClaudeTokens.self, from: Data(#"{"accessToken":"claude-access","refreshToken":"claude-refresh","expiresAt":1900000000}"#.utf8))
        try await codex.withLease { try codex.saveCredentials(credentials()) }
        try await claude.withLease { try claude.saveCredentials(claudeToken) }
        _ = try await codex.fetch(CodexTokens.self, source: "app", renew: { $0 }, usage: { try await calls.usage($0) })
        _ = try await codex.fetch(CodexTokens.self, source: "widget", minimumAge: 60, renew: { $0 }, usage: { try await calls.usage($0) })
        let count = await calls.access.count
        XCTAssertEqual(count, 1)
        try await codex.withLease { try codex.clear() }
        XCTAssertEqual(try claude.load(ClaudeTokens.self)?.refreshToken, "claude-refresh")
        try await claude.withLease { try claude.clear() }
        try await clean(codex)
    }
}

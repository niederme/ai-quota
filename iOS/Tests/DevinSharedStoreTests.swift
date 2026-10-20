import XCTest
import MobileAccessCore
@testable import AIQuota_iOS

private func devinTokens() -> DevinTokens {
    DevinTokens(apiKey: "devin-session-token$test", apiServerURL: "https://server.codeium.com")
}
private func devinSample() -> QuotaReading {
    let usage = DevinUsage(dailyUsedPercent: 25, dailyResetsAt: .now.addingTimeInterval(3600),
                           weeklyUsedPercent: 40, weeklyResetsAt: .now.addingTimeInterval(86400 * 3),
                           planName: "Pro", accountDisplayName: nil, overageBalanceUSD: nil,
                           planStart: nil, planEnd: nil, source: .manual, fetchedAt: .now)
    return DevinAPI.makeReading(from: usage)
}

final class DevinSharedStoreTests: XCTestCase {
    private func store() -> SharedQuotaStore {
        let id = UUID().uuidString
        return SharedQuotaStore(.devin, root: FileManager.default.temporaryDirectory.appendingPathComponent(id), namespace: id)
    }
    private func clean(_ store: SharedQuotaStore) async throws {
        try await store.withLease { try store.clear() }
        if let root = store.root { try? FileManager.default.removeItem(at: root) }
    }

    /// The session token has no visible expiry — renewal must be a no-op so a
    /// widget/app never churns the Keychain or retries pointlessly.
    func testDevinTokenNeverNeedsRefresh() {
        XCTAssertFalse(devinTokens().needsRefresh(at: .now))
        XCTAssertFalse(devinTokens().needsRefresh(at: .distantFuture))
    }

    func testDevinCredentialsRoundTripAndReading() async throws {
        let store = store()
        try await store.withLease { try store.saveCredentials(devinTokens()) }
        let loaded: DevinTokens? = try store.load(DevinTokens.self)
        XCTAssertEqual(loaded?.apiKey, devinTokens().apiKey)
        let reading = try await store.fetch(DevinTokens.self, source: "app",
            renew: { $0 }, usage: { _ in devinSample() })
        XCTAssertEqual(reading.shortTerm?.usedPercent, 25)
        XCTAssertEqual(reading.weekly?.usedPercent, 40)
        XCTAssertEqual(reading.metadata?.plan, "Pro")
        XCTAssertEqual(store.reading(), reading)
        try await clean(store)
    }

    /// A rejected token is a reconnect condition: the identity renew cannot
    /// repair it, and the saved reading must survive the failed refresh.
    func testDevin401MarksReconnectButPreservesReading() async throws {
        let store = store()
        try await store.withLease { try store.saveCredentials(devinTokens()) }
        _ = try await store.fetch(DevinTokens.self, source: "app",
            renew: { $0 }, usage: { _ in devinSample() })
        XCTAssertEqual(store.reading()?.shortTerm?.usedPercent, 25)
        do {
            _ = try await store.fetch(DevinTokens.self, source: "app",
                renew: { $0 }, usage: { _ in throw AccessError.http(401) })
            XCTFail("401 should fail the fetch")
        } catch {
            XCTAssertEqual(store.failure(), .reconnect)
            XCTAssertEqual(store.reading()?.shortTerm?.usedPercent, 25)
        }
        try await clean(store)
    }
}

import XCTest
import SwiftUI
import MobileAccessCore
@testable import AIQuota_iOS

private actor ForegroundRequests {
    private(set) var minimumAges: [TimeInterval] = []
    var failure = false
    func setFailure() { failure = true }
    func fetch(_ forceRenewal: Bool, _ minimumAge: TimeInterval) async throws -> QuotaReading {
        minimumAges.append(minimumAge)
        try await Task.sleep(for: .milliseconds(150))
        if failure { throw AccessError.http(503) }
        return QuotaReading(fetchedAt: .now, shortTerm: nil, weekly: nil)
    }
}

@MainActor
final class ForegroundRefreshTests: XCTestCase {
    private var savedCache: Data?
    override func setUp() {
        super.setUp()
        savedCache = UserDefaults.standard.data(forKey: "mobileProbe.claudeReading")
    }
    override func tearDown() {
        UserDefaults.standard.set(savedCache, forKey: "mobileProbe.claudeReading")
        super.tearDown()
    }

    func testQuietForegroundDeduplicatesAndManualSuccessMakesOpenFresh() async throws {
        let (store, model, requests, original) = try await fixture()
        let before = try renderedCard(model)
        model.refreshOnOpen()
        XCTAssertEqual(try renderedCard(model), before)
        XCTAssertTrue(model.busy)
        XCTAssertFalse(model.loading)
        XCTAssertEqual(model.reading, original)
        model.refreshOnOpen()
        model.refresh()
        await model.refreshAndWait()
        var ages = await requests.minimumAges
        XCTAssertEqual(ages, [30])
        XCTAssertFalse(model.busy)
        model.refreshOnOpen()
        ages = await requests.minimumAges
        XCTAssertEqual(ages, [30])
        await model.refreshAndWait()
        ages = await requests.minimumAges
        XCTAssertEqual(ages, [30, 0])
        model.refreshOnOpen()
        XCTAssertFalse(model.busy)
        try await cleanup(store)
    }

    func testFailureRetainsReadingAndQuickForegroundRetryIsSuppressed() async throws {
        let (store, model, requests, original) = try await fixture()
        await requests.setFailure()
        model.refreshOnOpen()
        await model.refreshAndWait()
        XCTAssertNotNil(model.error)
        XCTAssertEqual(model.reading, original)
        model.refreshOnOpen()
        XCTAssertFalse(model.busy)
        let ages = await requests.minimumAges
        XCTAssertEqual(ages, [30])
        try await cleanup(store)
    }

    func testNewerWidgetSuccessIsAdoptedWithoutFetch() async throws {
        let (store, model, requests, _) = try await fixture()
        let recent = QuotaReading(fetchedAt: .now, shortTerm: nil, weekly: nil)
        _ = try await store.fetch(ClaudeTokens.self, source: "widget", renew: { $0 }, usage: { _ in recent })
        model.refreshOnOpen()
        XCTAssertEqual(model.reading, recent)
        XCTAssertFalse(model.busy)
        let ages = await requests.minimumAges
        XCTAssertTrue(ages.isEmpty)
        try await cleanup(store)
    }

    private func fixture() async throws -> (SharedQuotaStore, ClaudeProbeModel, ForegroundRequests, QuotaReading) {
        let id = UUID().uuidString
        let store = SharedQuotaStore(.claude, root: FileManager.default.temporaryDirectory.appendingPathComponent(id), namespace: id)
        let tokens = try JSONDecoder().decode(ClaudeTokens.self, from: Data(
            #"{"accessToken":"synthetic-access","refreshToken":"synthetic-refresh","expiresAt":1900000000}"#.utf8))
        try await store.withLease { try store.saveCredentials(tokens) }
        let old = try QuotaReading.decode(Data(
            #"{"rate_limit":{"primary_window":{"used_percent":42,"limit_window_seconds":18000},"secondary_window":{"used_percent":61,"limit_window_seconds":604800}}}"#.utf8), now: .now.addingTimeInterval(-31))
        _ = try await store.fetch(ClaudeTokens.self, source: "fixture", renew: { $0 }, usage: { _ in old })
        let requests = ForegroundRequests()
        let model = ClaudeProbeModel(shared: store, fetchUsage: { try await requests.fetch($0, $1) })
        return (store, model, requests, old)
    }
    private func renderedCard(_ model: ClaudeProbeModel) throws -> Data {
        let card = ProviderDialCardContent(name: "Claude", icon: "logo-claude", availableWidth: 370,
            reading: model.reading, connected: model.connected, busy: model.loading, error: model.error)
            .frame(width: 370).environment(\.colorScheme, .dark)
        return try XCTUnwrap(ImageRenderer(content: card).uiImage?.pngData())
    }
    private func cleanup(_ store: SharedQuotaStore) async throws {
        try await store.withLease { try store.clear() }
        if let root = store.root { try FileManager.default.removeItem(at: root) }
    }
}

@MainActor
final class ProfileModelIsolationTests: XCTestCase {
    private func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("profile-model-" + UUID().uuidString)
    }

    private nonisolated static func codexTokens(_ account: String) -> CodexTokens {
        CodexTokens(accessToken: "access-" + account, refreshToken: "refresh-" + account,
                    accountID: account, expiresAt: .now.addingTimeInterval(3600))
    }

    private nonisolated static func claudeTokens(_ account: String) throws -> ClaudeTokens {
        try JSONDecoder().decode(ClaudeTokens.self, from: Data(
            "{\"accessToken\":\"access-\(account)\",\"refreshToken\":\"refresh-\(account)\",\"expiresAt\":1900000000}".utf8))
    }

    private func reading(_ percent: Double) -> QuotaReading {
        QuotaReading(fetchedAt: .now, shortTerm: QuotaWindow(
            usedPercent: percent, durationSeconds: 300, resetsAt: .now.addingTimeInterval(300)), weekly: nil)
    }

    func testCodexProfileDisconnectKeepsOtherProfileCredentialsAndReading() async throws {
        let root = root()
        let first = AccountProfile(id: UUID().uuidString, service: .codex, label: "First", isLegacy: false)
        let second = AccountProfile(id: UUID().uuidString, service: .codex, label: "Second", isLegacy: false)
        let firstStore = SharedQuotaStore(first, root: root)
        let secondStore = SharedQuotaStore(second, root: root)
        try await firstStore.withLease { try firstStore.saveCredentials(Self.codexTokens("first")) }
        try await secondStore.withLease { try secondStore.saveCredentials(Self.codexTokens("second")) }
        let secondReading = reading(22)
        _ = try await secondStore.fetch(CodexTokens.self, source: "test", renew: { $0 }, usage: { _ in secondReading })

        let model = ProbeModel(shared: firstStore, profile: first)
        model.disconnect()
        await model.refreshAndWait()

        XCTAssertNil(try firstStore.load(CodexTokens.self))
        XCTAssertNil(firstStore.reading())
        XCTAssertEqual(try secondStore.load(CodexTokens.self)?.accountID, "second")
        XCTAssertEqual(secondStore.reading(), secondReading)
        try FileManager.default.removeItem(at: root)
    }

    func testClaudeProfileDisconnectKeepsOtherProfileCredentialsAndReading() async throws {
        let root = root()
        let first = AccountProfile(id: UUID().uuidString, service: .claude, label: "First", isLegacy: false)
        let second = AccountProfile(id: UUID().uuidString, service: .claude, label: "Second", isLegacy: false)
        let firstStore = SharedQuotaStore(first, root: root)
        let secondStore = SharedQuotaStore(second, root: root)
        try await firstStore.withLease { try firstStore.saveCredentials(try Self.claudeTokens("first")) }
        try await secondStore.withLease { try secondStore.saveCredentials(try Self.claudeTokens("second")) }
        let secondReading = reading(44)
        _ = try await secondStore.fetch(ClaudeTokens.self, source: "test", renew: { $0 }, usage: { _ in secondReading })

        let model = ClaudeProbeModel(shared: firstStore, profile: first)
        model.disconnect()
        await model.refreshAndWait()

        XCTAssertNil(try firstStore.load(ClaudeTokens.self))
        XCTAssertNil(firstStore.reading())
        XCTAssertEqual(try secondStore.load(ClaudeTokens.self)?.accessToken, "access-second")
        XCTAssertEqual(secondStore.reading(), secondReading)
        try FileManager.default.removeItem(at: root)
    }

    func testProfileFallbackCachesArePrivateAndIgnoreLegacyCache() async throws {
        let root = root()
        let suite = "profile-model-defaults-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = AccountProfile(id: UUID().uuidString, service: .claude, label: "First", isLegacy: false)
        let second = AccountProfile(id: UUID().uuidString, service: .claude, label: "Second", isLegacy: false)
        let firstStore = SharedQuotaStore(first, root: root)
        let secondStore = SharedQuotaStore(second, root: root)
        try await firstStore.withLease { try firstStore.saveCredentials(try Self.claudeTokens("first")) }
        try await secondStore.withLease { try secondStore.saveCredentials(try Self.claudeTokens("second")) }
        let firstReading = reading(11)
        let secondReading = reading(77)
        defaults.set(try JSONEncoder().encode(firstReading), forKey: "mobileProbe.claudeReading." + first.id)
        defaults.set(try JSONEncoder().encode(secondReading), forKey: "mobileProbe.claudeReading." + second.id)
        defaults.set(try JSONEncoder().encode(reading(99)), forKey: "mobileProbe.claudeReading")

        XCTAssertEqual(ClaudeProbeModel(shared: firstStore, defaults: defaults, profile: first).reading, firstReading)
        XCTAssertEqual(ClaudeProbeModel(shared: secondStore, defaults: defaults, profile: second).reading, secondReading)

        let third = AccountProfile(id: UUID().uuidString, service: .claude, label: "Third", isLegacy: false)
        let thirdStore = SharedQuotaStore(third, root: root)
        try await thirdStore.withLease { try thirdStore.saveCredentials(try Self.claudeTokens("third")) }
        XCTAssertNil(ClaudeProbeModel(shared: thirdStore, defaults: defaults, profile: third).reading)
        try FileManager.default.removeItem(at: root)
    }
}

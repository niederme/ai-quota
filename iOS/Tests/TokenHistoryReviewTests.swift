import XCTest
import SwiftUI
import MobileAccessCore
@testable import AIQuota_iOS

final class TokenHistoryReviewTests: XCTestCase {
    @MainActor func testAnnualGridNarrowLargeLightDark() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let history = try XCTUnwrap(DemoQuotaData.tokenHistory())
        XCTAssertEqual(history.days().count, 364)
        for width in [320.0, 440.0] {
            for (name, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
                let content = NavigationStack {
                    ScrollView {
                        VStack(spacing: 20) {
                            Text("Sample data · iOS layout verification").font(.caption)
                            CodexResetNoticeBanner(announcement: CodexResetNotice.demoAnnouncement, openDetails: {}, dismiss: {}, loading: false)
                            ProviderDialCardContent(name: "Codex", icon: "logo-openai", availableWidth: width - 32,
                                reading: DemoQuotaData.reading(.codex), connected: true, busy: false, error: nil,
                                tokenHistory: history)
                            ProviderDialCardContent(name: "Claude", icon: "logo-claude", availableWidth: width - 32,
                                reading: DemoQuotaData.reading(.claude), connected: true, busy: false, error: nil)
                        }.padding(16)
                    }.background { OverviewBackground().ignoresSafeArea() }
                        .navigationTitle("AIQuota").toolbarTitleDisplayMode(.inlineLarge)
                }.frame(width: width, height: 920).environment(\.colorScheme, scheme)
                let host = UIHostingController(rootView: content)
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: 0, y: 0, width: width, height: 920)
                window.rootViewController = host; window.makeKeyAndVisible()
                defer { window.isHidden = true; previous?.makeKey() }
                try await Task.sleep(for: .milliseconds(500))
                let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: 920))
                let image = renderer.image { _ in host.view.drawHierarchy(in: CGRect(x: 0,y: 0,width: width,height: 920), afterScreenUpdates: true) }
                let path = FileManager.default.temporaryDirectory.appendingPathComponent("ios-token-grid-\(Int(width))-\(name).png")
                try image.pngData()?.write(to: path)
                print("TOKEN_GRID_REVIEW " + path.path)
                XCTAssertEqual(image.size.width, width)
            }
        }
    }
    func testPresentationDoesNotConfuseMissingZeroOrFailure() throws {
        func history(_ buckets: String) throws -> CodexTokenHistory {
            try XCTUnwrap(CodexTokenHistory.decode(Data("{\"page\":{\"activity_graph\":{\"daily_usage_buckets\":\(buckets)}}}".utf8)))
        }
        let now = try XCTUnwrap(CodexTokenHistory.dateFormatter().date(from: "2026-10-09"))
        let empty = try history("[]")
        let zero = try history("[{\"start_date\":\"2026-10-08\",\"tokens\":0}]")
        let older = try history("[{\"start_date\":\"2020-01-01\",\"tokens\":100}]")
        let future = try history("[{\"start_date\":\"2027-01-01\",\"tokens\":100}]")
        XCTAssertEqual(MobileTokenHistoryView.presentation(history: nil, unavailable: false, loading: true, now: now), .loading)
        XCTAssertEqual(MobileTokenHistoryView.presentation(history: nil, unavailable: true, loading: false, now: now), .unavailable)
        for value in [empty, older, future] {
            XCTAssertEqual(MobileTokenHistoryView.presentation(history: value, unavailable: false, loading: false, now: now), .empty)
        }
        // An explicit zero is still a reported record. Saved records win over refresh status.
        for (unavailable, loading) in [(false, false), (true, false), (false, true)] {
            XCTAssertEqual(MobileTokenHistoryView.presentation(history: zero, unavailable: unavailable, loading: loading, now: now), .populated)
        }
        XCTAssertNil(zero.tokensByDate["2026-10-07"])
    }

    @MainActor func testEmptyLoadingErrorAndCachedTransitionsLightDark() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let populated = try XCTUnwrap(DemoQuotaData.tokenHistory())
        let empty = try XCTUnwrap(CodexTokenHistory.decode(Data("{\"page\":{\"activity_graph\":{\"daily_usage_buckets\":[]}}}".utf8)))
        let today = CodexTokenHistory.dateFormatter().string(from: .now)
        func todayHistory(tokens: Int) throws -> CodexTokenHistory {
            try XCTUnwrap(CodexTokenHistory.decode(Data("{\"page\":{\"activity_graph\":{\"daily_usage_buckets\":[{\"start_date\":\"\(today)\",\"tokens\":\(tokens)}]}}}".utf8)))
        }
        let states: [(String, CodexTokenHistory?, Bool, Bool)] = [
            ("loading", nil, false, true), ("empty", empty, false, false),
            ("unavailable", nil, true, false), ("populated", populated, false, false),
            ("refreshing", populated, false, true), ("saved", populated, true, false),
            ("today-zero", try todayHistory(tokens: 0), false, false),
            ("today-tokens", try todayHistory(tokens: 1200), false, false)
        ]
        for (theme, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            let host = UIHostingController(rootView: AnyView(EmptyView()))
            window.rootViewController = host; window.makeKeyAndVisible()
            defer { window.isHidden = true; previous?.makeKey() }
            for (state, history, unavailable, loading) in states {
                host.rootView = AnyView(NavigationStack {
                    ScrollView {
                        VStack(spacing: 20) {
                            Text("Sample data · \(state.capitalized) state").font(.caption).foregroundStyle(.secondary)
                            ProviderDialCardContent(name: "Codex", icon: "logo-openai", availableWidth: 361,
                                reading: DemoQuotaData.reading(.codex), connected: true, busy: false, error: nil,
                                tokenHistory: history, tokenHistoryUnavailable: unavailable, tokenHistoryLoading: loading)
                            ProviderDialCardContent(name: "Claude", icon: "logo-claude", availableWidth: 361,
                                reading: DemoQuotaData.reading(.claude), connected: true, busy: false, error: nil)
                        }.padding(16)
                    }.background { OverviewBackground().ignoresSafeArea() }
                        .navigationTitle("AIQuota").toolbarTitleDisplayMode(.inlineLarge)
                }.environment(\.colorScheme, scheme))
                try await Task.sleep(for: .milliseconds(350))
                let renderer = UIGraphicsImageRenderer(size: CGSize(width: 393, height: 852))
                let image = renderer.image { _ in host.view.drawHierarchy(in: CGRect(x: 0, y: 0, width: 393, height: 852), afterScreenUpdates: true) }
                let path = FileManager.default.temporaryDirectory.appendingPathComponent("ios-token-\(state)-\(theme).png")
                try image.pngData()?.write(to: path)
                print("TOKEN_STATE_REVIEW " + path.path)
                XCTAssertEqual(image.size.width, 393)
            }
        }
    }

    @MainActor func testPlaceholdersKeepTheSameHeightAndGraphHasNoFooter() throws {
        let populated = try XCTUnwrap(DemoQuotaData.tokenHistory())
        let empty = try XCTUnwrap(CodexTokenHistory.decode(Data("{\"page\":{\"activity_graph\":{\"daily_usage_buckets\":[]}}}".utf8)))
        for width in [256.0, 329.0, 376.0] {
            let heights = [(nil, true), (Optional(empty), false), (Optional(populated), false)].map { history, loading in
                let host = UIHostingController(rootView: MobileTokenHistoryView(history: history, unavailable: false, loading: loading, availableWidth: width))
                return host.sizeThatFits(in: CGSize(width: width, height: 1000)).height
            }
            XCTAssertEqual(heights[0], heights[1], accuracy: 1)
            XCTAssertLessThan(heights[2], heights[0])
        }
    }

}

private actor CachedProfileTransport: HTTPTransport {
    private var fails = false
    private let day = CodexTokenHistory.dateFormatter().string(from: .now)

    func setFailure(_ value: Bool) { fails = value }

    func send(_ request: URLRequest) async throws -> HTTPResult {
        if request.url?.path == "/backend-api/profiles/me/page" {
            try await Task.sleep(for: .milliseconds(120))
            if fails { throw URLError(.timedOut) }
            let count = request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "profile-b" ? 7 : 42
            return HTTPResult(data: Data("{\"page\":{\"activity_graph\":{\"daily_usage_buckets\":[{\"start_date\":\"\(day)\",\"tokens\":\(count)}]}}}".utf8), status: 200)
        }
        return HTTPResult(data: Data(#"{"data":[]}"#.utf8), status: 200)
    }
}

private func cachedProfileCredential(_ account: String, access: String = "synthetic") throws -> CodexTokens {
    try JSONDecoder().decode(CodexTokens.self, from: Data(
        "{\"accessToken\":\"\(access)\",\"accountID\":\"\(account)\",\"expiresAt\":1900000000}".utf8))
}

@MainActor
final class ProbeTokenHistoryCacheTests: XCTestCase {
    private func fixture() async throws -> (SharedQuotaStore, UserDefaults, CachedProfileTransport, QuotaReading) {
        let id = UUID().uuidString
        let store = SharedQuotaStore(.codex, root: FileManager.default.temporaryDirectory.appendingPathComponent(id), namespace: id)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "token-history-" + id))
        let reading = QuotaReading(fetchedAt: .now.addingTimeInterval(-31), shortTerm: nil, weekly: nil)
        defaults.set(try JSONEncoder().encode(reading), forKey: "mobileProbe.codexReading")
        let credential = try cachedProfileCredential("profile-a")
        try await store.withLease { try store.saveCredentials(credential) }
        return (store, defaults, CachedProfileTransport(), reading)
    }

    private func model(_ store: SharedQuotaStore, _ defaults: UserDefaults, _ transport: CachedProfileTransport,
                       _ reading: QuotaReading) -> ProbeModel {
        ProbeModel(api: CodexAPI(transport: transport), shared: store, defaults: defaults,
                   fetchUsage: { _, _ in reading })
    }

    private func cleanup(_ store: SharedQuotaStore, _ defaults: UserDefaults) async throws {
        try await store.withLease { try store.clear() }
        if let root = store.root { try FileManager.default.removeItem(at: root) }
        defaults.removePersistentDomain(forName: "token-history-" + store.namespace)
    }

    func testCachedReopenAndResumeKeepGraphThroughFailedRefresh() async throws {
        let (store, defaults, transport, reading) = try await fixture()
        let first = model(store, defaults, transport, reading)
        first.refresh()
        await first.refreshAndWait()
        XCTAssertEqual(first.tokenHistory?.tokensByDate[CodexTokenHistory.dateFormatter().string(from: .now)], 42)

        let reopened = model(store, defaults, transport, reading)
        XCTAssertEqual(reopened.reading, reading)
        XCTAssertEqual(reopened.tokenHistory?.tokensByDate[CodexTokenHistory.dateFormatter().string(from: .now)], 42)
        await transport.setFailure(true)
        reopened.refreshOnOpen()
        XCTAssertNotNil(reopened.tokenHistory, "Cached graph remains visible during the foreground refresh")
        await reopened.refreshAndWait()
        XCTAssertNotNil(reopened.tokenHistory)
        XCTAssertTrue(reopened.tokenHistoryUnavailable)
        XCTAssertEqual(MobileTokenHistoryView.presentation(history: reopened.tokenHistory, unavailable: true, loading: false), .populated)
        try await cleanup(store, defaults)
    }

    func testColdStartUsesSkeletonUntilValidProfileResponse() async throws {
        let (store, defaults, transport, reading) = try await fixture()
        let fresh = model(store, defaults, transport, reading)
        XCTAssertNil(fresh.tokenHistory)
        fresh.refreshOnOpen()
        XCTAssertEqual(MobileTokenHistoryView.presentation(history: fresh.tokenHistory, unavailable: false, loading: true), .loading)
        await fresh.refreshAndWait()
        XCTAssertNotNil(fresh.tokenHistory)
        try await cleanup(store, defaults)
    }

    func testRecentGaugeWithoutHistoryStillFetchesProfile() async throws {
        let (store, defaults, transport, _) = try await fixture()
        let recent = QuotaReading(fetchedAt: .now, shortTerm: nil, weekly: nil)
        defaults.set(try JSONEncoder().encode(recent), forKey: "mobileProbe.codexReading")
        let fresh = ProbeModel(api: CodexAPI(transport: transport), shared: store, defaults: defaults,
                               fetchUsage: { _, _ in throw AccessError.http(503) })
        XCTAssertNil(fresh.tokenHistory)
        fresh.refreshOnOpen()
        await fresh.refreshAndWait()
        XCTAssertNotNil(fresh.tokenHistory)
        XCTAssertNil(fresh.error, "A fresh cached gauge must not force a quota request to fetch profile history")
        try await cleanup(store, defaults)
    }

    func testQuotaRefreshFailureRetainsCachedGraphAndMarksItStale() async throws {
        let (store, defaults, transport, reading) = try await fixture()
        let first = model(store, defaults, transport, reading)
        first.refresh()
        await first.refreshAndWait()
        let reopened = ProbeModel(api: CodexAPI(transport: transport), shared: store, defaults: defaults,
                                  fetchUsage: { _, _ in throw AccessError.http(503) })
        XCTAssertNotNil(reopened.tokenHistory)
        reopened.refreshOnOpen()
        await reopened.refreshAndWait()
        XCTAssertEqual(reopened.tokenHistory?.tokensByDate[CodexTokenHistory.dateFormatter().string(from: .now)], 42)
        XCTAssertTrue(reopened.tokenHistoryUnavailable)
        XCTAssertNotNil(reopened.error)
        try await cleanup(store, defaults)
    }

    func testProfileSwitchDropsOldHistoryButTokenRenewalKeepsIt() async throws {
        let (store, defaults, transport, reading) = try await fixture()
        let first = model(store, defaults, transport, reading)
        first.refresh()
        await first.refreshAndWait()
        let reused = model(store, defaults, transport, reading)
        let renewed = try cachedProfileCredential("profile-a", access: "rotated")
        try await store.withLease { try store.saveCredentials(renewed) }
        reused.refreshOnOpen()
        XCTAssertNotNil(reused.tokenHistory)
        await reused.refreshAndWait()

        let otherProfile = try cachedProfileCredential("profile-b")
        try await store.withLease { try store.saveCredentials(otherProfile) }
        reused.refreshOnOpen()
        XCTAssertNil(reused.tokenHistory)
        await reused.refreshAndWait()
        XCTAssertEqual(reused.tokenHistory?.tokensByDate[CodexTokenHistory.dateFormatter().string(from: .now)], 7)
        let reopened = model(store, defaults, transport, reading)
        XCTAssertEqual(reopened.tokenHistory?.tokensByDate[CodexTokenHistory.dateFormatter().string(from: .now)], 7)
        try await cleanup(store, defaults)
    }
}

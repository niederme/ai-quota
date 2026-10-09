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
        let states: [(String, CodexTokenHistory?, Bool, Bool)] = [
            ("loading", nil, false, true), ("empty", empty, false, false),
            ("unavailable", nil, true, false), ("populated", populated, false, false),
            ("refreshing", populated, false, true), ("saved", populated, true, false)
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
                                tokenHistory: history, tokenHistoryUnavailable: unavailable, tokenHistoryLoading: loading,
                                retryTokenHistory: {})
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

    @MainActor func testInitialPlaceholderAndGraphKeepTheSameHeight() throws {
        let populated = try XCTUnwrap(DemoQuotaData.tokenHistory())
        let empty = try XCTUnwrap(CodexTokenHistory.decode(Data("{\"page\":{\"activity_graph\":{\"daily_usage_buckets\":[]}}}".utf8)))
        for width in [256.0, 329.0, 376.0] {
            let heights = [(nil, true), (Optional(empty), false), (Optional(populated), false)].map { history, loading in
                let host = UIHostingController(rootView: MobileTokenHistoryView(history: history, unavailable: false, loading: loading, availableWidth: width))
                return host.sizeThatFits(in: CGSize(width: width, height: 1000)).height
            }
            XCTAssertEqual(heights[0], heights[1], accuracy: 1)
            XCTAssertEqual(heights[0], heights[2], accuracy: 1)
        }
    }

}

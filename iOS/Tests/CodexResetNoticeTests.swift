import XCTest
import SwiftUI
import MobileAccessCore
@testable import AIQuota_iOS

private final class ResetNoticeURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (response, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor final class CodexResetNoticeTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-09-22T12:00:00Z")!
    private var fixture: Data {
        Data("""
        {"data":{"scheduled_reset":{"id":"notice-1","status":"scheduled","reset_type":"regular",
        "announced_at":"2026-09-22T04:31:32.000Z","scheduled_for":"2026-09-23T06:59:00.000Z",
        "source":{"type":"x_post","author":"thsottiaux","url":"https://x.com/thsottiaux/status/1"}},"latest_reset":null},
        "meta":{"api_version":"v1","generated_at":"2026-09-22T11:59:00.000Z"}}
        """.utf8)
    }
    private func store() -> CodexResetNotice {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ResetNoticeURLProtocol.self]
        return CodexResetNotice(session: URLSession(configuration: config))
    }
    func testPublicRequestThrottlingAndFailureClearsNotice() async {
        var calls = 0
        let data = fixture
        ResetNoticeURLProtocol.handler = { request in
            calls += 1
            XCTAssertEqual(request.url?.absoluteString, "https://codex-resets.com/api/v1/status")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertFalse(request.httpShouldHandleCookies)
            return (HTTPURLResponse(url: request.url!, statusCode: calls == 1 ? 200 : 503,
                                    httpVersion: nil, headerFields: nil)!, data)
        }
        defer { ResetNoticeURLProtocol.handler = nil }
        let notice = store()
        await notice.refresh(at: now)
        XCTAssertNotNil(notice.announcement(dismissedID: ""))
        XCTAssertNil(notice.announcement(dismissedID: "notice-1"))
        await notice.refresh(at: now.addingTimeInterval(60))
        XCTAssertEqual(calls, 1)
        await notice.refresh(at: now.addingTimeInterval(901))
        XCTAssertEqual(calls, 2)
        XCTAssertNil(notice.announcement(dismissedID: ""))
    }
    func testRateLimitBackoffAndStaleResponse() async {
        var calls = 0
        let data = fixture
        ResetNoticeURLProtocol.handler = { request in
            calls += 1
            return (HTTPURLResponse(url: request.url!, statusCode: calls == 1 ? 429 : 200,
                httpVersion: nil, headerFields: ["Retry-After":"3600"])!, data)
        }
        defer { ResetNoticeURLProtocol.handler = nil }
        let notice = store()
        await notice.refresh(at: now)
        await notice.refresh(at: now.addingTimeInterval(901))
        XCTAssertEqual(calls, 1)
        await notice.refresh(at: now.addingTimeInterval(3601))
        XCTAssertEqual(calls, 2)
        XCTAssertNil(notice.announcement(dismissedID: ""))
    }
    func testBannerVisualReview() async throws {
        let announcement = try XCTUnwrap(CodexResetStatus.decode(fixture).announcement(at: now))
        let reading = try JSONDecoder().decode(QuotaReading.self, from: Data("""
        {"fetchedAt":\(now.timeIntervalSinceReferenceDate),"weekly":{"usedPercent":83,"durationSeconds":604800}}
        """.utf8))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.windows.first(where: \.isKeyWindow)
        for (name, scheme, size) in [("dark", ColorScheme.dark, DynamicTypeSize.large),
                                      ("light", .light, .large), ("accessible", .dark, .accessibility3),
                                      ("loading", .dark, .large)] {
            let content = NavigationStack {
                ScrollView {
                    VStack(spacing: 24) {
                        CodexResetNoticeBanner(announcement: announcement, openDetails: {}, dismiss: {}, loading: name == "loading")
                        ProviderDialCardContent(name: "Codex", icon: "logo-openai", availableWidth: 370,
                            reading: reading, connected: true, busy: name == "loading", error: nil)
                    }.padding(16)
                }
                .background { OverviewBackground().ignoresSafeArea() }
                .navigationTitle("AI Quota").toolbarTitleDisplayMode(.inlineLarge)
            }.environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, size)
            let window = UIWindow(windowScene: scene)
            window.rootViewController = UIHostingController(rootView: content)
            window.makeKeyAndVisible()
            defer { window.isHidden = true; previous?.makeKey() }
            try await Task.sleep(for: .milliseconds(500))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("reset-notice-\(name).png")
            try image.pngData()?.write(to: path)
            print("RESET_NOTICE_REVIEW " + path.path)
        }
    }
}

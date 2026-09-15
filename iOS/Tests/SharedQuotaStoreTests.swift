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
private actor UnauthorizedCalls {
    var renewals = 0
    var attempts = 0
    let alwaysReject: Bool
    init(alwaysReject: Bool = false) { self.alwaysReject = alwaysReject }
    func renew(_ old: CodexTokens) throws -> CodexTokens {
        renewals += 1
        return try credentials()
    }
    func usage(_ token: CodexTokens) throws -> QuotaReading {
        attempts += 1
        if attempts == 1 || alwaysReject { throw AccessError.http(401) }
        return try sample()
    }
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
    func testUnexpiredTokenRenewsOnceAfter401() async throws {
        let store = store(), calls = UnauthorizedCalls()
        try await store.withLease { try store.saveCredentials(credentials()) }
        let value = try await store.fetch(CodexTokens.self, source: "app",
            renew: { try await calls.renew($0) }, usage: { try await calls.usage($0) })
        let renewals = await calls.renewals, attempts = await calls.attempts
        XCTAssertEqual(renewals, 1)
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(store.reading(), value)
        XCTAssertNil(store.failure())
        try await clean(store)
    }
    func testSecond401StopsAndPreservesSavedReading() async throws {
        let store = store(), calls = UnauthorizedCalls(alwaysReject: true)
        try await store.withLease { try store.saveCredentials(credentials()) }
        let saved = try await store.fetch(CodexTokens.self, source: "app", renew: { $0 }, usage: { _ in try sample() })
        do {
            _ = try await store.fetch(CodexTokens.self, source: "app",
                renew: { try await calls.renew($0) }, usage: { try await calls.usage($0) })
            XCTFail("Expected reconnection requirement")
        } catch { XCTAssertEqual(error as? AccessError, .http(401)) }
        let renewals = await calls.renewals, attempts = await calls.attempts
        XCTAssertEqual(renewals, 1)
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(store.failure(), .reconnect)
        XCTAssertEqual(store.reading(), saved)
        try await clean(store)
    }
    func testAlreadyRenewedTokenDoesNotRenewAgainAfter401() async throws {
        let store = store(), calls = UnauthorizedCalls(alwaysReject: true)
        try await store.withLease { try store.saveCredentials(credentials(expired: true)) }
        do {
            _ = try await store.fetch(CodexTokens.self, source: "app",
                renew: { try await calls.renew($0) }, usage: { try await calls.usage($0) })
            XCTFail("Expected reconnection requirement")
        } catch { XCTAssertEqual(error as? AccessError, .http(401)) }
        let renewals = await calls.renewals, attempts = await calls.attempts
        XCTAssertEqual(renewals, 1)
        XCTAssertEqual(attempts, 1)
        try await clean(store)
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

// Render representative long-metadata cards for visual review without provider access.
import SwiftUI
final class OverviewLayoutReviewTests: XCTestCase {
    @MainActor func testCardHeightDoesNotChangeWhileRefreshingOrLosingMetadata() throws {
        let full = try JSONDecoder().decode(QuotaReading.self, from: Data("""
        {"fetchedAt":\(Date.now.timeIntervalSinceReferenceDate),"shortTerm":{"usedPercent":98,"durationSeconds":18000,"resetsAt":\(Date.now.addingTimeInterval(3600).timeIntervalSinceReferenceDate)},"weekly":{"usedPercent":55,"durationSeconds":604800,"resetsAt":\(Date.now.addingTimeInterval(86400).timeIntervalSinceReferenceDate)},"metadata":{"plan":"Plus","balanceUSD":12.50,"usageSpent":45.12,"usageCurrency":"USD"}}
        """.utf8))
        let empty = try JSONDecoder().decode(QuotaReading.self, from: Data("""
        {"fetchedAt":\(Date.now.timeIntervalSinceReferenceDate),"shortTerm":{"usedPercent":18,"durationSeconds":18000},"weekly":{"usedPercent":55,"durationSeconds":604800}}
        """.utf8))
        for typeSize in [DynamicTypeSize.large, .xxxLarge, .accessibility3] {
            func card(_ reading: QuotaReading?, busy: Bool, failure: SharedQuotaStore.Failure? = nil, connected: Bool = true, error: String? = nil) -> some View {
                ProviderDialCardContent(name: "Codex", icon: "logo-openai", availableWidth: 338,
                    reading: reading, connected: connected, busy: busy, error: error, failure: failure)
            }
            func renderedSize<V: View>(_ view: V) throws -> CGSize {
                try XCTUnwrap(ImageRenderer(content: view.frame(width: 338).environment(\.dynamicTypeSize, typeSize)).uiImage).size
            }
            let idle = try renderedSize(card(full, busy: false))
            XCTAssertEqual(try renderedSize(card(full, busy: true)), idle)
            XCTAssertEqual(try renderedSize(card(empty, busy: false)), idle)
            for failure in [SharedQuotaStore.Failure.renewal, .reconnect, .temporary] {
                XCTAssertEqual(try renderedSize(card(full, busy: false, failure: failure)), idle)
            }
            XCTAssertEqual(try renderedSize(card(nil, busy: false)), idle)
            XCTAssertEqual(try renderedSize(card(nil, busy: false, connected: false)), idle)
            XCTAssertEqual(try renderedSize(card(full, busy: false, error: "Provider request failed (HTTP 401).")), idle)
            let pair = EqualHeightCardStack(spacing: 16) {
                card(full, busy: false)
                card(empty, busy: true, failure: .renewal)
            }
            let pairSize = try renderedSize(pair)
            XCTAssertEqual(pairSize.height, idle.height * 2 + 16, accuracy: 1)
            let renderer = ImageRenderer(content: pair.frame(width: 338).padding(20)
                .background(Color(uiColor: .systemGroupedBackground))
                .environment(\.colorScheme, .dark).environment(\.dynamicTypeSize, typeSize))
            renderer.scale = 2
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("overview-pair-\(typeSize).png")
            try XCTUnwrap(renderer.uiImage).pngData()?.write(to: path)
            print("PAIR_REVIEW " + path.path)
        }
    }
    @MainActor func testDisconnectedCardsOfferConnectAction() throws {
        for size in [DynamicTypeSize.large, .accessibility3] {
            let view = ProviderDialCardContent(name: "Claude Code", icon: "logo-claude", availableWidth: 362,
                reading: nil, connected: false, busy: false, error: nil,
                accountDestination: AnyView(Text("Claude sign-in")))
                .frame(width: 362).padding(20)
                .background(Color(uiColor: .systemGroupedBackground))
                .environment(\.colorScheme, .dark).environment(\.dynamicTypeSize, size)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            let attachment = XCTAttachment(image: image)
            attachment.name = "Disconnected Claude \(size)"; attachment.lifetime = .keepAlways
            add(attachment)
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("disconnected-\(size).png")
            try image.pngData()?.write(to: path)
            print("DISCONNECTED_REVIEW " + path.path)
        }
    }
    @MainActor func testSpendingPopoversPresentOnCards() async throws {
        let reading = try JSONDecoder().decode(QuotaReading.self, from: Data("""
        {"fetchedAt":\(Date.now.timeIntervalSinceReferenceDate),"weekly":{"usedPercent":59,"durationSeconds":604800,"resetsAt":\(Date.now.addingTimeInterval(3600).timeIntervalSinceReferenceDate)},"metadata":{"plan":"Pro","balanceUSD":10.44,"usageSpent":15.58,"usageCurrency":"USD"}}
        """.utf8))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.windows.first(where: \.isKeyWindow)
        for (name, icon, explanation) in [("Codex", "logo-openai", MetadataExplanation.codexSpend),
                                          ("Claude Code", "logo-claude", .claudeSpend)] {
            let view = NavigationStack {
                ProviderDialCardContent(name: name, icon: icon, availableWidth: 362,
                    reading: reading, connected: true, busy: false, error: nil,
                    accountDestination: AnyView(Text("Account details")), info: explanation)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(20)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .navigationTitle("AI Quota").toolbarTitleDisplayMode(.inlineLarge)
            }.tint(Color(uiColor: .systemPurple))
            let host = UIHostingController(rootView: view)
            let window = UIWindow(windowScene: scene)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true; previous?.makeKey() }
            try await Task.sleep(for: .milliseconds(800))
            XCTAssertNotNil(host.presentedViewController, "The info button must present a popover independently of account navigation.")
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "\(name) spending popover"; attachment.lifetime = .keepAlways
            add(attachment)
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("popover-\(explanation.rawValue).png")
            try image.pngData()?.write(to: path)
            print("POPOVER_REVIEW " + path.path)
        }
    }
    @MainActor func testOverviewAppearances() throws {
        for (name, percent, scheme) in [
            ("purple-dark", 42.0, ColorScheme.dark),
            ("orange-light", 87.0, .light),
            ("red-dark", 100.0, .dark)
        ] {
            let raw = """
            {"fetchedAt":\(Date.now.timeIntervalSinceReferenceDate),"shortTerm":{"usedPercent":\(percent),"durationSeconds":18000,"resetsAt":800003600},"weekly":{"usedPercent":47,"durationSeconds":604800,"resetsAt":800086400},"metadata":{"plan":"Plus","balanceUSD":9.75,"usageSpent":93.77,"usageCurrency":"USD"}}
            """
            let reading = try JSONDecoder().decode(QuotaReading.self, from: Data(raw.utf8))
            let view = ProviderDialCardContent(name: "Codex", icon: "logo-openai", availableWidth: 362,
                reading: reading, connected: true, busy: false, error: nil)
                .frame(width: 362).padding(20)
                .background(Color(uiColor: .systemGroupedBackground))
                .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertLessThan(image.size.height, 450, "Metadata must remain beside the gauge at phone width.")
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("aiquota-" + name + ".png")
            try image.pngData()?.write(to: path)
            print("LAYOUT_REVIEW " + path.path)
        }
    }
}

final class WidgetLayoutReviewTests: XCTestCase {
    @MainActor func testMixedWidgetProportions() throws {
        let reading = try sample()
        for service in QuotaService.allCases {
            let value = ProviderReading(service: service, reading: reading, needsApp: false)
            let view = HStack(spacing: 16) {
                ServiceDetailsView(value: value, date: .now).frame(width: 160, height: 56)
                CodexDial(value: value, date: .now, logoScale: 0.8).frame(width: 56, height: 56)
                CodexDial(value: value, date: .now).frame(width: 56, height: 56)
            }.padding(12).background(Color.black).environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 3
            let image = try XCTUnwrap(renderer.uiImage)
            let attachment = XCTAttachment(image: image)
            attachment.name = "Mixed widgets " + service.name
            attachment.lifetime = .keepAlways
            add(attachment)
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("widgets-" + service.rawValue + ".png")
            try image.pngData()?.write(to: path)
            print("LAYOUT_REVIEW " + path.path)
        }
    }
}

final class ConnectionStateTests: XCTestCase {
    func testFailurePersistsWithoutDeletingReadingAndClearsAfterSuccess() async throws {
        let id = UUID().uuidString
        let store = SharedQuotaStore(.claude, root: FileManager.default.temporaryDirectory.appendingPathComponent(id), namespace: id)
        try await store.withLease { try store.saveCredentials(credentials()) }
        let saved = try await store.fetch(CodexTokens.self, source: "test", renew: { $0 }, usage: { _ in try sample() })
        for (failure, expected) in [(ClaudeAccessError.renewalRejected(status: 400, reason: nil), SharedQuotaStore.Failure.renewal), (.reconnectRequired, .reconnect)] {
            do {
                _ = try await store.fetch(CodexTokens.self, source: "test", forceRenewal: true, renew: { _ in throw failure }, usage: { _ in try sample() })
                XCTFail("Expected failure")
            } catch {}
            XCTAssertEqual(store.failure(), expected)
            XCTAssertEqual(store.reading(), saved)
            XCTAssertNotNil(try store.load(CodexTokens.self))
        }
        _ = try await store.fetch(CodexTokens.self, source: "test", renew: { $0 }, usage: { _ in try sample() })
        XCTAssertNil(store.failure())
        try await store.withLease { try store.clear() }
        try? FileManager.default.removeItem(at: store.root!)
    }
    func testNetworkAndGenericBadRequestAreNotDisconnected() {
        XCTAssertEqual(SharedQuotaStore.Failure.classify(URLError(.notConnectedToInternet)), .temporary)
        XCTAssertEqual(SharedQuotaStore.Failure.classify(ClaudeAccessError.requestFailed(stage: "usage update", status: 400)), .temporary)
        XCTAssertEqual(SharedQuotaStore.Failure.classify(ClaudeAccessError.reconnectRequired), .reconnect)
    }
    func testResetPlanRejectsStalePastAndEmptyReadingsAndUsesStableIDs() throws {
        let now = Date.now
        func reading(age: Double, reset: Double, used: Int) throws -> QuotaReading {
            try JSONDecoder().decode(QuotaReading.self, from: Data("""
            {"fetchedAt":\(now.addingTimeInterval(-age).timeIntervalSinceReferenceDate),"shortTerm":{"usedPercent":\(used),"durationSeconds":18000,"resetsAt":\(now.addingTimeInterval(reset).timeIntervalSinceReferenceDate)}}
            """.utf8))
        }
        XCTAssertEqual(MobileResetNotifications.planned(try reading(age: 1, reset: 3600, used: 95), now: now).count, 1)
        for (age, reset, used) in [(1801.0, 3600.0, 42), (1, -1, 42), (1, 3600, 0)] {
            XCTAssertTrue(MobileResetNotifications.planned(try reading(age: age, reset: reset, used: used), now: now).isEmpty)
        }
        XCTAssertTrue(MobileResetNotifications.planned(nil, now: now).isEmpty)
        XCTAssertNotEqual(MobileResetNotifications.identifier(.claude, "5h"), MobileResetNotifications.identifier(.codex, "5h"))
        XCTAssertNotEqual(MobileResetNotifications.identifier(.claude, "5h"), MobileResetNotifications.identifier(.claude, "7d"))
    }
    @MainActor func testRenewalStateRender() throws {
        let content = ProviderDialCardContent(name: "Claude", icon: "logo-claude", availableWidth: 362,
            reading: try sample(), connected: true, busy: false, error: nil, failure: .renewal)
            .frame(width: 362).padding(20).background(Color(uiColor: .systemGroupedBackground))
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("renewal-state.png")
        try image.pngData()?.write(to: path)
        print("STATE_REVIEW " + path.path)
    }
}

private actor ReminderRecorder {
    var pending: [String: Date] = [:]
    func schedule(_ id: String, date: Date) { pending[id] = date }
    func remove(_ id: String) { pending.removeValue(forKey: id) }
}
final class ResetSchedulingTests: XCTestCase {
    func testReplaceCancelAndProviderIsolation() async throws {
        let recorder = ReminderRecorder()
        let first = Date.now.addingTimeInterval(3600), changed = first.addingTimeInterval(60)
        func apply(_ service: QuotaService, _ plan: [(String, Date)]) async throws {
            try await MobileResetNotifications.apply(service, plan: plan,
                remove: { await recorder.remove($0) }, schedule: { id, _, date in await recorder.schedule(id, date: date) })
        }
        try await apply(.claude, [("5h", first), ("7d", first)])
        try await apply(.claude, [("5h", changed), ("7d", first)])
        var pending = await recorder.pending
        XCTAssertEqual(pending.count, 2)
        XCTAssertEqual(pending[MobileResetNotifications.identifier(.claude, "5h")], changed)
        try await apply(.codex, [("5h", first)])
        // Empty plans represent disabled, disconnected, stale, or unavailable windows.
        try await apply(.claude, [])
        pending = await recorder.pending
        XCTAssertEqual(pending.count, 1)
        XCTAssertNotNil(pending[MobileResetNotifications.identifier(.codex, "5h")])
        try await apply(.codex, [])
        let empty = await recorder.pending.isEmpty
        XCTAssertTrue(empty)
    }
}

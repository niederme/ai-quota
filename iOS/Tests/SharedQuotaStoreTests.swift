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
private func sample(usedPercent: Int) throws -> QuotaReading {
    try QuotaReading.decode(Data("""
    {"rate_limit":{"primary_window":{"used_percent":\(usedPercent),"limit_window_seconds":18000},"secondary_window":{"used_percent":50,"limit_window_seconds":604800}}}
    """.utf8), now: .now)
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
private actor ClaudeUnauthorizedCalls {
    var renewals = 0
    var attempts = 0
    func renew(_ old: CodexTokens) throws -> CodexTokens {
        renewals += 1
        return try credentials()
    }
    func usage(_ token: CodexTokens) throws -> QuotaReading {
        attempts += 1
        if attempts == 1 { throw ClaudeAccessError.requestFailed(stage: "usage update", status: 401) }
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
    func testForegroundReusesWidgetSuccessButManualRefreshFetches() async throws {
        let store = store()
        try await store.withLease { try store.saveCredentials(credentials()) }
        let calls = Calls()
        let widget = try await store.fetch(CodexTokens.self, source: "widget", renew: { $0 }, usage: { try await calls.usage($0) })
        let foreground = try await store.fetch(CodexTokens.self, source: "app", minimumAge: 30, renew: { $0 }, usage: { try await calls.usage($0) })
        XCTAssertEqual(foreground, widget)
        XCTAssertEqual(foreground.fetchedAt, widget.fetchedAt)
        let afterForeground = await calls.access.count
        XCTAssertEqual(afterForeground, 1)
        _ = try await store.fetch(CodexTokens.self, source: "app", minimumAge: 0, renew: { $0 }, usage: { try await calls.usage($0) })
        let afterManual = await calls.access.count
        XCTAssertEqual(afterManual, 2)
        try await clean(store)
    }

    func testClaudeRateLimitBlocksAppWidgetAndBackgroundRequests() async throws {
        let store = store(.claude)
        try await store.withLease { try store.saveCredentials(credentials()) }
        do {
            _ = try await store.fetch(CodexTokens.self, source: "app", renew: { $0 }, usage: { _ in
                throw ClaudeAccessError.requestFailed(stage: "usage update", status: 429)
            })
            XCTFail("Expected rate limit")
        } catch { }
        let cooldown = try XCTUnwrap(store.cooldownURL)
        let original = try Data(contentsOf: cooldown)
        for source in ["app", "widget", "background"] {
            do {
                _ = try await store.fetch(CodexTokens.self, source: source, renew: { $0 }, usage: { _ in
                    XCTFail("Cooldown must prevent a request")
                    return try sample()
                })
                XCTFail("Expected cooldown")
            } catch { }
        }
        XCTAssertEqual(try Data(contentsOf: cooldown), original)
        try JSONEncoder().encode(Date.distantPast).write(to: cooldown)
        _ = try await store.fetch(CodexTokens.self, source: "app", renew: { $0 }, usage: { _ in try sample() })
        XCTAssertNil(store.failure())
        try await clean(store)
    }
    func testResetClearsClaudeCooldownAndWidgetCannotRestoreFailure() async throws {
        let store = store(.claude)
        try await store.withLease { try store.saveCredentials(credentials()) }
        do {
            _ = try await store.fetch(CodexTokens.self, source: "app", renew: { $0 }, usage: { _ in
                throw ClaudeAccessError.requestFailed(stage: "usage update", status: 429)
            })
            XCTFail("Expected rate limit")
        } catch { }
        XCTAssertTrue(store.updatesPaused)
        try await store.withLease { try store.clear() }
        XCTAssertFalse(store.updatesPaused)
        XCTAssertNil(store.failure())
        do {
            _ = try await store.fetch(CodexTokens.self, source: "widget", renew: { $0 }, usage: { _ in
                XCTFail("Signed-out refresh must not call the provider")
                return try sample()
            })
            XCTFail("Expected signed-out refresh to stop")
        } catch { }
        XCTAssertNil(store.failure())
        XCTAssertNil(try store.load(CodexTokens.self))
        let restored = await ClaudeProbeModel(shared: store)
        let failure = await restored.connectionFailure
        let connected = await restored.connected
        XCTAssertNil(failure)
        XCTAssertFalse(connected)
        try await clean(store)
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
    func testClaudeUnexpiredTokenRenewsOnceAfter401() async throws {
        let store = store(.claude), calls = ClaudeUnauthorizedCalls()
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
        let folder = try XCTUnwrap(store.root?.appendingPathComponent("widget-diagnostics").appendingPathComponent(store.namespace))
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

    func testProfilesOfSameProviderKeepCredentialsReadingsAndFailuresIsolated() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let live = SharedQuotaStore(.codex, root: root)
        let second = SharedQuotaStore(.codex, root: root, namespace: UUID().uuidString)
        try await live.withLease { try live.saveCredentials(credentials()) }
        let secondCredentials = try JSONDecoder().decode(
            CodexTokens.self,
            from: Data(#"{"accessToken":"second-access","refreshToken":"second-refresh","expiresAt":1900000000}"#.utf8)
        )
        try await second.withLease { try second.saveCredentials(secondCredentials) }

        _ = try await live.fetch(CodexTokens.self, source: "test", renew: { $0 }, usage: { _ in try sample(usedPercent: 12) })
        _ = try await second.fetch(CodexTokens.self, source: "test", renew: { $0 }, usage: { _ in try sample(usedPercent: 78) })
        XCTAssertEqual(live.reading()?.shortTerm?.usedPercent, 12)
        XCTAssertEqual(second.reading()?.shortTerm?.usedPercent, 78)
        XCTAssertNotEqual(live.readingURL, second.readingURL)
        XCTAssertEqual(try live.load(CodexTokens.self)?.refreshToken, "new-refresh")
        XCTAssertEqual(try second.load(CodexTokens.self)?.refreshToken, "second-refresh")

        do {
            _ = try await second.fetch(CodexTokens.self, source: "test", renew: { $0 }, usage: { _ in
                throw AccessError.http(503)
            })
            XCTFail("Expected provider failure")
        } catch { }
        XCTAssertNil(live.failure())
        XCTAssertEqual(second.failure(), .temporary)

        try await second.withLease { try second.clear() }
        XCTAssertNotNil(live.reading())
        XCTAssertNotNil(try live.load(CodexTokens.self))
        try await live.withLease { try live.clear() }
        try? FileManager.default.removeItem(at: root)
    }
}

final class AccountRegistryTests: XCTestCase {
    private func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    func testLegacyMigrationCreatesOnlyDetectedProviderAndPersistsDefault() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let migrating = AccountRegistry.Store(root: root, legacyServices: [.claude])

        XCTAssertEqual(migrating.all(), [
            AccountProfile(id: "live", service: .claude, label: "Claude", isLegacy: true, suggestedNamePending: true)
        ])
        XCTAssertEqual(migrating.defaultProfile(for: .claude)?.id, "live")
        XCTAssertNil(migrating.defaultProfile(for: .codex))

        // Once recorded, later evidence cannot cause a second migration.
        let reopened = AccountRegistry.Store(root: root, legacyServices: [.codex])
        XCTAssertEqual(reopened.all(), migrating.all())
        XCTAssertNil(reopened.defaultProfile(for: .codex))
    }

    func testFreshInstallRemainsEmptyAndFirstAddedProviderUsesLive() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = AccountRegistry.Store(root: root, legacyServices: [])

        XCTAssertTrue(registry.all().isEmpty)
        let first = registry.add(service: .codex)
        let second = registry.add(service: .codex)
        XCTAssertEqual(first.id, "live")
        XCTAssertTrue(first.isLegacy)
        XCTAssertNotEqual(second.id, "live")
        XCTAssertFalse(second.isLegacy)
        XCTAssertEqual(registry.defaultProfile(for: .codex), first)
    }

    func testCompositeMutationsDoNotChangeOtherProvidersLiveProfile() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = AccountRegistry.Store(root: root, legacyServices: [.codex, .claude])
        registry.rename(service: .codex, id: "live", label: "Work")
        registry.setProviderIdentity(service: .codex, id: "live", identity: "member@example.com")

        XCTAssertEqual(registry.defaultProfile(for: .codex)?.label, "Work")
        XCTAssertEqual(registry.defaultProfile(for: .codex)?.providerIdentity, "member@example.com")
        XCTAssertEqual(registry.defaultProfile(for: .claude)?.label, "Claude")
        XCTAssertNil(registry.defaultProfile(for: .claude)?.providerIdentity)
    }

    func testExtensionEmptyReadDoesNotFinalizeMigrationBeforeApp() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let widget = AccountRegistry.Store(root: root, legacyServices: [], persistEmptyMigration: false)
        XCTAssertTrue(widget.all().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("account-registry-v1.json").path))

        let app = AccountRegistry.Store(root: root, legacyServices: [.codex])
        XCTAssertEqual(app.all(), [
            AccountProfile(id: "live", service: .codex, label: "Codex", isLegacy: true, suggestedNamePending: true)
        ])
    }

    func testConcurrentAddsPreserveEveryProfile() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = AccountRegistry.Store(root: root, legacyServices: [])
        await withTaskGroup(of: AccountProfile.self) { group in
            for _ in 0..<8 { group.addTask { registry.add(service: .claude) } }
            for await _ in group { }
        }
        let profiles = registry.profiles(for: .claude)
        XCTAssertEqual(profiles.count, 8)
        XCTAssertEqual(Set(profiles.map(\.id)).count, 8)
        XCTAssertEqual(profiles.filter { $0.id == "live" }.count, 1)
    }

    func testServiceOrderAndDefaultAccountPersistAcrossLoads() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = AccountRegistry.Store(root: root, legacyServices: [])
        _ = registry.add(service: .codex)
        let work = registry.add(service: .codex)
        registry.setDefault(service: .codex, id: work.id)
        registry.setServiceOrder([.claude, .codex])

        let reopened = AccountRegistry.Store(root: root, legacyServices: [])
        XCTAssertEqual(reopened.defaultProfile(for: .codex)?.id, work.id)
        XCTAssertEqual(reopened.serviceOrder(), [.claude, .codex])
    }
}

// Render representative long-metadata cards for visual review without provider access.
import SwiftUI
final class OverviewLayoutReviewTests: XCTestCase {
    @MainActor func testRefreshPreservesCompactSummaryHeight() throws {
        let reading = try sample()
        for typeSize in [DynamicTypeSize.large, .xxxLarge, .accessibility3] {
            func size(busy: Bool) throws -> CGSize {
                let card = ProviderDialCardContent(name: "Claude", icon: "logo-claude", availableWidth: 370,
                    reading: reading, connected: true, busy: busy, error: nil)
                    .frame(width: 370).environment(\.dynamicTypeSize, typeSize)
                return try XCTUnwrap(ImageRenderer(content: card).uiImage).size
            }
            XCTAssertEqual(try size(busy: false), try size(busy: true))
        }
    }
    @MainActor func testDisconnectedAndExpiredCardsOfferConnectionAction() throws {
        for expired in [false, true] {
            for size in [DynamicTypeSize.large, .accessibility3] {
                let view = ProviderDialCardContent(name: "Claude Code", icon: "logo-claude", availableWidth: 362,
                    reading: expired ? try sample() : nil, connected: expired, busy: false, error: nil,
                    failure: expired ? .reconnect : nil, onOpen: {}, onReconnect: {})
                    .frame(width: 362).padding(20)
                    .background(Color(uiColor: .systemGroupedBackground))
                    .environment(\.colorScheme, .dark).environment(\.dynamicTypeSize, size)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.uiImage)
                let attachment = XCTAttachment(image: image)
                attachment.name = "Connection Claude expired=\(expired) \(size)"; attachment.lifetime = .keepAlways
                add(attachment)
                let path = FileManager.default.temporaryDirectory.appendingPathComponent("connection-expired-\(expired)-\(size).png")
                try image.pngData()?.write(to: path)
                print("DISCONNECTED_REVIEW " + path.path)
            }
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
        XCTAssertEqual(MobileResetNotifications.identifier(.codex, "5h"), "quota.reset.codex.5h")
        XCTAssertNotEqual(
            MobileResetNotifications.identifier(.codex, "5h", namespace: "second"),
            MobileResetNotifications.identifier(.codex, "5h")
        )
        XCTAssertEqual(MobileResetNotifications.windowPrefix(.codex, "5h"), "notifications.codex.5h.")
        XCTAssertEqual(
            MobileResetNotifications.windowPrefix(.codex, "5h", namespace: "second"),
            "notifications.codex.second.5h."
        )
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

extension SharedQuotaStoreTests {
    func testWidgetHistoryRemainsAccountScopedAndClearsOnDisconnect() async throws {
        let first = store()
        let second = SharedQuotaStore(.codex, root: first.root, namespace: "second-account")
        let credential = CodexTokens(accessToken: "fixture-a", refreshToken: nil, accountID: "workspace-a", expiresAt: .distantFuture)
        let other = CodexTokens(accessToken: "fixture-b", refreshToken: nil, accountID: "workspace-b", expiresAt: .distantFuture)
        try await first.withLease { try first.saveCredentials(credential) }
        try await second.withLease { try second.saveCredentials(other) }
        let tokens = try XCTUnwrap(CodexTokenHistory.decode(Data(#"{"page":{"activity_graph":{"daily_usage_buckets":[{"start_date":"2026-10-28","tokens":1200}]}}}"#.utf8), scopeID: CodexAPI.tokenHistoryScope(credential)))
        try await first.publishWidgetHistory(tokens: tokens, matching: credential)
        XCTAssertEqual(first.widgetHistory()?.tokens?.tokensByDate["2026-10-28"], 1200)
        XCTAssertNil(second.widgetHistory())
        // A late completion for the old workspace cannot publish into the new one.
        try await first.withLease { try first.saveCredentials(other) }
        XCTAssertNil(first.widgetHistory())
        try await first.publishWidgetHistory(tokens: tokens, matching: credential)
        XCTAssertNil(first.widgetHistory())
        try await first.withLease { try first.clear() }
        try await first.withLease { try first.saveCredentials(credential) }
        XCTAssertNil(first.widgetHistory())
        try await clean(second)
        try await clean(first)
    }
}

// Run with scripts/test-claude-account-lifecycle.py. No app, credential store,
// defaults, WebKit session or external network is used by this executable.
import Foundation
@testable import AIQuotaKit

final class Memory<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func read() -> Value { lock.withLock { value } }
    @discardableResult func edit<T>(_ action: (inout Value) -> T) -> T { lock.withLock { action(&value) } }
}

actor Gate<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Error>?
    var waiting: Bool { continuation != nil }
    func wait() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func finish(_ result: Result<Value, Error>) { continuation?.resume(with: result); continuation = nil }
}

struct DummyAuth: Sendable {
    var context: SharedClaudeAuthContext?
    var signedOut = false
}

func coordinator(_ memory: Memory<DummyAuth>, org: String? = nil,
                 login: @escaping ClaudeAuthCoordinator.LoginWindowRunner) -> ClaudeAuthCoordinator {
    ClaudeAuthCoordinator(
        accountStorageID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
        probe: { org.map { .found(orgId: $0, cookies: []) } ?? .notFound },
        headlessSessionReviver: { .notFound },
        oauthCredentialsLoader: { _ in throw ClaudeOAuthCredentialsError.notFound },
        keychainAccessAllowed: { false }, sessionValidator: { _ in .invalid },
        webSessionClearer: {}, webSessionRestorer: { _ in }, loginWindowRunner: login,
        contextWriter: { context in memory.edit { $0.context = context } },
        signedOutReader: { memory.read().signedOut },
        signedOutWriter: { value in memory.edit { $0.signedOut = value } },
        webSessionResetter: {}, webSessionVerifier: { true }
    )
}

// Fail closed: every request is consumed in-process. Unknown/unexpected requests
// cannot fall through to a real URL loading protocol or socket.
final class DummyWire: URLProtocol, @unchecked Sendable {
    static let pending = Memory<[DummyWire]>([])
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.pending.edit { $0.append(self) } }
    override func stopLoading() {}
    static func take() async throws -> DummyWire {
        for _ in 0..<2_000 {
            if let item = pending.edit({ $0.isEmpty ? nil : $0.removeFirst() }) { return item }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw CheckFailure(message: "dummy request did not arrive")
    }
    func finish(status: Int = 200, body: String) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

struct DummyWidget: Sendable {
    var codex: SharedCodexAuthContext?
    var claude: SharedClaudeAuthContext?
    var codexUsage: CodexUsage?
    var claudeUsage: ClaudeUsage?
}

func widget(_ memory: Memory<DummyWidget>) -> WidgetRefreshService {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [DummyWire.self]
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCache = nil
    return WidgetRefreshService(session: URLSession(configuration: configuration), store: .init(
        codexContext: { memory.read().codex }, claudeContext: { memory.read().claude },
        codexUsage: { memory.read().codexUsage }, claudeUsage: { memory.read().claudeUsage },
        commitCodex: { expected, renewed, usage in memory.edit { value in
            guard value.codex == expected else { return false }
            if let renewed { value.codex = renewed }
            if let usage { value.codexUsage = usage }
            return true
        } },
        commitClaude: { expected, usage in memory.edit { value in
            guard value.claude == expected else { return false }
            value.claudeUsage = usage; return true
        } },
        clearCodex: { expected in memory.edit { value in
            if value.codex == expected { value.codex = nil; value.codexUsage = nil }
        } },
        clearClaude: { expected in memory.edit { value in
            if value.claude == expected { value.claude = nil; value.claudeUsage = nil }
        } }
    ))
}

struct CheckFailure: Error { let message: String }
func require(_ value: Bool, _ message: String) throws { if !value { throw CheckFailure(message: message) } }

@main enum ClaudeLifecycleDummyChecks {
    static let a = "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa"
    static let b = "bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb"
    static func codexBody(_ id: String) -> String {
        "{\"account_id\":\"\(id)\",\"plan_type\":\"plus\",\"rate_limit\":{\"primary_window\":{\"used_percent\":12,\"reset_at\":2000000000,\"reset_after_seconds\":3600,\"limit_window_seconds\":604800},\"secondary_window\":null}}"
    }
    static let claudeBody = "{\"five_hour\":{\"utilization\":12},\"seven_day\":{\"utilization\":24}}"
    static func cookie(_ value: String) -> PersistedCookie {
        PersistedCookie(HTTPCookie(properties: [.name: "sessionKey", .value: value, .domain: ".invalid", .path: "/", .secure: "TRUE"])!)
    }
    static func codex(_ id: String, expired: Bool = false) -> SharedCodexAuthContext {
        .init(sessionToken: "dummy-session-\(id)", accessToken: "dummy-token-\(id)",
              accessTokenExpiresAt: Date.now.addingTimeInterval(expired ? -100 : 3600), accountID: id)
    }
    static func main() async throws {
        var checks = 0
        // Reconnect is legal for a saved but currently disconnected card. An
        // unexpected organization is rejected before persistence/authentication.
        for initialOrg in [nil, a] as [String?] {
            let memory = Memory(DummyAuth())
            let sut = coordinator(memory, org: initialOrg) { (b, []) }
            await sut.bootstrap()
            do { try await sut.reconnectWithWebAuthentication(expectedOrganizationID: a); throw CheckFailure(message: "mismatch accepted") }
            catch ClaudeWebReconnectError.organizationMismatch {}
            try require(memory.read().context?.orgId == initialOrg, "mismatch replaced persisted organization")
            try require(await sut.state == (initialOrg == nil ? .unauthenticated : .authenticated), "mismatch changed prior state")
            checks += 1
        }
        for initialOrg in [nil, a] as [String?] {
            let memory = Memory(DummyAuth())
            let sut = coordinator(memory, org: initialOrg) { throw CancellationError() }
            await sut.bootstrap()
            do { try await sut.reconnectWithWebAuthentication(expectedOrganizationID: a); throw CheckFailure(message: "cancel accepted") }
            catch is CancellationError {}
            try require(memory.read().context?.orgId == initialOrg, "cancel replaced prior connection")
            try require(await sut.state == (initialOrg == nil ? .unauthenticated : .authenticated), "cancel changed prior state")
            checks += 1
        }
        let matching = Memory(DummyAuth(signedOut: true))
        let matchingSUT = coordinator(matching) { (a.uppercased(), []) }
        await matchingSUT.bootstrap()
        try await matchingSUT.reconnectWithWebAuthentication(expectedOrganizationID: a)
        try require(matching.read().context?.orgId == a && !matching.read().signedOut, "matching reconnect failed")
        checks += 1

        // Reset must finish without waiting for the suspended login window;
        // neither its late success nor cancellation may restore old credentials.
        for lateSuccess in [true, false] {
            let memory = Memory(DummyAuth())
            let gate = Gate<(orgId: String, cookies: [HTTPCookie])>()
            let sut = coordinator(memory, org: a) { try await gate.wait() }
            await sut.bootstrap()
            let pending = Task { try await sut.reconnectWithWebAuthentication(expectedOrganizationID: a) }
            for _ in 0..<2_000 {
                if await gate.waiting { break }
                try await Task.sleep(for: .milliseconds(1))
            }
            try require(await gate.waiting, "dummy login did not suspend")
            await sut.reset()
            try require(await sut.state == .signedOutByUser, "reset did not complete during pending login")
            await gate.finish(lateSuccess ? .success((a, [])) : .failure(CancellationError()))
            do { try await pending.value; throw CheckFailure(message: "reset login committed") }
            catch is CancellationError {}
            try require(await sut.state == .signedOutByUser && memory.read().context == nil && memory.read().signedOut,
                        "late login success/rollback resurrected reset context")
            checks += 1
        }

        // Late success/error for both providers must not replace/delete B after
        // a suspended A request. Also test explicit removal and renewed tokens.
        for service in ["claude", "codex"] {
            for status in [200, 401] {
                let oldClaude = SharedClaudeAuthContext(orgId: a, cookies: [cookie("dummy-A")])
                let newClaude = SharedClaudeAuthContext(orgId: b, cookies: [cookie("dummy-B")])
                let memory = Memory(DummyWidget(codex: service == "codex" ? codex(a) : nil,
                                               claude: service == "claude" ? oldClaude : nil))
                let sut = widget(memory)
                let task = Task { await sut.refreshAvailableServices(force: true) }
                let request = try await DummyWire.take()
                memory.edit { value in
                    if service == "claude" { value.claude = newClaude }
                    else { value.codex = codex(b) }
                }
                request.finish(status: status, body: service == "claude" ? claudeBody : codexBody(a))
                let snapshot = await task.value
                try require(memory.read().claude?.orgId == (service == "claude" ? b : nil), "late Claude changed B")
                try require(memory.read().codex?.accountID == (service == "codex" ? b : nil), "late Codex changed B")
                try require(snapshot.claudeUsage == nil && snapshot.codexUsage == nil, "late reading returned for B")
                checks += 1
            }
        }
        for service in ["claude", "codex"] {
            let memory = Memory(DummyWidget(codex: service == "codex" ? codex(a) : nil,
                                           claude: service == "claude" ? .init(orgId: a, cookies: [cookie("dummy-A")]) : nil))
            let sut = widget(memory)
            let task = Task { await sut.refreshAvailableServices(force: true) }
            let request = try await DummyWire.take()
            memory.edit { $0.codex = nil; $0.claude = nil }
            request.finish(body: service == "claude" ? claudeBody : codexBody(a))
            _ = await task.value
            try require(memory.read().codex == nil && memory.read().claude == nil && memory.read().codexUsage == nil && memory.read().claudeUsage == nil, "late response resurrected removal")
            checks += 1
        }
        let renewed = Memory(DummyWidget(codex: codex(a, expired: true)))
        let renewingWidget = widget(renewed)
        let renewing = Task { await renewingWidget.refreshAvailableServices(force: true) }
        let tokenRequest = try await DummyWire.take()
        renewed.edit { $0.codex = codex(b) }
        tokenRequest.finish(body: "{\"access_token\":\"dummy-renewed-A\"}")
        _ = await renewing.value
        try require(renewed.read().codex?.accountID == b && renewed.read().codexUsage == nil, "late renewal overwrote B")
        checks += 1

        // A successful unchanged request is a control: guards must not disable refresh.
        let control = Memory(DummyWidget(claude: .init(orgId: a, cookies: [cookie("dummy-A")])))
        let controlWidget = widget(control)
        let successful = Task { await controlWidget.refreshAvailableServices(force: true) }
        try await DummyWire.take().finish(body: claudeBody)
        let successSnapshot = await successful.value
        try require(successSnapshot.claudeUsage?.quotaScopeID == a, "valid Claude refresh did not commit")
        checks += 1
        let codexControl = Memory(DummyWidget(codex: codex(a)))
        let codexWidget = widget(codexControl)
        let codexSuccess = Task { await codexWidget.refreshAvailableServices(force: true) }
        try await DummyWire.take().finish(body: codexBody(a))
        try require(await codexSuccess.value.codexUsage?.accountID == a, "valid Codex refresh did not commit")
        checks += 1

        let rotated = Memory(DummyWidget(claude: .init(orgId: a, cookies: [cookie("dummy-old")])) )
        let rotatingWidget = widget(rotated)
        let rotating = Task { await rotatingWidget.refreshAvailableServices(force: true) }
        let rotatingRequest = try await DummyWire.take()
        rotated.edit { $0.claude = .init(orgId: a, cookies: [cookie("dummy-new")]) }
        rotatingRequest.finish(body: claudeBody)
        _ = await rotating.value
        try require(rotated.read().claudeUsage == nil, "same-org old credential response committed")
        checks += 1

        let wrongResponse = Memory(DummyWidget(codex: codex(a)))
        let wrongWidget = widget(wrongResponse)
        let wrongFetch = Task { await wrongWidget.refreshAvailableServices(force: true) }
        try await DummyWire.take().finish(body: codexBody(b))
        _ = await wrongFetch.value
        try require(wrongResponse.read().codexUsage == nil, "different response account accepted")
        checks += 1

        var previous = CodexUsage.placeholder.withMonthlyBudget(.init(unit: "credit", used: 42, limit: 100, resetAt: nil))
        previous.accountID = b
        let provenance = Memory(DummyWidget(codex: codex(a), codexUsage: previous))
        let provenanceWidget = widget(provenance)
        let partial = Task { await provenanceWidget.refreshAvailableServices(force: true) }
        try await DummyWire.take().finish(body: "{\"account_id\":\"\(a)\",\"plan_type\":\"plus\"}")
        try await DummyWire.take().finish(body: "{}") // Optional monthly-budget response.
        let partialSnapshot = await partial.value
        try require(partialSnapshot.codexUsage?.accountID == a && partialSnapshot.codexUsage?.monthlyBudget == nil,
                    "partial A response retained B's confirmed budget")
        checks += 1

        let cached = Memory(DummyWidget(claude: .init(orgId: a, cookies: [cookie("dummy-A")]),
                                       claudeUsage: dummyReading(b)))
        let cachedWidget = widget(cached)
        try require(await cachedWidget.currentSnapshot().claudeUsage == nil, "widget exposed wrong-org cached reading")
        checks += 1

        print("PASS: \(checks) dummy coordinator/widget checks; no real stores or network")
        try await runPrimaryRefreshChecks()
        try await runAdditionalReconnectChecks()
    }
}

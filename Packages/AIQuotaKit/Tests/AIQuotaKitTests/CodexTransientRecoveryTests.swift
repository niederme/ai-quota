import Foundation
import Testing
@testable import AIQuotaKit

@Suite("Codex transient restoration", .serialized)
struct CodexTransientRecoveryTests {
    private func jwt(_ workspace: String = "fixture-workspace") -> String {
        let payload = Data("{\"chatgpt_account_id\":\"\(workspace)\",\"sub\":\"fixture-user\"}".utf8)
            .base64EncodedString().replacingOccurrences(of: "=", with: "")
        return "e30.\(payload).fixture"
    }

    private func coordinator(
        clock: LockIsolated<Date> = .init(Date(timeIntervalSince1970: 1000)),
        probe: @escaping CodexAuthCoordinator.SessionProbe = { .found(sessionToken: "fixture-session") },
        refresher: @escaping CodexAuthCoordinator.AccessTokenRefresher,
        writes: LockIsolated<Int> = .init(0),
        clears: LockIsolated<Int> = .init(0)
    ) -> CodexAuthCoordinator {
        CodexAuthCoordinator(accountStorageID: UUID(), probe: probe,
            headlessSessionReviver: { nil }, tokenRefresher: refresher,
            oauthCredentialsLoader: { throw CodexOAuthCredentialsError.notFound },
            expectedAccountID: { "fixture-workspace" }, contextWriter: { _ in writes.withLock { $0 += 1 } },
            sessionClearer: { clears.withLock { $0 += 1 } }, now: { clock.value })
    }

    private func transport(_ handler: @escaping @Sendable (URLRequest) throws -> (Int, Data)) -> URLSession {
        RecoveryURLProtocol.handler.withLock { $0 = handler }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecoveryURLProtocol.self]
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    @Test("refresh distinguishes temporary HTTP failures, genuine rejection and malformed responses")
    func classifiesSessionResponses() async throws {
        for (status, body, reconnect) in [(429, "", false), (500, "", false), (503, "", false),
                                         (403, "challenge", false), (401, "", true),
                                         (200, "{}", true), (200, "", false), (200, "not JSON", false),
                                         (200, "{\"error\":\"temporary\"}", false)] {
            let session = transport { request in
                #expect(request.url?.absoluteString == "https://chatgpt.com/api/auth/session")
                #expect(!request.httpShouldHandleCookies)
                #expect(request.timeoutInterval == 15)
                #expect(request.value(forHTTPHeaderField: "Cookie") == "__Secure-next-auth.session-token=fixture-session")
                return (status, Data(body.utf8))
            }
            do {
                _ = try await CodexAuthCoordinator.refreshSessionToken("fixture-session", session: session)
                Issue.record("Expected an error for \(status)")
            } catch let error as NetworkError {
                #expect(error.needsReconnect == reconnect)
                if status == 429 { if case .rateLimited = error {} else { Issue.record("Lost rate-limit classification") } }
            }
            session.invalidateAndCancel()
        }
        let session = transport { _ in throw URLError(.timedOut) }
        defer { session.invalidateAndCancel() }
        await #expect(throws: URLError.self) { try await CodexAuthCoordinator.refreshSessionToken("fixture-session", session: session) }
    }

    @Test("successful refresh returns the response without adopting a different account")
    func successfulTransport() async throws {
        let token = jwt()
        let session = transport { _ in (200, Data("{\"accessToken\":\"\(token)\",\"expires\":\"2099-01-01T00:00:00Z\"}".utf8)) }
        defer { session.invalidateAndCancel() }
        let result = try await CodexAuthCoordinator.refreshSessionToken("fixture-session", session: session)
        #expect(result.token == token)
        #expect(result.expiresAt != nil)
    }

    @Test("bootstrap temporary failure retries with capped backoff and keeps its identity")
    func retriesAfterBackoff() async throws {
        let clock = LockIsolated(Date(timeIntervalSince1970: 1000)), calls = LockIsolated(0), writes = LockIsolated(0)
        let available = LockIsolated(false), token = jwt()
        let sut = coordinator(clock: clock, refresher: { _ in
            calls.withLock { $0 += 1 }
            guard available.value else { throw NetworkError.httpError(statusCode: 503) }
            return (token, .distantFuture)
        }, writes: writes)
        await sut.bootstrap()
        #expect(await sut.state == .unauthenticated)
        #expect(await sut.hasRetryableRestoration)
        #expect(writes.value == 0)
        for delay in [30.0, 60, 120, 240, 300, 300] {
            let count = calls.value
            for _ in 0..<3 { #expect(!(await sut.retryTransientRestorationIfNeeded())) }
            #expect(calls.value == count)
            clock.withLock { $0 = $0.addingTimeInterval(delay) }
            #expect(!(await sut.retryTransientRestorationIfNeeded()))
            #expect(calls.value == count + 1)
        }
        available.withLock { $0 = true }; clock.withLock { $0 = $0.addingTimeInterval(300) }
        #expect(await sut.retryTransientRestorationIfNeeded())
        #expect(await sut.state == .authenticated)
        #expect(!(await sut.hasRetryableRestoration))
        #expect(try await sut.accessContext().accountID == "fixture-workspace")
        #expect(writes.value == 1)
    }

    @Test("indeterminate revalidation retains a verified connection; real rejection does not")
    func revalidationDistinguishesFailures() async throws {
        let failure = LockIsolated<NetworkError?>(nil), writes = LockIsolated(0), token = jwt()
        let sut = coordinator(refresher: { _ in
            if let error = failure.value { throw error }
            return (token, .distantFuture)
        }, writes: writes)
        await sut.bootstrap()
        failure.withLock { $0 = .httpError(statusCode: 503) }
        #expect(!(await sut.revalidateSessionAfterAuthFailure()))
        #expect(await sut.state == .authenticated)
        #expect(writes.value == 1)
        #expect(await sut.restorationFailure?.needsReconnect == false)
        failure.withLock { $0 = nil }
        #expect(await sut.revalidateSessionAfterAuthFailure())
        #expect(await sut.restorationFailure == nil)
        failure.withLock { $0 = .tokenExpired }
        #expect(!(await sut.revalidateSessionAfterAuthFailure()))
        #expect(await sut.state == .unauthenticated)
        #expect(!(await sut.hasRetryableRestoration))
        #expect(writes.value == 2)
    }

    @Test("network failures at launch are retryable; wrong workspace and expiry are not")
    func retryEligibilityAndIdentity() async {
        for wrongAccount in [false, true] {
            let token = jwt("another-workspace"), writes = LockIsolated(0)
            let sut = coordinator(refresher: { _ in
                if wrongAccount { return (token, .distantFuture) }
                throw NetworkError.tokenExpired
            }, writes: writes)
            await sut.bootstrap()
            #expect(await sut.state == .unauthenticated)
            #expect(!(await sut.hasRetryableRestoration))
            #expect(!(await sut.retryTransientRestorationIfNeeded()))
            #expect(writes.value == 0)
        }
        let sut = coordinator(refresher: { _ in throw URLError(.notConnectedToInternet) })
        await sut.bootstrap()
        #expect(await sut.hasRetryableRestoration)
    }

    @Test("cancelled bootstrap exits busy state without saving a late response")
    func cancelledBootstrap() async {
        let gate = RecoveryGate(), writes = LockIsolated(0), token = jwt()
        let sut = coordinator(refresher: { _ in await gate.wait(); return (token, .distantFuture) }, writes: writes)
        let task = Task { await sut.bootstrap() }
        while !(await gate.waiting) { await Task.yield() }
        task.cancel(); await gate.resume(); await task.value
        #expect(await sut.state == .unauthenticated)
        #expect(await sut.hasRetryableRestoration)
        #expect(writes.value == 0)
    }

    @Test("transport cancellation without Task cancellation never invalidates a verified session")
    func transportCancellationIsIndeterminate() async {
        let cancel = LockIsolated(false), token = jwt(), writes = LockIsolated(0)
        let sut = coordinator(refresher: { _ in
            if cancel.value { throw URLError(.cancelled) }
            return (token, .distantFuture)
        }, writes: writes)
        await sut.bootstrap(); cancel.withLock { $0 = true }
        #expect(!(await sut.revalidateSessionAfterAuthFailure()))
        #expect(!Task.isCancelled)
        #expect(await sut.state == .authenticated)
        #expect(await sut.restorationFailure?.needsReconnect == false)
        #expect(writes.value == 1)
    }

    @Test("retry coalesces, survives cancellation, and never overrides explicit sign-out")
    func cancellationAndSignOutDuringRetry() async throws {
        for signOut in [false, true] {
            let gate = RecoveryGate(), calls = LockIsolated(0), writes = LockIsolated(0), clears = LockIsolated(0)
            let clock = LockIsolated(Date(timeIntervalSince1970: 1000)), token = jwt()
            let sut = coordinator(clock: clock, refresher: { _ in
                let count = calls.withLock { $0 += 1; return $0 }
                if count == 1 { throw NetworkError.rateLimited }
                await gate.wait(); return (token, .distantFuture)
            }, writes: writes, clears: clears)
            await sut.bootstrap(); clock.withLock { $0 = $0.addingTimeInterval(30) }
            let task = Task { await sut.retryTransientRestorationIfNeeded() }
            while !(await gate.waiting) { await Task.yield() }
            #expect(!(await sut.retryTransientRestorationIfNeeded()))
            #expect(calls.value == 2)
            if signOut { try await sut.signOut() } else { task.cancel() }
            await gate.resume(); _ = await task.value
            #expect(writes.value == 0)
            #expect(await sut.state == (signOut ? .signedOutByUser : .unauthenticated))
            #expect(await sut.hasRetryableRestoration == !signOut)
            #expect(!(await sut.retryTransientRestorationIfNeeded()))
            #expect(calls.value == 2) // Includes a canceled attempt's reserved backoff.
            if signOut {
                #expect(clears.value == 1)
                #expect(!(await sut.retryTransientRestorationIfNeeded()))
                #expect(!(await sut.restoreWithoutPromptIfPossible()))
            }
        }
    }
}

private actor RecoveryGate {
    var continuation: CheckedContinuation<Void, Never>?
    var waiting: Bool { continuation != nil }
    func wait() async { await withCheckedContinuation { continuation = $0 } }
    func resume() { continuation?.resume(); continuation = nil }
}

private final class RecoveryURLProtocol: URLProtocol, @unchecked Sendable {
    static let handler = LockIsolated<(@Sendable (URLRequest) throws -> (Int, Data))?>(nil)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler.value!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

import Foundation
import Testing
@testable import AIQuotaKit

/// ChatGPT re-issues its session cookie when the session is read. The app must
/// keep the re-issued cookie, or the saved session fails after a relaunch.
@Suite("Codex session cookie renewal", .serialized)
struct CodexSessionRenewalTests {
    private let name = "__Secure-next-auth.session-token"

    private func jwt(_ workspace: String = "fixture-workspace") -> String {
        let data = Data("{\"chatgpt_account_id\":\"\(workspace)\",\"sub\":\"fixture-user\"}".utf8)
        return "e30.\(data.base64EncodedString().replacingOccurrences(of: "=", with: "")).fixture"
    }

    private func response(_ headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://chatgpt.com/api/auth/session")!, statusCode: 200,
                        httpVersion: nil, headerFields: headers)!
    }

    private func cookie(_ name: String, _ value: String, domain: String = ".chatgpt.com") -> HTTPCookie {
        HTTPCookie(properties: [.name: name, .value: value, .domain: domain, .path: "/", .secure: "TRUE"])!
    }

    @Test("reads a re-issued session cookie, including lowercase headers")
    func readsRenewedCookie() {
        for header in ["Set-Cookie", "set-cookie"] {
            let http = response([header: "\(name)=fixture-renewed; Path=/; Secure; HttpOnly; SameSite=Lax"])
            #expect(CodexAuthCoordinator.renewedSessionToken(from: http) == "fixture-renewed")
        }
        #expect(CodexAuthCoordinator.renewedSessionToken(from: response([:])) == nil)
        let other = response(["Set-Cookie": "__cf_bm=fixture; Path=/; Secure"])
        #expect(CodexAuthCoordinator.renewedSessionToken(from: other) == nil)
    }

    @Test("ignores a deleted session cookie")
    func ignoresDeletion() {
        let http = response(["Set-Cookie": "\(name)=fixture; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT"])
        #expect(CodexAuthCoordinator.renewedSessionToken(from: http) == nil)
    }

    @Test("a renewed cookie replaces every old session chunk in a staged jar")
    func mergeReplacesChunks() {
        let jar = [cookie("\(name).0", "old-a"), cookie("\(name).1", "old-b"), cookie("oai-did", "device"),
                   cookie(name, "other-site", domain: ".example.com")]
        let merged = CodexAuthCoordinator.mergingRenewedSessionCookies([cookie(name, "fixture-renewed")], into: jar)
        #expect(CodexAuthCoordinator.sessionToken(from: merged) == "fixture-renewed")
        #expect(merged.contains { $0.name == "oai-did" })
        #expect(merged.contains { $0.domain == ".example.com" })
        #expect(!merged.contains { $0.name.hasPrefix("\(name).") })
        #expect(CodexAuthCoordinator.mergingRenewedSessionCookies([], into: jar) == jar)
    }

    @Test("restoring a session saves the re-issued cookie for the next launch")
    func restoreAdoptsRenewedCookie() async {
        let token = jwt(), saved = LockIsolated<[String]>([])
        let sut = CodexAuthCoordinator(accountStorageID: UUID(), probe: { .notFound }, headlessSessionReviver: { nil },
            sessionRefresher: { session in
                #expect(session == "fixture-old")
                return CodexSessionRefresh(token: token, expiresAt: .distantFuture, renewedSessionToken: "fixture-renewed")
            }, sessionTokenLoader: { "fixture-old" },
            oauthCredentialsLoader: { throw CodexOAuthCredentialsError.notFound },
            expectedAccountID: { "fixture-workspace" },
            contextWriter: { context in saved.withLock { $0.append(context.sessionToken) } },
            interactiveSessionProvider: { _ in Issue.record("Restoration opened sign-in"); throw CancellationError() },
            sessionClearer: {})
        await sut.bootstrap()
        #expect(await sut.state == .authenticated)
        #expect(saved.value == ["fixture-renewed"])
    }

    @Test("a refresh without a re-issued cookie keeps the one sent")
    func keepsSentCookieWithoutRenewal() async {
        let token = jwt(), saved = LockIsolated<[String]>([])
        let sut = CodexAuthCoordinator(accountStorageID: UUID(), probe: { .notFound }, headlessSessionReviver: { nil },
            sessionRefresher: { _ in CodexSessionRefresh(token: token, expiresAt: .distantFuture) },
            sessionTokenLoader: { "fixture-old" },
            oauthCredentialsLoader: { throw CodexOAuthCredentialsError.notFound },
            expectedAccountID: { "fixture-workspace" },
            contextWriter: { context in saved.withLock { $0.append(context.sessionToken) } },
            sessionClearer: {})
        await sut.bootstrap()
        #expect(saved.value == ["fixture-old"])
    }

    @Test("a long-running app renews the saved cookie twice a day and keeps working if that fails")
    func periodicRenewal() async throws {
        try #require(StorageTestIsolation.isRunningTests)
        let id = UUID(), key = "sessionToken.\(id.uuidString.lowercased())"
        KeychainStore.save("fixture-old", forKey: key)
        defer { KeychainStore.delete(forKey: key) }
        try #require(KeychainStore.load(forKey: key) == "fixture-old")
        let token = jwt(), clock = LockIsolated(Date(timeIntervalSince1970: 1000))
        let sent = LockIsolated<[String]>([]), fail = LockIsolated(false)
        let sut = CodexAuthCoordinator(accountStorageID: id, probe: { .notFound }, headlessSessionReviver: { nil },
            sessionRefresher: { session in
                let count = sent.withLock { $0.append(session); return $0.count }
                if fail.value { throw NetworkError.httpError(statusCode: 503) }
                return CodexSessionRefresh(token: token, expiresAt: .distantFuture, renewedSessionToken: "fixture-renewed-\(count)")
            },
            oauthCredentialsLoader: { throw CodexOAuthCredentialsError.notFound },
            expectedAccountID: { "fixture-workspace" }, contextWriter: { _ in }, sessionClearer: {},
            now: { clock.value })
        await sut.bootstrap()
        #expect(sent.value == ["fixture-old"])
        #expect(KeychainStore.load(forKey: key) == "fixture-renewed-1")

        _ = try await sut.accessContext()
        #expect(sent.value.count == 1) // Not due yet.

        clock.withLock { $0 = $0.addingTimeInterval(CodexAuthCoordinator.sessionRenewalInterval + 1) }
        _ = try await sut.accessContext()
        #expect(sent.value == ["fixture-old", "fixture-renewed-1"])
        #expect(KeychainStore.load(forKey: key) == "fixture-renewed-2")

        fail.withLock { $0 = true }
        clock.withLock { $0 = $0.addingTimeInterval(CodexAuthCoordinator.sessionRenewalInterval + 1) }
        #expect(try await sut.accessContext().accessToken == token)
        #expect(await sut.state == .authenticated)
        #expect(sent.value.count == 3)
        _ = try await sut.accessContext()
        #expect(sent.value.count == 3) // One attempt per interval.
    }

    @Test("sign-in verification commits the cookie the check re-issued")
    func stagedVerificationAdoptsRenewal() async throws {
        let access = jwt("personal")
        let candidate = CodexWebSessionResult(sessionToken: "fixture-old", accessToken: access, expiresAt: nil,
            cookiesToCommit: [cookie(name, "fixture-old"), cookie("oai-did", "device")])
        RenewalURLProtocol.handler.withLock { $0 = { _ in
            (200, ["Set-Cookie": "\(self.name)=fixture-renewed; Path=/; Secure; HttpOnly"],
             try JSONSerialization.data(withJSONObject: ["accessToken": access]))
        } }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RenewalURLProtocol.self]
        let session = CodexAuthCoordinator.stagedSessionTransport(configuration: config)
        defer { session.invalidateAndCancel() }
        let verified = try await CodexAuthCoordinator.verifyStagedSession(candidate, session: session)
        #expect(verified.sessionToken == "fixture-renewed")
        let committed = try #require(verified.cookiesToCommit)
        #expect(CodexAuthCoordinator.sessionToken(from: committed) == "fixture-renewed")
        #expect(committed.contains { $0.name == "oai-did" })
    }
}

private final class RenewalURLProtocol: URLProtocol, @unchecked Sendable {
    static let handler = LockIsolated<(@Sendable (URLRequest) throws -> (Int, [String: String], Data))?>(nil)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler.value else { throw NetworkError.unknownEndpoint }
            let (status, headers, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

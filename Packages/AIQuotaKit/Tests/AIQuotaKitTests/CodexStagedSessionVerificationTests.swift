import Foundation
import Testing
@testable import AIQuotaKit

@Suite("Staged Codex cookie verification", .serialized)
struct CodexStagedSessionVerificationTests {
    private func jwt(_ workspace: String, user: String? = "user-a", marker: String = "initial") throws -> String {
        var payload: [String: Any] = ["chatgpt_account_id": workspace, "marker": marker]
        payload["sub"] = user
        let encoded = try JSONSerialization.data(withJSONObject: payload).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "e30.\(encoded).fixture"
    }

    private func cookie(_ name: String = "__Secure-next-auth.session-token", value: String = "fixture-session",
                        domain: String = ".chatgpt.com", path: String = "/", expired: Bool = false) -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: path, .secure: "TRUE"]
        if expired { properties[.expires] = Date(timeIntervalSince1970: 1) }
        return HTTPCookie(properties: properties)!
    }

    private func transport(_ handler: @escaping @Sendable (URLRequest) throws -> (Int, Data)) -> URLSession {
        StagedVerificationURLProtocol.handler.withLock { $0 = handler }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StagedVerificationURLProtocol.self]
        return CodexAuthCoordinator.stagedSessionTransport(configuration: config)
    }

    @Test("a renewed access token completes using the exact independently verified jar")
    func verifiesCapturedJar() async throws {
        let initial = try jwt("personal"), renewed = try jwt("personal", marker: "renewed")
        let frozen = [cookie(value: "renewed-opaque-cookie")]
        let candidate = CodexWebSessionResult(sessionToken: "renewed-opaque-cookie", accessToken: initial,
            expiresAt: nil, cookiesToCommit: frozen)
        let session = transport { request in
            #expect(request.url?.absoluteString == "https://chatgpt.com/api/auth/session")
            #expect(request.value(forHTTPHeaderField: "Cookie") == "__Secure-next-auth.session-token=renewed-opaque-cookie")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(!request.httpShouldHandleCookies)
            #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
            return (200, try JSONSerialization.data(withJSONObject: ["accessToken": renewed, "expires": "2026-11-01T00:00:00Z"]))
        }
        defer { session.invalidateAndCancel() }
        let verified = try await CodexAuthCoordinator.verifyStagedSession(candidate, session: session)
        #expect(verified.accessToken == renewed)
        #expect(verified.sessionToken == candidate.sessionToken)
        #expect(verified.cookiesToCommit == frozen)
        #expect(verified.expiresAt != nil)
    }

    @Test("unrecognized cookie names do not masquerade as an unstable session")
    func missingLegacyCookieNameCanBeIndependentlyVerified() async throws {
        let access = try jwt("personal")
        let candidate = CodexWebSessionResult(sessionToken: "", accessToken: access, expiresAt: nil,
            cookiesToCommit: [cookie("new-provider-cookie", value: "fixture")])
        #expect(CodexLoginCompletionGate().evaluate(candidate, expectedAccountID: "personal") == .complete)
        let session = transport { request in
            #expect(request.value(forHTTPHeaderField: "Cookie") == "new-provider-cookie=fixture")
            return (200, try JSONSerialization.data(withJSONObject: ["accessToken": access]))
        }
        defer { session.invalidateAndCancel() }
        let verified = try await CodexAuthCoordinator.verifyStagedSession(candidate, session: session)
        #expect(verified.accessToken == access)
        #expect(verified.sessionToken.isEmpty)
        #expect(verified.cookiesToCommit == candidate.cookiesToCommit)
    }

    @Test("another workspace or user can never validate the candidate jar")
    func rejectsChangedIdentity() async throws {
        let candidate = CodexWebSessionResult(sessionToken: "fixture-session", accessToken: try jwt("personal"),
            expiresAt: nil, cookiesToCommit: [cookie()])
        for token in [try jwt("work"), try jwt("personal", user: "user-b"), try jwt("personal", user: nil)] {
            let session = transport { _ in (200, try JSONSerialization.data(withJSONObject: ["accessToken": token])) }
            await #expect(throws: NetworkError.self) { try await CodexAuthCoordinator.verifyStagedSession(candidate, session: session) }
            session.invalidateAndCancel()
        }
    }

    @Test("snapshot mismatch and missing cookies fail before an HTTP call")
    func rejectsInvalidSnapshot() async throws {
        let calls = LockIsolated(0)
        let session = transport { _ in calls.withLock { $0 += 1 }; return (200, Data()) }
        defer { session.invalidateAndCancel() }
        for candidate in [
            CodexWebSessionResult(sessionToken: "different", accessToken: try jwt("personal"), expiresAt: nil, cookiesToCommit: [cookie()]),
            CodexWebSessionResult(sessionToken: "", accessToken: try jwt("personal"), expiresAt: nil, cookiesToCommit: [])
        ] {
            await #expect(throws: NetworkError.self) { try await CodexAuthCoordinator.verifyStagedSession(candidate, session: session) }
        }
        #expect(calls.value == 0)
    }

    @Test("verification sends only cookies applicable to the exact HTTPS endpoint")
    func cookieRoutingPreservesChunksAndBoundaries() throws {
        let request = try CodexAuthCoordinator.stagedSessionRequest(cookies: [
            cookie("__Secure-next-auth.session-token.0", value: "chunk-a"),
            cookie("__Secure-next-auth.session-token.1", value: "chunk-b", path: "/api/auth"),
            cookie("wrong-host", domain: ".openai.com"),
            cookie("subdomain-only", domain: "auth.chatgpt.com"),
            cookie("wrong-path", path: "/api/auth/session-other"),
            cookie("expired", expired: true)
        ])
        let header = try #require(request.value(forHTTPHeaderField: "Cookie"))
        #expect(header.contains("__Secure-next-auth.session-token.0=chunk-a"))
        #expect(header.contains("__Secure-next-auth.session-token.1=chunk-b"))
        for excluded in ["wrong-host", "subdomain-only", "wrong-path", "expired"] { #expect(!header.contains(excluded)) }
    }

    @Test("an HTTP rejection cannot become an authenticated result")
    func verificationFailureIsExplicit() async throws {
        let candidate = CodexWebSessionResult(sessionToken: "fixture-session", accessToken: try jwt("personal"),
            expiresAt: nil, cookiesToCommit: [cookie()])
        let session = transport { _ in (403, Data()) }
        defer { session.invalidateAndCancel() }
        await #expect(throws: NetworkError.self) { try await CodexAuthCoordinator.verifyStagedSession(candidate, session: session) }
    }

    @Test("redirects are rejected before the captured jar can reach another endpoint")
    func redirectsCannotForwardCookies() async throws {
        let candidate = CodexWebSessionResult(sessionToken: "fixture-session", accessToken: try jwt("personal"),
            expiresAt: nil, cookiesToCommit: [cookie()])
        let calls = LockIsolated(0)
        let session = transport { request in
            calls.withLock { $0 += 1 }
            #expect(request.url?.absoluteString == "https://chatgpt.com/api/auth/session")
            return (302, Data())
        }
        defer { session.invalidateAndCancel() }
        await #expect(throws: NetworkError.self) { try await CodexAuthCoordinator.verifyStagedSession(candidate, session: session) }
        #expect(calls.value == 1)
    }
}

private final class StagedVerificationURLProtocol: URLProtocol, @unchecked Sendable {
    static let handler = LockIsolated<(@Sendable (URLRequest) throws -> (Int, Data))?>(nil)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler.value else { throw NetworkError.unknownEndpoint }
            let (status, data) = try handler(request)
            if status == 302 {
                let destination = URL(string: "https://redirect.invalid/session")!
                let redirect = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil,
                    headerFields: ["Location": destination.absoluteString])!
                client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: destination), redirectResponse: redirect)
                client?.urlProtocol(self, didReceive: redirect, cacheStoragePolicy: .notAllowed)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

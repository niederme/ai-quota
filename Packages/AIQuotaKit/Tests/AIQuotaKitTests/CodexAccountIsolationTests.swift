import Foundation
import Testing
@testable import AIQuotaKit

/// All credentials and responses are synthetic; no provider or live storage reads.
extension AccountRegistryTests {
    @Suite("Codex account isolation", .serialized)
    struct CodexAccountIsolationTests {
        init() {
            AccountRegistry.resetForTesting()
            UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
            UserDefaults.standard.removeObject(forKey: "codex.signedOutByUser")
        }

        private func credentials(_ identity: String, token: String? = nil) -> CodexOAuthCredentials {
            CodexOAuthCredentials(accessToken: token ?? "fixture-\(identity)", refreshToken: nil,
                                  idToken: nil, accountID: identity, lastRefresh: nil,
                                  expiresAt: .now.addingTimeInterval(3600))
        }

        private func coordinator(_ value: LockIsolated<CodexOAuthCredentials>, id: UUID? = nil) async -> CodexAuthCoordinator {
            let sut = CodexAuthCoordinator(accountStorageID: id, probe: { .notFound },
                                           headlessSessionReviver: { nil },
                                           tokenRefresher: { _ in throw NetworkError.refreshFailed },
                                           oauthCredentialsLoader: { value.value })
            await sut.bootstrap()
            return sut
        }

        private func session(_ handler: @escaping @Sendable (URLRequest) throws -> Data) -> URLSession {
            IsolationURLProtocol.handler.withLock { $0 = handler }
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [IsolationURLProtocol.self]
            config.urlCache = nil
            config.httpCookieStorage = nil
            return URLSession(configuration: config)
        }

        private func graph(_ tokens: Int?) -> Data {
            let buckets = tokens.map { "[{\"start_date\":\"2026-10-23\",\"tokens\":\($0)}]" } ?? "[]"
            return Data("{\"stats\":{\"daily_usage_buckets\":\(buckets)}}".utf8)
        }

        @Test func cliSwitchCannotRetargetPrimaryOrOtherAccount() async throws {
            defer { AccountRegistry.resetForTesting() }
            let personal = AccountRegistry.upsert(provider: .codex, displayLabel: "Personal", workspaceID: "a",
                                                  authSource: .oauth, connectionKind: .legacyPrimary)
            let work = AccountRegistry.upsert(provider: .codex, displayLabel: "Work", workspaceID: "b", authSource: .webSession)
            let cli = LockIsolated(credentials("a"))
            let primaryCoordinator = await coordinator(cli)
            let workCoordinator = await coordinator(LockIsolated(credentials("b")), id: UUID(uuidString: work.id))
            let calls = LockIsolated(0)
            let a = graph(600), b = graph(0)
            let transport = session { request in
                calls.withLock { $0 += 1 }
                let identity = request.value(forHTTPHeaderField: "ChatGPT-Account-Id") ?? ""
                if request.url?.path == "/backend-api/wham/usage" {
                    return Data("{\"account_id\":\"\(identity)\",\"plan_type\":\"business\",\"spend_control\":{\"individual_limit\":{\"unit\":\"credit\",\"used\":8.22,\"limit\":7000}}}".utf8)
                }
                #expect(request.url?.path == "/backend-api/wham/profiles/me")
                #expect(request.url?.query == nil)
                #expect(!request.httpShouldHandleCookies)
                #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
                #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-\(identity)")
                return identity == "a" ? a : b
            }
            let primary = OpenAIClient(coordinator: primaryCoordinator, session: transport)
            let isolated = OpenAIClient(coordinator: workCoordinator, accountStorageID: UUID(uuidString: work.id), session: transport)
            let primaryHistory = try #require(try await primary.fetchTokenHistory())
            let workHistory = try #require(try await isolated.fetchTokenHistory())
            #expect(primaryHistory.tokensByDate["2026-10-23"] == 600)
            #expect(workHistory.tokensByDate["2026-10-23"] == 0)
            #expect(primaryHistory.isAttributed(toWorkspaceID: "a"))
            #expect(!primaryHistory.isAttributed(toWorkspaceID: "b"))
            #expect(workHistory.isAttributed(toWorkspaceID: "b"))
            #expect(!workHistory.isAttributed(toWorkspaceID: "a"))
            cli.withLock { $0 = credentials("b") }
            // The coordinator ignores CLI B and retains its still-valid A source.
            #expect(try await primary.fetchUsage().accountID == "a")
            #expect(try await primary.fetchTokenHistory()?.tokensByDate["2026-10-23"] == 600)
            #expect(calls.value == 4)
            #expect(AccountRegistry.account(id: personal.id)?.workspaceID == "a")
            #expect(try await isolated.fetchTokenHistory()?.tokensByDate["2026-10-23"] == 0)
            cli.withLock { $0 = credentials("a") }
            #expect(try await primary.fetchTokenHistory()?.tokensByDate["2026-10-23"] == 600)
            #expect(await primaryCoordinator.state == .authenticated) // never signs out to repair data
        }

        @Test func twoAccountsReceiveDistinctMonthlyBudgetsIncludingExplicitZero() async throws {
            defer { AccountRegistry.resetForTesting() }
            AccountRegistry.upsert(provider: .codex, displayLabel: "Personal", workspaceID: "a",
                                   authSource: .oauth, connectionKind: .legacyPrimary)
            let work = AccountRegistry.upsert(provider: .codex, displayLabel: "Work", workspaceID: "b", authSource: .webSession)
            let a = await coordinator(LockIsolated(credentials("a")))
            let id = try #require(UUID(uuidString: work.id))
            let b = await coordinator(LockIsolated(credentials("b")), id: id)
            let transport = session { request in
                let identity = request.value(forHTTPHeaderField: "ChatGPT-Account-Id") ?? ""
                let used = identity == "a" ? "8.22" : "0"
                return Data("{\"account_id\":\"\(identity)\",\"plan_type\":\"business\",\"spend_control\":{\"individual_limit\":{\"unit\":\"credit\",\"used\":\(used),\"limit\":7000,\"reset_at\":1792886400}}}".utf8)
            }
            let personal = try await OpenAIClient(coordinator: a, session: transport).fetchUsage()
            let workReading = try await OpenAIClient(coordinator: b, accountStorageID: id, session: transport).fetchUsage()
            #expect(personal.accountID == "a")
            #expect(personal.displayableMonthlyBudget?.used == 8.22)
            #expect(workReading.accountID == "b")
            #expect(workReading.displayableMonthlyBudget?.used == 0)
            #expect(workReading.displayableMonthlyBudget?.limit == 7000)
        }

        @Test func lateResponseFromChangedCredentialsIsRejected() async throws {
            defer { AccountRegistry.resetForTesting() }
            AccountRegistry.upsert(provider: .codex, displayLabel: "Personal", workspaceID: "a",
                                   authSource: .oauth, connectionKind: .legacyPrimary)
            let cli = LockIsolated(credentials("a"))
            let auth = await coordinator(cli)
            let changed = credentials("a", token: "rotated-fixture-a"), response = graph(600)
            let client = OpenAIClient(coordinator: auth, session: session { _ in
                cli.withLock { $0 = changed }
                return response
            })
            await #expect(throws: NetworkError.self) { try await client.fetchTokenHistory() }
        }

        @Test func relaunchUsesPersistedBindingAndRejectsWrongResponseAccount() async throws {
            defer { AccountRegistry.resetForTesting() }
            let account = AccountRegistry.upsert(provider: .codex, displayLabel: "Personal", workspaceID: "a",
                                                 authSource: .oauth, connectionKind: .legacyPrimary)
            let cli = LockIsolated(credentials("b"))
            let auth = await coordinator(cli)
            let calls = LockIsolated(0)
            let client = OpenAIClient(coordinator: auth, session: session { _ in
                calls.withLock { $0 += 1 }
                return Data("{\"account_id\":\"b\",\"plan_type\":\"business\"}".utf8)
            })
            await #expect(throws: NetworkError.self) { try await client.fetchUsage() }
            #expect(calls.value == 0)
            cli.withLock { $0 = credentials("a") }
            #expect(await auth.restoreWithoutPromptIfPossible())
            await #expect(throws: NetworkError.self) { try await client.fetchUsage() }
            #expect(calls.value == 1)
            #expect(AccountRegistry.account(id: account.id)?.workspaceID == "a")
        }

        @Test func emptyAndZeroHistoryDoNotReusePositiveSnapshot() async throws {
            defer { AccountRegistry.resetForTesting() }
            AccountRegistry.upsert(provider: .codex, displayLabel: "Personal", workspaceID: "a",
                                   authSource: .oauth, connectionKind: .legacyPrimary)
            let auth = await coordinator(LockIsolated(credentials("a")))
            let payload = LockIsolated(graph(600))
            let client = OpenAIClient(coordinator: auth, session: session { _ in payload.value })
            #expect(try await client.fetchTokenHistory()?.tokensByDate["2026-10-23"] == 600)
            payload.withLock { $0 = graph(0) }
            #expect(try await client.fetchTokenHistory()?.tokensByDate["2026-10-23"] == 0)
            payload.withLock { $0 = graph(nil) }
            #expect(try await client.fetchTokenHistory()?.tokensByDate.isEmpty == true)
            payload.withLock { $0 = Data("{\"page\":{}}".utf8) }
            #expect(try await client.fetchTokenHistory() == nil)
        }

        @Test func legacyPageResponseCannotBePromotedOrUsedAsFallback() async throws {
            defer { AccountRegistry.resetForTesting() }
            AccountRegistry.upsert(provider: .codex, displayLabel: "Personal", workspaceID: "a",
                                   authSource: .oauth, connectionKind: .legacyPrimary)
            let auth = await coordinator(LockIsolated(credentials("a")))
            let calls = LockIsolated(0)
            let client = OpenAIClient(coordinator: auth, session: session { request in
                calls.withLock { $0 += 1 }
                #expect(request.url?.path == "/backend-api/wham/profiles/me")
                return Data(#"{"page":{"activity_graph":{"daily_usage_buckets":[{"start_date":"2026-10-23","tokens":600}]}}}"#.utf8)
            })
            #expect(try await client.fetchTokenHistory() == nil)
            #expect(calls.value == 1)
            #expect(await auth.state == .authenticated)
        }

        @Test func removedScopedAccountRejectsPendingResponseWithoutRecreatingIt() async throws {
            defer { AccountRegistry.resetForTesting() }
            let account = AccountRegistry.upsert(provider: .codex, displayLabel: "Work", workspaceID: "b", authSource: .webSession)
            let id = try #require(UUID(uuidString: account.id))
            let auth = await coordinator(LockIsolated(credentials("b")), id: id)
            let response = graph(600)
            let client = OpenAIClient(coordinator: auth, accountStorageID: id, session: session { _ in
                AccountRegistry.remove(id: account.id)
                return response
            })
            await #expect(throws: NetworkError.self) { try await client.fetchTokenHistory() }
            #expect(AccountRegistry.account(id: account.id) == nil)
            #expect(AccountRegistry.accounts().isEmpty)
        }

        @Test func partialResponseDoesNotRetainUnverifiedOrOtherAccountCache() async throws {
            defer { AccountRegistry.resetForTesting(); SharedDefaults.clearUsage() }
            AccountRegistry.upsert(provider: .codex, displayLabel: "Personal", workspaceID: "a",
                                   authSource: .oauth, connectionKind: .legacyPrimary)
            let auth = await coordinator(LockIsolated(credentials("a")))
            let client = OpenAIClient(coordinator: auth, session: session { request in
                if request.url?.path == "/backend-api/wham/usage" {
                    return Data("{\"account_id\":\"a\",\"plan_type\":\"business\"}".utf8)
                }
                return Data("{}".utf8)
            })
            for identity in [nil, "b", "a"] as [String?] {
                var cached = CodexUsage.placeholder.withMonthlyBudget(.init(unit: "credit", used: 8.22, limit: 7000, resetAt: nil))
                cached.accountID = identity
                // Use a matching plan to exercise the partial-response retention path.
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let raw = try decoder.decode(WhamUsageResponse.self, from: Data("{\"plan_type\":\"business\"}".utf8))
                var previous = CodexUsage(from: raw, fetchedAt: .distantPast).withMonthlyBudget(cached.monthlyBudget)
                previous.accountID = identity
                SharedDefaults.saveUsage(previous)
                let result = try await client.fetchUsage()
                #expect(result.accountID == "a")
                #expect((result.monthlyBudget != nil) == (identity == "a"))
                // Rejected old caches remain intact; there is no destructive repair.
                #expect(SharedDefaults.loadCachedUsage()?.monthlyBudget?.used == 8.22)
            }
        }

        @Test func identityChangeDuringOptionalMonthlyBudgetCannotEscapeOuterFetch() async throws {
            defer { AccountRegistry.resetForTesting() }
            AccountRegistry.upsert(provider: .codex, displayLabel: "Personal", workspaceID: "a",
                                   authSource: .oauth, connectionKind: .legacyPrimary)
            let cli = LockIsolated(credentials("a"))
            let auth = await coordinator(cli)
            let changed = credentials("a", token: "rotated-fixture-a")
            let client = OpenAIClient(coordinator: auth, session: session { request in
                if request.url?.path == "/backend-api/wham/usage" {
                    return Data("{\"account_id\":\"a\",\"plan_type\":\"business\"}".utf8)
                }
                cli.withLock { $0 = changed }
                return Data("{}".utf8)
            })
            await #expect(throws: NetworkError.self) { try await client.fetchUsage() }
        }

        @Test func unknownOrDuplicateIdentityIsNeverBound() {
            let account = ConnectedAccount(provider: .codex, displayLabel: "Personal", authSource: .oauth, connectionKind: .legacyPrimary)
            let other = ConnectedAccount(provider: .codex, displayLabel: "Work", workspaceID: "b", authSource: .webSession)
            for identity in [nil, "", "b"] as [String?] {
                #expect(throws: NetworkError.self) {
                    try OpenAIClient.validateIdentity(.init(accessToken: "fixture", accountID: identity, source: .codexOAuth),
                                                      account: account, accounts: [account, other])
                }
            }
        }

        @Test func legacyCacheWithoutProvenanceCannotAuthorizeWrongReconnect() async throws {
            defer { AccountRegistry.resetForTesting() }
            let account = AccountRegistry.upsert(provider: .codex, displayLabel: "Personal", workspaceID: "a",
                                                 authSource: .oauth, connectionKind: .legacyPrimary)
            SharedDefaults.saveUsage(.placeholder, forAccountID: account.id)
            let commits = LockIsolated(0)
            let payload = try JSONSerialization.data(withJSONObject: ["https://api.openai.com/auth": ["chatgpt_account_id": "b"]])
            let encoded = payload.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            let auth = CodexAuthCoordinator(probe: { .notFound }, headlessSessionReviver: { nil },
                oauthCredentialsLoader: { credentials("a") }, contextWriter: { _ in },
                interactiveSessionProvider: { _ in .init(sessionToken: "", accessToken: "fixture.\(encoded).fixture", expiresAt: nil) },
                sessionCommitter: { _, _ in commits.withLock { $0 += 1 } })
            await auth.bootstrap()
            await #expect(throws: NetworkError.self) { try await auth.reconnect() }
            #expect(commits.value == 0)
            #expect(AccountRegistry.account(id: account.id)?.workspaceID == "a")
            let cached = SharedDefaults.loadCachedUsage(forAccountID: account.id)
            #expect(cached != nil && cached?.accountID == nil)
        }

        @Test func identityDiagnosticsDistinguishMissingMismatchAndDuplicateWithoutIdentifiers() {
            let bound = ConnectedAccount(provider: .codex, displayLabel: "Personal", workspaceID: "a", authSource: .oauth)
            let duplicate = ConnectedAccount(provider: .codex, displayLabel: "Other", workspaceID: "a", authSource: .webSession)
            let noClaim = CodexAccessContext(accessToken: "fixture", accountID: nil, source: .webSession)
            let wrong = CodexAccessContext(accessToken: "fixture", accountID: "b", source: .webSession)
            let correct = CodexAccessContext(accessToken: "fixture", accountID: "a", source: .webSession)
            #expect(OpenAIClient.identityIssue(noClaim, account: bound, accounts: [bound]) == "missingWorkspaceClaim")
            #expect(OpenAIClient.identityIssue(wrong, account: bound, accounts: [bound]) == "workspaceMismatch")
            #expect(OpenAIClient.identityIssue(correct, account: bound, accounts: [bound, duplicate]) == "duplicateBinding")
            #expect(OpenAIClient.identityIssue(correct, account: bound, accounts: [bound]) == nil)
        }

        @Test func verifiedQuotaIdentitySurvivesPersistenceAndBudgetCopies() throws {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let raw = try decoder.decode(WhamUsageResponse.self, from: Data("{\"account_id\":\"a\",\"plan_type\":\"business\"}".utf8))
            let reading = CodexUsage(from: raw)
            let copy = reading.withMonthlyBudget(.init(unit: "credit", used: 0, limit: 7000, resetAt: nil))
                .withBonusCreditsSpentThisMonth(0)
            #expect(copy.accountID == "a")
            let encoded = try JSONEncoder().encode(copy)
            #expect(try JSONDecoder().decode(CodexUsage.self, from: encoded).accountID == "a")
            var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            legacy.removeValue(forKey: "accountID")
            #expect(try JSONDecoder().decode(CodexUsage.self, from: JSONSerialization.data(withJSONObject: legacy)).accountID == nil)
        }
    }

}

private final class IsolationURLProtocol: URLProtocol, @unchecked Sendable {
    static let handler = LockIsolated<(@Sendable (URLRequest) throws -> Data)?>(nil)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler.value else { throw NetworkError.unknownEndpoint }
            let data = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

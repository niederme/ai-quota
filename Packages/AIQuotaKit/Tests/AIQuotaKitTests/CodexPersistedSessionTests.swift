import Foundation
import Testing
@testable import AIQuotaKit

@Suite("Codex native saved session restoration", .serialized)
struct CodexNativeSessionPersistenceTests {
    private func jwt(_ workspace: String) -> String {
        let data = Data("{\"chatgpt_account_id\":\"\(workspace)\",\"sub\":\"fixture-user\"}".utf8)
        return "e30.\(data.base64EncodedString().replacingOccurrences(of: "=", with: "")).fixture"
    }

    @Test("saved account-local session survives coordinator recreation when WebKit is empty")
    func restoresPersistedSessionWithoutCookies() async throws {
        try #require(StorageTestIsolation.isRunningTests)
        let defaultsKeys = ["app.installedAt.v2", "codex.signedOutByUser"]
        let defaultsValues = defaultsKeys.map { UserDefaults.standard.object(forKey: $0) }
        defer { for (key, value) in zip(defaultsKeys, defaultsValues) { UserDefaults.standard.set(value, forKey: key) } }
        UserDefaults.standard.removeObject(forKey: defaultsKeys[0])
        UserDefaults.standard.removeObject(forKey: defaultsKeys[1])
        for storageID in [nil, UUID()] {
            let key = storageID.map { "sessionToken.\($0.uuidString.lowercased())" } ?? "sessionToken"
            let workspace = "fixture-\(storageID?.uuidString ?? "primary")"
            let token = jwt(workspace)
            KeychainStore.save("synthetic-persisted-session", forKey: key)
            defer { KeychainStore.delete(forKey: key) }
            try #require(KeychainStore.load(forKey: key) == "synthetic-persisted-session")
            for _ in 0..<2 {
                let sut = CodexAuthCoordinator(accountStorageID: storageID,
                    probe: { .notFound }, headlessSessionReviver: { nil },
                    tokenRefresher: { session in
                        #expect(session == "synthetic-persisted-session")
                        return (token, .distantFuture)
                    }, oauthCredentialsLoader: { throw CodexOAuthCredentialsError.notFound },
                    expectedAccountID: { workspace }, contextWriter: { _ in },
                    interactiveSessionProvider: { _ in Issue.record("Restoration opened sign-in"); throw CancellationError() },
                    sessionClearer: {})
                await sut.bootstrap()
                #expect(await sut.state == .authenticated)
                #expect(KeychainStore.load(forKey: key) == "synthetic-persisted-session")
            }
        }
    }
}

@Suite("Codex saved session recovery", .serialized)
struct CodexSavedSessionRecoveryTests {
    private func jwt(_ workspace: String = "fixture-workspace") -> String {
        let data = Data("{\"chatgpt_account_id\":\"\(workspace)\",\"sub\":\"fixture-user\"}".utf8)
        return "e30.\(data.base64EncodedString().replacingOccurrences(of: "=", with: "")).fixture"
    }
    private func primaryDefaults() -> () -> Void {
        let keys = ["app.installedAt.v2", "codex.signedOutByUser"]
        let old = keys.map { UserDefaults.standard.object(forKey: $0) }
        UserDefaults.standard.set(true, forKey: keys[0])
        UserDefaults.standard.removeObject(forKey: keys[1])
        return { for (key, value) in zip(keys, old) { UserDefaults.standard.set(value, forKey: key) } }
    }
    private func coordinator(_ id: UUID?, saved: @escaping @Sendable () -> String? = { "fixture-saved-session" },
                             probe: @escaping CodexAuthCoordinator.SessionProbe = { .notFound },
                             refresh: @escaping CodexAuthCoordinator.AccessTokenRefresher,
                             writes: LockIsolated<Int> = .init(0),
                             clock: LockIsolated<Date> = .init(.now)) -> CodexAuthCoordinator {
        CodexAuthCoordinator(accountStorageID: id, probe: probe, headlessSessionReviver: { nil },
            tokenRefresher: refresh, sessionTokenLoader: saved,
            oauthCredentialsLoader: { throw CodexOAuthCredentialsError.notFound },
            expectedAccountID: { "fixture-workspace" }, contextWriter: { _ in writes.withLock { $0 += 1 } },
            interactiveSessionProvider: { _ in Issue.record("Silent recovery opened login"); throw CancellationError() },
            sessionClearer: {}, now: { clock.value })
    }

    @Test("primary and additional accounts renew saved sessions before consulting WebKit")
    func launchParity() async throws {
        let reset = primaryDefaults(); defer { reset() }
        let token = jwt()
        for id in [nil, UUID()] {
            for _ in 0..<2 {
                let writes = LockIsolated(0)
                let sut = coordinator(id, probe: { Issue.record("Usable saved session should not require WebKit"); return .notFound },
                    refresh: { session in #expect(session == "fixture-saved-session"); return (token, .distantFuture) }, writes: writes)
                await sut.bootstrap()
                #expect(await sut.state == .authenticated)
                #expect(try await sut.accessContext().accountID == "fixture-workspace")
                #expect(await sut.restorationFailure == nil)
                #expect(writes.value == 1)
            }
        }
    }

    @Test("offline update preserves the saved session and both account kinds recover after backoff")
    func offlineThenRecovery() async throws {
        let reset = primaryDefaults(); defer { reset() }
        let token = jwt()
        for id in [nil, UUID()] {
            let online = LockIsolated(false), calls = LockIsolated(0), clock = LockIsolated(Date.now), writes = LockIsolated(0)
            let sut = coordinator(id, refresh: { _ in
                calls.withLock { $0 += 1 }
                guard online.value else { throw URLError(.notConnectedToInternet) }
                return (token, .distantFuture)
            }, writes: writes, clock: clock)
            await sut.bootstrap()
            #expect(await sut.hasRetryableRestoration)
            #expect(writes.value == 0)
            for _ in 0..<3 { #expect(!(await sut.retryTransientRestorationIfNeeded())) }
            #expect(calls.value == 1)
            online.withLock { $0 = true }; clock.withLock { $0 = $0.addingTimeInterval(30) }
            #expect(await sut.retryTransientRestorationIfNeeded())
            #expect(await sut.state == .authenticated)
            #expect(await sut.restorationFailure == nil)
            #expect(writes.value == 1)
        }
    }

    @Test("expired and wrong-workspace saved sessions do not authenticate either account kind")
    func rejectionParity() async {
        let reset = primaryDefaults(); defer { reset() }
        let wrong = jwt("other-workspace")
        for id in [nil, UUID()] {
            for wrongIdentity in [false, true] {
                let writes = LockIsolated(0)
                let sut = coordinator(id, refresh: { _ in
                    if wrongIdentity { return (wrong, .distantFuture) }
                    throw NetworkError.tokenExpired
                }, writes: writes)
                await sut.bootstrap()
                #expect(await sut.state == .unauthenticated)
                #expect(await sut.restorationFailure?.needsReconnect == true)
                #expect(!(await sut.hasRetryableRestoration))
                #expect(writes.value == 0)
            }
        }
    }

    @Test("rejected saved session can be replaced only by verified account-local browser recovery")
    func browserFallback() async throws {
        let reset = primaryDefaults(); defer { reset() }
        let token = jwt()
        for id in [nil, UUID()] {
            let sut = coordinator(id, probe: { .found(sessionToken: "fixture-browser-session") }, refresh: { session in
                if session == "fixture-saved-session" { throw NetworkError.tokenExpired }
                #expect(session == "fixture-browser-session")
                return (token, .distantFuture)
            })
            await sut.bootstrap()
            #expect(await sut.state == .authenticated)
            #expect(await sut.restorationFailure == nil)
        }
    }

    @Test("explicit sign-out wins over a retained saved session on the next launch")
    func signOutParity() async throws {
        let reset = primaryDefaults(); defer { reset() }
        let token = jwt()
        for id in [nil, UUID()] {
            let key = id.map { "codex.signedOutByUser.\($0.uuidString.lowercased())" } ?? "codex.signedOutByUser"
            defer { UserDefaults.standard.removeObject(forKey: key) }
            let first = coordinator(id, refresh: { _ in (token, .distantFuture) })
            await first.bootstrap(); try await first.signOut()
            let next = coordinator(id, saved: { Issue.record("Signed-out account read its saved session"); return "fixture" },
                refresh: { _ in Issue.record("Signed-out account tried renewal"); return (token, .distantFuture) })
            await next.bootstrap()
            #expect(await next.state == .signedOutByUser)
            #expect(!(await next.retryTransientRestorationIfNeeded()))
        }
    }

    @Test("canceling saved-session renewal cannot publish a late authenticated result")
    func canceledSavedRenewal() async {
        let entered = LockIsolated(false), release = LockIsolated(false), writes = LockIsolated(0), token = jwt()
        let sut = coordinator(UUID(), refresh: { _ in
            entered.withLock { $0 = true }
            while !release.value { try? await Task.sleep(for: .milliseconds(1)) }
            return (token, .distantFuture)
        }, writes: writes)
        let task = Task { await sut.bootstrap() }
        while !entered.value { await Task.yield() }
        task.cancel(); release.withLock { $0 = true }; await task.value
        #expect(await sut.state == .unauthenticated)
        #expect(await sut.hasRetryableRestoration)
        #expect(writes.value == 0)
    }

    @Test("saved sessions survive separate process launches and offline/rejection failures",
          .enabled(if: ProcessInfo.processInfo.environment["AIQUOTA_RELAUNCH_FIXTURE"] != nil))
    func crossProcessSavedSession() async throws {
        // The runner supplies a fresh UUID Keychain namespace shared by its
        // child processes. Files contain only synthetic context evidence.
        try #require(StorageTestIsolation.isRunningTests)
        let reset = primaryDefaults(); defer { reset() }
        let env = ProcessInfo.processInfo.environment
        let folder = URL(fileURLWithPath: try #require(env["AIQUOTA_RELAUNCH_FIXTURE"]))
        let namespace = try #require(env["AIQUOTA_TEST_STORE_ID"])
        try #require(UUID(uuidString: namespace) != nil)
        let phase = try #require(env["AIQUOTA_RELAUNCH_PHASE"])
        try #require(["seed", "restore", "offline", "expired", "wrong", "cleanup"].contains(phase))
        let token = jwt(), wrong = jwt("other-workspace")
        for id in [nil, UUID(uuidString: "C7BB91A3-62DB-4A66-B663-CBB90754F3B8")] {
            let path = folder.appendingPathComponent(id == nil ? "primary.json" : "additional.json")
            let previous = try? Data(contentsOf: path)
            let key = id.map { "sessionToken.\($0.uuidString.lowercased())" } ?? "sessionToken"
            if phase == "cleanup" {
                KeychainStore.delete(forKey: key)
                #expect(KeychainStore.load(forKey: key) == nil)
                continue
            }
            if phase == "seed" { KeychainStore.delete(forKey: key) }
            else {
                try #require(previous != nil)
                try #require(KeychainStore.load(forKey: key) == "synthetic-process-session")
            }
            let sut = CodexAuthCoordinator(accountStorageID: id,
                probe: { phase == "seed" ? .found(sessionToken: "synthetic-process-session") : .notFound },
                headlessSessionReviver: { nil }, tokenRefresher: { session in
                    #expect(session == "synthetic-process-session")
                    switch phase {
                    case "offline": throw URLError(.notConnectedToInternet)
                    case "expired": throw NetworkError.tokenExpired
                    case "wrong": return (wrong, .distantFuture)
                    default: return (token, .distantFuture)
                    }
                }, oauthCredentialsLoader: { throw CodexOAuthCredentialsError.notFound },
                expectedAccountID: { "fixture-workspace" }, contextWriter: { context in
                    try! JSONEncoder().encode(context).write(to: path, options: .atomic)
                }, interactiveSessionProvider: { _ in Issue.record("Relaunch opened sign-in"); throw CancellationError() },
                sessionClearer: {})
            await sut.bootstrap()
            #expect(KeychainStore.load(forKey: key) == "synthetic-process-session")
            if phase == "seed" || phase == "restore" {
                #expect(await sut.state == .authenticated)
                #expect(try await sut.accessContext().accountID == "fixture-workspace")
                let persisted = try JSONDecoder().decode(SharedCodexAuthContext.self, from: Data(contentsOf: path))
                #expect(persisted.sessionToken == "synthetic-process-session")
            } else {
                #expect(await sut.state == .unauthenticated)
                #expect(await sut.hasRetryableRestoration == (phase == "offline"))
                #expect(try Data(contentsOf: path) == previous)
            }
        }
        print("PROCESS_RELAUNCH phase=\(phase) pid=\(ProcessInfo.processInfo.processIdentifier) accounts=2")
    }

}

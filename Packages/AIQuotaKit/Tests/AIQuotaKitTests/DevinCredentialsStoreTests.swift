import Foundation
import SQLite3
import Testing
@testable import AIQuotaKit
@testable import MobileAccessCore

private func withTempHome<T>(_ body: (URL) throws -> T) throws -> T {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    return try body(dir)
}

@Test func credentialsFileParsesTOML() throws {
    let text = """
        windsurf_api_key = "devin-session-token$abc123"
        api_server_url = "https://server.codeium.com"
        other_field = "ignored"
        """
    let parsed = try #require(DevinCredentialsStore.CredentialsFile.parse(text))
    #expect(parsed.apiKey == "devin-session-token$abc123")
    #expect(parsed.apiServerURL?.absoluteString == "https://server.codeium.com")
}

@Test func credentialsFileToleratesCommentsAndMissingURL() throws {
    let text = """
        # comment
        api_server_url = 'https://custom.example.com'

        windsurf_api_key = 'devin-session-token$xyz' # trailing
        """
    let parsed = try #require(DevinCredentialsStore.CredentialsFile.parse(text))
    #expect(parsed.apiKey == "devin-session-token$xyz")
    #expect(parsed.apiServerURL?.absoluteString == "https://custom.example.com")
}

@Test func credentialsFileRejectsMissingKey() {
    #expect(DevinCredentialsStore.CredentialsFile.parse("api_server_url = \"https://x\"") == nil)
    #expect(DevinCredentialsStore.CredentialsFile.parse("windsurf_api_key = \"\"") == nil)
    #expect(DevinCredentialsStore.CredentialsFile.parse("") == nil)
}

@Test func cliCredentialReadsFromDefaultAndXDGPaths() throws {
    try withTempHome { home in
        #expect(DevinCredentialsStore.cliCredential(environment: [:], home: home) == nil)

        let dir = home.appendingPathComponent(".local/share/devin")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "windsurf_api_key = \"devin-session-token$home\"\n"
            .write(to: dir.appendingPathComponent("credentials.toml"), atomically: true, encoding: .utf8)

        let credential = try #require(DevinCredentialsStore.cliCredential(environment: [:], home: home))
        #expect(credential.apiKey == "devin-session-token$home")
        #expect(credential.source == .cli)
        #expect(credential.apiServerURL == DevinAPI.defaultAPIServerURL)

        // XDG path takes precedence.
        let xdg = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: xdg) }
        try FileManager.default.createDirectory(at: xdg.appendingPathComponent("devin"), withIntermediateDirectories: true)
        try "windsurf_api_key = \"devin-session-token$xdg\"\n"
            .write(to: xdg.appendingPathComponent("devin/credentials.toml"), atomically: true, encoding: .utf8)

        let xdgCredential = try #require(DevinCredentialsStore.cliCredential(
            environment: ["XDG_DATA_HOME": xdg.path], home: home
        ))
        #expect(xdgCredential.apiKey == "devin-session-token$xdg")
    }
}

@Test func appStateCredentialReadsSQLiteAuthStatus() throws {
    try withTempHome { home in
        let dbDir = home.appendingPathComponent("Library/Application Support/Devin/User/globalStorage")
        try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        let dbPath = dbDir.appendingPathComponent("state.vscdb").path

        var db: OpaquePointer?
        #expect(sqlite3_open(dbPath, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        sqlite3_exec(db, "CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value TEXT)", nil, nil, nil)
        let json = #"{"apiKey": "devin-session-token$dbkey"}"#
        let escaped = json.replacingOccurrences(of: "'", with: "''")
        sqlite3_exec(db, "INSERT INTO ItemTable (key, value) VALUES ('windsurfAuthStatus', '\(escaped)')", nil, nil, nil)

        let credential = try #require(DevinCredentialsStore.appStateCredential(home: home))
        #expect(credential.apiKey == "devin-session-token$dbkey")
        #expect(credential.source == .appState)
    }
}

@Test func candidateOrderIsCLIThenAppState() throws {
    try withTempHome { home in
        let cliDir = home.appendingPathComponent(".local/share/devin")
        try FileManager.default.createDirectory(at: cliDir, withIntermediateDirectories: true)
        try "windsurf_api_key = \"devin-session-token$cli\"\n"
            .write(to: cliDir.appendingPathComponent("credentials.toml"), atomically: true, encoding: .utf8)

        let dbDir = home.appendingPathComponent("Library/Application Support/Devin/User/globalStorage")
        try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        let dbPath = dbDir.appendingPathComponent("state.vscdb").path
        var db: OpaquePointer?
        #expect(sqlite3_open(dbPath, &db) == SQLITE_OK)
        sqlite3_exec(db, "CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value TEXT)", nil, nil, nil)
        sqlite3_exec(db, #"INSERT INTO ItemTable (key, value) VALUES ('windsurfAuthStatus', '{"apiKey": "devin-session-token$app"}')"#, nil, nil, nil)
        sqlite3_close(db)

        let sources = DevinCredentialsStore.candidates(environment: [:], home: home).map(\.source)
        #expect(sources.count >= 2 && sources[0] == .cli && sources[1] == .appState)
        #expect(DevinCredentialsStore.hasDiscoverableCredential(environment: [:], home: home))
    }
}

@Test func devinCoordinatorFallsThroughStaleCLICredential() async throws {
    // CLI token is stale (validator rejects), app-state token validates — the
    // coordinator must keep walking the candidate list.
    let coordinator = DevinAuthCoordinator(
        credentialResolver: {
            [
                DevinCredential(apiKey: "stale-cli", apiServerURL: DevinAPI.defaultAPIServerURL, source: .cli),
                DevinCredential(apiKey: "valid-app", apiServerURL: DevinAPI.defaultAPIServerURL, source: .appState),
            ]
        },
        credentialValidator: { $0.apiKey == "valid-app" }
    )

    try await coordinator.signIn()
    #expect(await coordinator.state == .authenticated)
    let context = try await coordinator.requestContext()
    #expect(context.apiKey == "valid-app")
    #expect(context.source == .appState)
}

@Test func devinCoordinatorFailsWhenAllCandidatesRejected() async throws {
    let coordinator = DevinAuthCoordinator(
        credentialResolver: {
            [DevinCredential(apiKey: "bad", apiServerURL: DevinAPI.defaultAPIServerURL, source: .cli)]
        },
        credentialValidator: { _ in false }
    )
    await #expect(throws: NetworkError.self) { try await coordinator.signIn() }
    #expect(await coordinator.state == .unauthenticated)
}

@Test func devinCoordinatorRequestContextThrowsWhenUnauthenticated() async throws {
    let coordinator = DevinAuthCoordinator(credentialResolver: { [] })
    await #expect(throws: NetworkError.self) { try await coordinator.requestContext() }
}

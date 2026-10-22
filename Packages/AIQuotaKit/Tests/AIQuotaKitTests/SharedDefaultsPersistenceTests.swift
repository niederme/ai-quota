import Testing
import Foundation
@testable import AIQuotaKit

struct SharedDefaultsPersistenceTests {
    @Test("shared defaults force-persist mutations for widget consumers")
    func sharedDefaultsSynchronizeAfterWrites() throws {
        let source = try String(
            contentsOf: repoRoot.appending(path: "Packages/AIQuotaKit/Sources/AIQuotaKit/Storage/SharedDefaults.swift"),
            encoding: .utf8
        )

        #expect(source.contains("private static func persistChanges()"))
        #expect(source.contains("defaults.synchronize()"))
        #expect(source.contains("defaults.set(data, forKey: codexUsageKey)\n        persistChanges()"))
        #expect(source.contains("defaults.removeObject(forKey: codexUsageKey)\n        persistChanges()"))
        #expect(source.contains("defaults.set(data, forKey: claudeUsageKey)"))
        #expect(source.contains("defaults.set(currentClaudeUsageSchemaVersion, forKey: claudeUsageSchemaVersionKey)"))
        #expect(source.contains("defaults.integer(forKey: claudeUsageSchemaVersionKey) >= currentClaudeUsageSchemaVersion"))
        #expect(source.contains("defaults.removeObject(forKey: claudeUsageKey)\n        defaults.removeObject(forKey: claudeUsageSchemaVersionKey)\n        persistChanges()"))
        #expect(source.contains("defaults.set(data, forKey: settingsKey)\n        persistChanges()"))
        #expect(source.contains("defaults.set(data, forKey: enrolledServicesKey)\n        persistChanges()"))
        #expect(source.contains("defaults.removeObject(forKey: enrolledServicesKey)\n        persistChanges()"))
    }

    @Test("Claude source diagnostics retain only a redacted ring buffer")
    func claudeSourceDiagnosticsUseRingBuffer() {
        SharedDefaults.clearClaudeSourceAttempts()
        defer { SharedDefaults.clearClaudeSourceAttempts() }

        for index in 0..<12 {
            SharedDefaults.appendClaudeSourceAttempt(.init(
                source: .oauth,
                httpStatus: 400 + index,
                errorCategory: .authFailed,
                timestamp: Date(timeIntervalSince1970: Double(index))
            ))
        }

        let attempts = SharedDefaults.loadClaudeSourceAttempts()
        #expect(attempts.count == 10)
        #expect(attempts.first?.httpStatus == 402)
        #expect(attempts.last?.httpStatus == 411)
    }

    @Test("Codex source diagnostics retain only a redacted ring buffer")
    func codexSourceDiagnosticsUseRingBuffer() {
        SharedDefaults.clearCodexSourceAttempts()
        defer { SharedDefaults.clearCodexSourceAttempts() }

        for index in 0..<12 {
            SharedDefaults.appendCodexSourceAttempt(.init(
                source: .codexOAuth,
                httpStatus: 500 + index,
                errorCategory: .serverError,
                timestamp: Date(timeIntervalSince1970: Double(index))
            ))
        }

        let attempts = SharedDefaults.loadCodexSourceAttempts()
        #expect(attempts.count == 10)
        #expect(attempts.first?.httpStatus == 502)
        #expect(attempts.last?.httpStatus == 511)
    }

    @Test("Codex snapshots are isolated by account")
    func codexSnapshotsAreAccountScoped() {
        let firstID = UUID().uuidString
        let secondID = UUID().uuidString
        defer {
            SharedDefaults.clearUsage(forAccountID: firstID)
            SharedDefaults.clearUsage(forAccountID: secondID)
        }

        SharedDefaults.saveUsage(.placeholder, forAccountID: firstID)
        SharedDefaults.saveUsage(.placeholder, forAccountID: secondID)
        SharedDefaults.clearUsage(forAccountID: firstID)

        #expect(SharedDefaults.loadCachedUsage(forAccountID: firstID) == nil)
        #expect(SharedDefaults.loadCachedUsage(forAccountID: secondID) != nil)
    }

    @Test("Claude snapshots are isolated by account")
    func claudeSnapshotsAreAccountScoped() {
        let firstID = UUID().uuidString
        let secondID = UUID().uuidString
        defer {
            SharedDefaults.clearClaudeUsage(forAccountID: firstID)
            SharedDefaults.clearClaudeUsage(forAccountID: secondID)
        }

        SharedDefaults.saveClaudeUsage(.placeholder, forAccountID: firstID)
        SharedDefaults.saveClaudeUsage(.placeholder, forAccountID: secondID)
        SharedDefaults.clearClaudeUsage(forAccountID: firstID)

        #expect(SharedDefaults.loadCachedClaudeUsage(forAccountID: firstID) == nil)
        #expect(SharedDefaults.loadCachedClaudeUsage(forAccountID: secondID) != nil)
    }

    @Test("connected account IDs are stable UUID strings and metadata contains no credentials")
    func connectedAccountMetadataIsNonSecret() throws {
        let id = UUID()
        let account = ConnectedAccount(
            id: id,
            provider: .codex,
            displayLabel: "Work",
            workspaceID: "workspace-123",
            authSource: .oauth
        )

        #expect(account.id == id.uuidString)
        let json = String(decoding: try JSONEncoder().encode(account), as: UTF8.self)
        #expect(!json.contains("accessToken"))
        #expect(!json.contains("sessionToken"))
        #expect(!json.contains("cookie"))
    }

    private var repoRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

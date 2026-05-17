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

    private var repoRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

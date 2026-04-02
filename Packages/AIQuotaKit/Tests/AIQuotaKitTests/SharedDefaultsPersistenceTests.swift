import Testing
import Foundation

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
        #expect(source.contains("defaults.set(data, forKey: claudeUsageKey)\n        persistChanges()"))
        #expect(source.contains("defaults.removeObject(forKey: claudeUsageKey)\n        persistChanges()"))
        #expect(source.contains("defaults.set(data, forKey: settingsKey)\n        persistChanges()"))
        #expect(source.contains("defaults.set(data, forKey: enrolledServicesKey)\n        persistChanges()"))
        #expect(source.contains("defaults.removeObject(forKey: enrolledServicesKey)\n        persistChanges()"))
    }

    private var repoRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

import Foundation
import Testing
@testable import AIQuotaKit

@Suite("AuthInstallState", .serialized)
struct AuthInstallStateTests {
    init() {
        UserDefaults.standard.removeObject(forKey: "onboarding.v1.hasCompleted")
        SharedDefaults.clearUsage()
        SharedDefaults.clearClaudeUsage()
    }

    @Test("existing install when onboarding has completed even without website data")
    func existingInstallFromOnboardingMarker() {
        let (suiteName, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "onboarding.v1.hasCompleted")

        #expect(AuthInstallState.isExistingInstall(hasWebsiteData: false, userDefaults: defaults))
    }

    @Test("fresh install when no website data and no persisted app state")
    func freshInstallWithoutState() {
        let (suiteName, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(!AuthInstallState.isExistingInstall(hasWebsiteData: false, userDefaults: defaults))
    }

    @Test("fresh install cleanup does not clear provider WebKit sessions")
    func freshInstallCleanupDoesNotClearWebKitSessions() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let claude = try String(
            contentsOf: root.appendingPathComponent("Sources/AIQuotaKit/Auth/ClaudeAuthCoordinator.swift"),
            encoding: .utf8
        )
        let codex = try String(
            contentsOf: root.appendingPathComponent("Sources/AIQuotaKit/Auth/CodexAuthCoordinator.swift"),
            encoding: .utf8
        )

        #expect(claude.contains("Do not clear WebKit cookies here"))
        #expect(codex.contains("Do not clear WebKit cookies here"))
    }

    private func isolatedDefaults() -> (suiteName: String, defaults: UserDefaults) {
        let suiteName = "AIQuotaKit.AuthInstallStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (suiteName, defaults)
    }
}

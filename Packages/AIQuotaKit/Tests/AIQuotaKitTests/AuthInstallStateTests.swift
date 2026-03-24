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
        UserDefaults.standard.set(true, forKey: "onboarding.v1.hasCompleted")
        defer { UserDefaults.standard.removeObject(forKey: "onboarding.v1.hasCompleted") }

        #expect(AuthInstallState.isExistingInstall(hasWebsiteData: false))
    }

    @Test("fresh install when no website data and no persisted app state")
    func freshInstallWithoutState() {
        #expect(!AuthInstallState.isExistingInstall(hasWebsiteData: false))
    }
}

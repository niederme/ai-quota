import Foundation
import WebKit

enum AuthInstallState {
    static let onboardingCompletedKey = "onboarding.v1.hasCompleted"

    static func isExistingInstall(hasWebsiteData: Bool) -> Bool {
        hasWebsiteData ||
        UserDefaults.standard.object(forKey: onboardingCompletedKey) != nil ||
        SharedDefaults.loadCachedUsage() != nil ||
        SharedDefaults.loadCachedClaudeUsage() != nil
    }

    static func isExistingInstall() async -> Bool {
        let hasWebsiteData: Bool = await withCheckedContinuation { cont in
            Task { @MainActor in
                let records = await WKWebsiteDataStore.default()
                    .dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
                cont.resume(returning: !records.isEmpty)
            }
        }
        return isExistingInstall(hasWebsiteData: hasWebsiteData)
    }
}

import AppKit
import AIQuotaKit

final class AnalyticsAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = SharedDefaults.loadSettings()
        AnalyticsClient.shared.bootstrap(initialCollectionEnabled: settings.analyticsEnabled)

        let enrolledServices = SharedDefaults.loadEnrolledServices()
        let services = switch enrolledServices.count {
        case 0: "none"
        case 1: enrolledServices.first?.rawValue ?? "none"
        default: "both"
        }

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let onboardingCompleted = UserDefaults.standard.bool(forKey: "onboarding.v1.hasCompleted")
        Task {
            await AnalyticsClient.shared.send(
                "app_launched",
                params: [
                    "app_version": appVersion,
                    "services": services,
                    "service_count": String(enrolledServices.count),
                    "menu_bar_service": settings.menuBarService.rawValue,
                    "notifications_enabled": settings.notifications.enabled ? "true" : "false",
                    "onboarding_completed": onboardingCompleted ? "true" : "false"
                ],
                enabled: settings.analyticsEnabled
            )
        }
    }
}

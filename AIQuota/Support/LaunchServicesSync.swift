import AppKit
import Foundation
import OSLog
import AIQuotaKit

enum LaunchServicesSync {
    private static let logger = Logger(subsystem: "ai.quota", category: "launchservices")
    private static let lastRegisteredVersionKey = "launchServices.lastRegisteredBundleVersion"
    private static let lastRegisteredPathKey = "launchServices.lastRegisteredBundlePath"
    private static let lsregisterPath =
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    static func repairIfNeeded() {
        let bundleVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let bundlePath = Bundle.main.bundleURL.path

        let defaults = UserDefaults.standard
        let alreadyRegisteredVersion = defaults.string(forKey: lastRegisteredVersionKey)
        let alreadyRegisteredPath = defaults.string(forKey: lastRegisteredPathKey)

        guard WidgetBundleRegistrationPolicy.shouldRepair(
            currentVersion: bundleVersion,
            currentPath: bundlePath,
            lastRegisteredVersion: alreadyRegisteredVersion,
            lastRegisteredPath: alreadyRegisteredPath
        ) else {
            return
        }

        Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: lsregisterPath)
            process.arguments = ["-f", "-R", "-trusted", bundlePath]

            do {
                try process.run()
                process.waitUntilExit()

                guard process.terminationStatus == 0 else {
                    logger.error("LaunchServices registration failed with status \(process.terminationStatus)")
                    return
                }

                defaults.set(bundleVersion, forKey: lastRegisteredVersionKey)
                defaults.set(bundlePath, forKey: lastRegisteredPathKey)
                logger.info("LaunchServices refreshed for bundle version \(bundleVersion, privacy: .public)")
            } catch {
                logger.error("LaunchServices registration threw error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

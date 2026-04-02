import AppKit
import Foundation
import OSLog
import AIQuotaKit
import WidgetKit

enum LaunchServicesSync {
    private static let logger = Logger(subsystem: "ai.quota", category: "launchservices")
    private static let lastRegisteredVersionKey = "launchServices.lastRegisteredBundleVersion"
    private static let lastRegisteredPathKey = "launchServices.lastRegisteredBundlePath"
    private static let lastRestartedWidgetHostVersionKey = "launchServices.lastRestartedWidgetHostVersion"
    private static let lastRestartedWidgetHostPathKey = "launchServices.lastRestartedWidgetHostPath"
    private static let lsregisterPath =
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    private static let killallPath = "/usr/bin/killall"
    private static let widgetHostProcesses = ["AIQuotaWidget", "chronod"]

    static func repairIfNeeded() {
        let bundleVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let bundlePath = Bundle.main.bundleURL.path

        let defaults = UserDefaults.standard
        let alreadyRegisteredVersion = defaults.string(forKey: lastRegisteredVersionKey)
        let alreadyRegisteredPath = defaults.string(forKey: lastRegisteredPathKey)
        let alreadyRestartedVersion = defaults.string(forKey: lastRestartedWidgetHostVersionKey)
        let alreadyRestartedPath = defaults.string(forKey: lastRestartedWidgetHostPathKey)

        let shouldRepairRegistration = WidgetBundleRegistrationPolicy.shouldRepair(
            currentVersion: bundleVersion,
            currentPath: bundlePath,
            lastRegisteredVersion: alreadyRegisteredVersion,
            lastRegisteredPath: alreadyRegisteredPath
        )
        let shouldRestartHosts = WidgetBundleRegistrationPolicy.shouldRestartWidgetHosts(
            currentVersion: bundleVersion,
            currentPath: bundlePath,
            lastRestartedVersion: alreadyRestartedVersion,
            lastRestartedPath: alreadyRestartedPath
        )

        guard shouldRepairRegistration || shouldRestartHosts else {
            return
        }

        Task.detached(priority: .utility) {
            if shouldRepairRegistration {
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
                    return
                }
            }

            if shouldRestartHosts {
                restartWidgetHosts(bundleVersion: bundleVersion, bundlePath: bundlePath, defaults: defaults)
            }
        }
    }

    private static func restartWidgetHosts(bundleVersion: String, bundlePath: String, defaults: UserDefaults) {
        for processName in widgetHostProcesses {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: killallPath)
            process.arguments = [processName]

            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    logger.info("Restarted widget host process \(processName, privacy: .public)")
                } else {
                    logger.warning("Widget host restart for \(processName, privacy: .public) exited with status \(process.terminationStatus)")
                }
            } catch {
                logger.warning("Widget host restart for \(processName, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        defaults.set(bundleVersion, forKey: lastRestartedWidgetHostVersionKey)
        defaults.set(bundlePath, forKey: lastRestartedWidgetHostPathKey)
        defaults.synchronize()

        Task {
            try? await Task.sleep(for: .seconds(1))
            WidgetCenter.shared.reloadAllTimelines()
        }
        logger.info("Queued widget timeline reload after host restart for bundle version \(bundleVersion, privacy: .public)")
    }
}

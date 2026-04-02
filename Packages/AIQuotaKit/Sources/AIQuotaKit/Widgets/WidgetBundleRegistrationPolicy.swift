import Foundation

public enum WidgetBundleRegistrationPolicy {
    public static func shouldRepair(
        currentVersion: String,
        currentPath: String,
        lastRegisteredVersion: String?,
        lastRegisteredPath: String?
    ) -> Bool {
        currentVersion != lastRegisteredVersion || currentPath != lastRegisteredPath
    }

    public static func shouldRestartWidgetHosts(
        currentVersion: String,
        currentPath: String,
        lastRestartedVersion: String?,
        lastRestartedPath: String?
    ) -> Bool {
        currentVersion != lastRestartedVersion || currentPath != lastRestartedPath
    }
}

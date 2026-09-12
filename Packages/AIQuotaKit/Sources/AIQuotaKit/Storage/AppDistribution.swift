import Foundation

public enum AppDistribution {
    /// Package compilation flags are independent of the host target's APP_STORE flag.
    /// Both store app and widget plists carry this explicit runtime channel marker.
    public static var allowsHostCredentialDiscovery: Bool {
        allowsHostCredentialDiscovery(info: Bundle.main.infoDictionary ?? [:])
    }

    static func allowsHostCredentialDiscovery(info: [String: Any]) -> Bool {
        info["AIQuotaAppStoreBuild"] as? Bool != true
    }
}

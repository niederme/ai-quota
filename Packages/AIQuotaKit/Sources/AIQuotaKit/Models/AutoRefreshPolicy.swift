import Foundation

public struct AutoRefreshContext: Sendable, Equatable {
    public var appIsActive: Bool
    public var lowPowerModeEnabled: Bool
    public var networkAvailable: Bool
    public var machineIdleSeconds: TimeInterval
    public var hasCachedUsageData: Bool
    public var codexNearThreshold: Bool
    public var claudeNearThreshold: Bool

    public var nearThreshold: Bool {
        codexNearThreshold || claudeNearThreshold
    }

    public init(
        appIsActive: Bool,
        lowPowerModeEnabled: Bool,
        networkAvailable: Bool,
        machineIdleSeconds: TimeInterval,
        hasCachedUsageData: Bool,
        codexNearThreshold: Bool,
        claudeNearThreshold: Bool
    ) {
        self.appIsActive = appIsActive
        self.lowPowerModeEnabled = lowPowerModeEnabled
        self.networkAvailable = networkAvailable
        self.machineIdleSeconds = machineIdleSeconds
        self.hasCachedUsageData = hasCachedUsageData
        self.codexNearThreshold = codexNearThreshold
        self.claudeNearThreshold = claudeNearThreshold
    }
}

public enum AutoRefreshPolicy {
    public static func interval(for context: AutoRefreshContext) -> TimeInterval {
        let idleSeconds = max(0, context.machineIdleSeconds)

        if !context.networkAvailable || context.lowPowerModeEnabled || idleSeconds >= 1_800 {
            return 1_800
        }

        if context.appIsActive || context.nearThreshold {
            return 60
        }

        if !context.hasCachedUsageData {
            return 300
        }

        if idleSeconds >= 900 {
            return 900
        }

        if idleSeconds >= 300 {
            return 600
        }

        return 300
    }
}

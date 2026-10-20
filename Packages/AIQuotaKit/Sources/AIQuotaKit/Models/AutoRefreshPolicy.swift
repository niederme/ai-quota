import Foundation
import MobileAccessCore

public struct AutoRefreshContext: Sendable, Equatable {
    public var lowPowerModeEnabled: Bool
    public var networkAvailable: Bool
    public var machineIdleSeconds: TimeInterval
    public var serviceRecentlyActive: Bool
    public var codexNearThreshold: Bool
    public var claudeNearThreshold: Bool
    public var devinNearThreshold: Bool

    public var nearThreshold: Bool {
        codexNearThreshold || claudeNearThreshold || devinNearThreshold
    }

    public init(
        lowPowerModeEnabled: Bool,
        networkAvailable: Bool,
        machineIdleSeconds: TimeInterval,
        serviceRecentlyActive: Bool,
        codexNearThreshold: Bool,
        claudeNearThreshold: Bool,
        devinNearThreshold: Bool = false
    ) {
        self.lowPowerModeEnabled = lowPowerModeEnabled
        self.networkAvailable = networkAvailable
        self.machineIdleSeconds = machineIdleSeconds
        self.serviceRecentlyActive = serviceRecentlyActive
        self.codexNearThreshold = codexNearThreshold
        self.claudeNearThreshold = claudeNearThreshold
        self.devinNearThreshold = devinNearThreshold
    }
}

public enum AutoRefreshPolicy {
    public static func interval(for context: AutoRefreshContext) -> TimeInterval {
        let idleSeconds = max(0, context.machineIdleSeconds)

        if !context.networkAvailable || context.lowPowerModeEnabled || idleSeconds >= 300 {
            return 600
        }

        if context.serviceRecentlyActive || context.nearThreshold {
            return 60
        }

        return 300
    }
}

public enum AutoRefreshActivity {
    public static func changed(from previous: CodexUsage?, to current: CodexUsage) -> Bool {
        guard let previous else { return false }
        return previous.monthlyBudget?.used != current.monthlyBudget?.used
            || previous.monthlyBudget?.limit != current.monthlyBudget?.limit
            || previous.weeklyUsedPercent != current.weeklyUsedPercent
            || previous.hourlyUsedPercent != current.hourlyUsedPercent
            || previous.limitReached != current.limitReached
            || previous.allowed != current.allowed
            || previous.creditBalance != current.creditBalance
            || previous.bonusCreditsSpentThisMonth != current.bonusCreditsSpentThisMonth
            || previous.approxLocalMessages != current.approxLocalMessages
            || previous.approxCloudMessages != current.approxCloudMessages
    }

    public static func changed(from previous: ClaudeUsage?, to current: ClaudeUsage) -> Bool {
        guard let previous else { return false }
        return previous.fiveHourUtilization != current.fiveHourUtilization
            || previous.sevenDayUtilization != current.sevenDayUtilization
            || previous.extraUsage?.usedCredits != current.extraUsage?.usedCredits
            || previous.extraUsage?.monthlyLimit != current.extraUsage?.monthlyLimit
            || previous.extraUsage?.isEnabled != current.extraUsage?.isEnabled
            || previous.bonusUsage != current.bonusUsage
            || previous.spendLimit?.used != current.spendLimit?.used
            || previous.spendLimit?.limit != current.spendLimit?.limit
    }

    public static func changed(from previous: DevinUsage?, to current: DevinUsage) -> Bool {
        guard let previous else { return false }
        return previous.dailyUsedPercent != current.dailyUsedPercent
            || previous.weeklyUsedPercent != current.weeklyUsedPercent
            || previous.overageBalanceUSD != current.overageBalanceUSD
            || previous.planName != current.planName
    }
}

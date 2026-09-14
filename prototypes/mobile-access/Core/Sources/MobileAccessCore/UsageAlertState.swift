import Foundation

public struct UsageAlertState: Codable, Sendable {
    public var windowEnd: Date
    public var highestNotified: Double
    public init(windowEnd: Date, highestNotified: Double = 0) {
        self.windowEnd = windowEnd; self.highestNotified = highestNotified
    }
    public func next(used: Double, now: Date, nearEnabled: Bool, nearThreshold: Double, limitEnabled: Bool) -> Double? {
        guard windowEnd > now, used.isFinite, (0...100).contains(used) else { return nil }
        if limitEnabled, used >= 100, highestNotified < 100 { return 100 }
        let threshold = min(99, max(5, nearThreshold.isFinite ? nearThreshold : 85))
        if nearEnabled, used >= threshold, highestNotified < threshold { return threshold }
        return nil
    }
}

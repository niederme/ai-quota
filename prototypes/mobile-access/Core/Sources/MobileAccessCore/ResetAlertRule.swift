import Foundation

public struct ResetAlertRule: Sendable, Equatable {
    public enum Mode: String, CaseIterable, Sendable { case off, nearLimit, everyReset }
    public let mode: Mode
    public let threshold: Double
    public init(mode: Mode = .nearLimit, threshold: Double = 90) {
        self.mode = mode
        self.threshold = threshold.isFinite ? min(100, max(1, threshold)) : 90
    }
    public func allows(usedPercent: Double) -> Bool {
        guard usedPercent.isFinite, (0...100).contains(usedPercent) else { return false }
        switch mode {
        case .off: return false
        case .nearLimit: return usedPercent >= threshold
        case .everyReset: return true
        }
    }
}

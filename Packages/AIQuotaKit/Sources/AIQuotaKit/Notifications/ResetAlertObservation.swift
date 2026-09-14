import Foundation

/// Remembers the greatest usage observed in a provider window. A passed clock
/// alone is not evidence of reset: the provider must report a new future window.
public struct ResetAlertObservation: Codable, Sendable, Equatable {
    public var end: Date
    public var peak: Double
    public init(end: Date, peak: Double) { self.end = end; self.peak = peak }
    public mutating func observe(used: Double, end next: Date, now: Date) -> Double? {
        guard used.isFinite, (0...100).contains(used) else { return nil }
        if next == end { peak = max(peak, used); return nil }
        let priorPeak = end <= now && next > now ? peak : nil
        end = next
        peak = used
        return priorPeak
    }
    public static func allows(priorPeak: Double?, minimum: Int) -> Bool {
        guard let priorPeak else { return false }
        return priorPeak >= Double(min(100, max(0, minimum)))
    }
}

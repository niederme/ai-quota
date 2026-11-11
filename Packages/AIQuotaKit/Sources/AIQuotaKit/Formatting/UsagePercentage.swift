/// Whole-number usage labels must not imply exhaustion while capacity remains.
public enum UsagePercentage {
    public static func roundedForDisplay(_ percent: Double) -> Int {
        guard let rounded = Int(exactly: percent.rounded()) else { return 0 }
        return percent < 100 ? min(99, rounded) : rounded
    }
}

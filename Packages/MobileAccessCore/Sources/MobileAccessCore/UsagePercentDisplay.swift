/// Whole-number usage labels must not imply exhaustion while capacity remains:
/// 99.6% reads "99%", and only a reading at or past the limit reads "100%".
/// Mirrors AIQuotaKit's `UsagePercentage.roundedForDisplay` (the Mac app links
/// both packages, so this stays internal to avoid an ambiguous public name).
func usagePercentForDisplay(_ percent: Double) -> Int {
    guard let rounded = Int(exactly: percent.rounded()) else { return 0 }
    return percent < 100 ? min(99, rounded) : rounded
}

public extension QuotaWindow {
    /// The used percentage as shown in labels.
    var displayPercent: Int { usagePercentForDisplay(usedPercent) }
}

public extension MonthlyBudget {
    /// The used percentage as shown in labels.
    var displayPercent: Int { usagePercentForDisplay(usedPercent) }
}

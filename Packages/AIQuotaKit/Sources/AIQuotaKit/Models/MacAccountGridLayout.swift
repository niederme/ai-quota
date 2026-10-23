import Foundation

/// The macOS overview uses the same vertical account rhythm as iOS. Keep the
/// viewport content-sized until the available screen height requires scrolling.
public enum MacAccountGridLayout {
    public static func columns(for width: Double) -> Int { 1 }

    public static func rows(accountCount: Int, width: Double) -> Int {
        let count = max(0, accountCount)
        let columnCount = columns(for: width)
        return (count + columnCount - 1) / columnCount
    }

    public static func viewportHeight(accountCount: Int, width: Double, availableHeight: Double) -> Double {
        let count = max(1, rows(accountCount: accountCount, width: width))
        // Match the 114-point visible dial plus 32 points of card padding,
        // 16-point inter-card spacing and
        // the ScrollView's 8-point top/bottom padding. Measured content takes
        // over once the cards have rendered, including any token history.
        return min(availableHeight, Double(count * 146 + (count - 1) * 16 + 16))
    }
}

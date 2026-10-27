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
        // Empty sheets show the same two service rows as the connected layout.
        let count = accountCount == 0 ? 2 : max(1, rows(accountCount: accountCount, width: width))
        // A 114-point dial, 21-point row insets and 8/16-point body insets.
        // Measured content takes over after layout, including token history.
        return min(availableHeight, Double(count * 156 + 24))
    }
}

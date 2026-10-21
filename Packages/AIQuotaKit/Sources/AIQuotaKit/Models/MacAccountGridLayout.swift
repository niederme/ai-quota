import Foundation

/// Row-major overview geometry. The final card in an odd row stays in the
/// first column; the scroll viewport only shrinks when the screen requires it.
public enum MacAccountGridLayout {
    public static func columns(for width: Double) -> Int { width >= 600 ? 2 : 1 }

    public static func rows(accountCount: Int, width: Double) -> Int {
        let count = max(0, accountCount)
        let columnCount = columns(for: width)
        return (count + columnCount - 1) / columnCount
    }

    public static func viewportHeight(accountCount: Int, width: Double, availableHeight: Double) -> Double {
        min(availableHeight, Double(max(1, rows(accountCount: accountCount, width: width))) * 180 + 16)
    }
}

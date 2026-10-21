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
        let count = max(1, rows(accountCount: accountCount, width: width))
        // Match MacAccountCard's 126-point minimum, 8-point row gap and the
        // ScrollView's 8-point top/bottom padding. Extra height belonged to
        // the viewport and appeared as a blank strip above the footer.
        return min(availableHeight, Double(count * 126 + (count - 1) * 8 + 16))
    }
}

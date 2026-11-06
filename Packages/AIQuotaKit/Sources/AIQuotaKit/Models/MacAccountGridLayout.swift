import Foundation

/// The macOS overview uses the same vertical account rhythm as iOS. Keep the
/// viewport content-sized until the available screen height requires scrolling.
public enum MacAccountGridLayout {
    public static let cardSpacing: Double = 8

    public static func columns(for width: Double) -> Int { 1 }

    public static func rows(accountCount: Int, width: Double) -> Int {
        let count = max(0, accountCount)
        let columnCount = columns(for: width)
        return (count + columnCount - 1) / columnCount
    }

    public static func viewportHeight(accountCount: Int, width: Double, availableHeight: Double) -> Double {
        // Empty sheets show the same two service rows as the connected layout.
        let count = accountCount == 0 ? 2 : max(1, rows(accountCount: accountCount, width: width))
        // A 114-point dial, 21-point row insets, card gaps and 8/16-point body insets.
        // Measured content takes over after layout, including token history.
        return min(availableHeight, Double(count * 156 + 24) + Double(count - 1) * cardSpacing)
    }

    /// The slot a dragged card would land in. `midYs` are the cards' resting
    /// centres in their current order, measured when the drag began; the
    /// dragged card passes a neighbour once its centre crosses that neighbour's.
    public static func reorderTarget(from index: Int, draggedMidY: Double, midYs: [Double]) -> Int {
        guard midYs.indices.contains(index) else { return index }
        return midYs.indices.filter { $0 != index && midYs[$0] < draggedMidY }.count
    }

    /// How a resting card makes room while another is dragged: -1 moves it up
    /// one slot, 1 moves it down one slot, 0 leaves it in place.
    public static func reorderShift(of index: Int, dragging from: Int, to target: Int) -> Int {
        if target > from, index > from, index <= target { return -1 }
        if target < from, index >= target, index < from { return 1 }
        return 0
    }

    /// The new order after dropping the card at `from` into slot `target`.
    public static func reordered<ID>(_ ids: [ID], from: Int, to target: Int) -> [ID] {
        guard ids.indices.contains(from) else { return ids }
        var result = ids
        let moved = result.remove(at: from)
        result.insert(moved, at: min(max(0, target), result.count))
        return result
    }
}

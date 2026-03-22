import SwiftUI
import AIQuotaKit

struct MenuBarIconView: View {
    let usedPercent: Int
    let secondaryPercent: Int
    let limitReached: Bool
    let isLoading: Bool
    /// Worst metric across all authenticated services — drives ring colour
    /// even when the displayed service is healthy.
    let worstPercent: Int
    var body: some View {
        Image(nsImage: GaugeImageMaker.image(
            primaryPercent: usedPercent,
            secondaryPercent: secondaryPercent,
            limitReached: limitReached,
            isLoading: isLoading,
            size: 22,
            worstPercent: worstPercent
        ))
        .interpolation(.high)
        .antialiased(true)
        .frame(width: 22, height: 22)
    }
}

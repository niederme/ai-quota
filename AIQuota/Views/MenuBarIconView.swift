import SwiftUI
import AIQuotaKit

struct MenuBarIconView: View {
    let usedPercent: Int
    let secondaryPercent: Int
    let limitReached: Bool
    let isLoading: Bool
    var body: some View {
        Image(nsImage: GaugeImageMaker.image(
            primaryPercent: usedPercent,
            secondaryPercent: secondaryPercent,
            limitReached: limitReached,
            isLoading: isLoading,
            size: 22
        ))
        .interpolation(.high)
        .antialiased(true)
        .frame(width: 22, height: 22)
    }
}

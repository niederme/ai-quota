import SwiftUI
import AIQuotaKit

struct MenuBarIconView: View {
    let usedPercent: Int
    let limitReached: Bool
    let isLoading: Bool

    var body: some View {
        Image(nsImage: GaugeImageMaker.image(
            usedPercent: usedPercent,
            limitReached: limitReached,
            isLoading: isLoading,
            size: 22
        ))
        .interpolation(.high)
        .antialiased(true)
        .frame(width: 22, height: 22)
    }
}

import SwiftUI
import AIQuotaKit

struct MenuBarIconView: View {
    let usage: CodexUsage?
    let isLoading: Bool

    var body: some View {
        Image(nsImage: GaugeImageMaker.image(
            usedPercent: usage?.weeklyUsedPercent ?? 0,
            limitReached: usage?.limitReached ?? false,
            isLoading: isLoading,
            size: 22
        ))
        .interpolation(.high)
        .antialiased(true)
        .frame(width: 22, height: 22)
    }
}

import SwiftUI
import AppKit
import AIQuotaKit

struct MenuBarGaugeInput {
    let usedPercent: Int
    let secondaryPercent: Int
    let limitReached: Bool
    let isLoading: Bool
    let worstPercent: Int
}

struct MenuBarIconView: View {
    let usedPercent: Int
    let secondaryPercent: Int
    let limitReached: Bool
    let isLoading: Bool
    /// Worst metric for the currently displayed service — drives ring colour.
    let worstPercent: Int

    init(
        usedPercent: Int,
        secondaryPercent: Int,
        limitReached: Bool,
        isLoading: Bool,
        worstPercent: Int
    ) {
        self.usedPercent = usedPercent
        self.secondaryPercent = secondaryPercent
        self.limitReached = limitReached
        self.isLoading = isLoading
        self.worstPercent = worstPercent
    }

    init(input: MenuBarGaugeInput) {
        self.init(
            usedPercent: input.usedPercent,
            secondaryPercent: input.secondaryPercent,
            limitReached: input.limitReached,
            isLoading: input.isLoading,
            worstPercent: input.worstPercent
        )
    }

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

struct DoubleMenuBarIconView: View {
    let left: MenuBarGaugeInput
    let right: MenuBarGaugeInput

    private let gaugeSize: CGFloat = 22
    private let spacing: CGFloat = 5

    var body: some View {
        Image(nsImage: combinedImage())
            .interpolation(.high)
            .antialiased(true)
            .frame(width: gaugeSize * 2 + spacing, height: gaugeSize)
    }

    private func combinedImage() -> NSImage {
        let totalWidth = gaugeSize * 2 + spacing
        let image = NSImage(size: NSSize(width: totalWidth, height: gaugeSize))
        image.lockFocusFlipped(false)

        gaugeImage(for: left).draw(
            in: NSRect(x: 0, y: 0, width: gaugeSize, height: gaugeSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )

        gaugeImage(for: right).draw(
            in: NSRect(x: gaugeSize + spacing, y: 0, width: gaugeSize, height: gaugeSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )

        image.unlockFocus()
        return image
    }

    private func gaugeImage(for input: MenuBarGaugeInput) -> NSImage {
        GaugeImageMaker.image(
            primaryPercent: input.usedPercent,
            secondaryPercent: input.secondaryPercent,
            limitReached: input.limitReached,
            isLoading: input.isLoading,
            size: gaugeSize,
            worstPercent: input.worstPercent
        )
    }
}

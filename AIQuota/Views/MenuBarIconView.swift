import SwiftUI
import AppKit
import AIQuotaKit

struct MenuBarGaugeInput {
    let usedPercent: Int
    let secondaryPercent: Int
    let limitReached: Bool
    let isLoading: Bool
    let worstPercent: Int
    var showsSecondaryMetric: Bool = true
}

struct MenuBarIconView: View {
    let usedPercent: Int
    let secondaryPercent: Int
    let limitReached: Bool
    let isLoading: Bool
    /// Worst metric for the currently displayed service — drives ring colour.
    let worstPercent: Int
    let showsSecondaryMetric: Bool
    let showsUpdateBadge: Bool

    init(
        usedPercent: Int,
        secondaryPercent: Int,
        limitReached: Bool,
        isLoading: Bool,
        worstPercent: Int,
        showsUpdateBadge: Bool = false,
        showsSecondaryMetric: Bool = true
    ) {
        self.usedPercent = usedPercent
        self.secondaryPercent = secondaryPercent
        self.limitReached = limitReached
        self.isLoading = isLoading
        self.worstPercent = worstPercent
        self.showsSecondaryMetric = showsSecondaryMetric
        self.showsUpdateBadge = showsUpdateBadge
    }

    init(input: MenuBarGaugeInput, showsUpdateBadge: Bool = false) {
        self.init(
            usedPercent: input.usedPercent,
            secondaryPercent: input.secondaryPercent,
            limitReached: input.limitReached,
            isLoading: input.isLoading,
            worstPercent: input.worstPercent,
            showsUpdateBadge: showsUpdateBadge,
            showsSecondaryMetric: input.showsSecondaryMetric
        )
    }

    var body: some View {
        Image(nsImage: renderedImage())
        .interpolation(.high)
        .antialiased(true)
        .frame(width: 22, height: 22)
    }

    private func renderedImage() -> NSImage {
        let image = GaugeImageMaker.image(
            primaryPercent: usedPercent,
            secondaryPercent: secondaryPercent,
            limitReached: limitReached,
            isLoading: isLoading,
            size: 22,
            worstPercent: worstPercent,
            showsSecondaryMetric: showsSecondaryMetric
        )
        if showsUpdateBadge { MenuBarUpdateBadge.draw(in: image) }
        return image
    }
}

struct DoubleMenuBarIconView: View {
    let left: MenuBarGaugeInput
    let right: MenuBarGaugeInput
    let showsUpdateBadge: Bool

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
        if showsUpdateBadge { MenuBarUpdateBadge.draw(in: image) }
        return image
    }

    private func gaugeImage(for input: MenuBarGaugeInput) -> NSImage {
        GaugeImageMaker.image(
            primaryPercent: input.usedPercent,
            secondaryPercent: input.secondaryPercent,
            limitReached: input.limitReached,
            isLoading: input.isLoading,
            size: gaugeSize,
            worstPercent: input.worstPercent,
            showsSecondaryMetric: input.showsSecondaryMetric
        )
    }
}

private enum MenuBarUpdateBadge {
    static func draw(in image: NSImage) {
        let diameter: CGFloat = 6
        let inset: CGFloat = 1
        let rect = NSRect(
            x: image.size.width - diameter - inset,
            y: image.size.height - diameter - inset,
            width: diameter,
            height: diameter
        )
        image.lockFocus()
        let dot = NSBezierPath(ovalIn: rect)
        NSColor.systemOrange.setFill()
        dot.fill()
        image.unlockFocus()
    }
}

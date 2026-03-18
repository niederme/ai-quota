import SwiftUI
import AppKit
import CoreGraphics
import AIQuotaKit

struct MenuBarIconView: View {
    let usage: CodexUsage?
    let isLoading: Bool
    let showPercent: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: gaugeImage)
                .interpolation(.high)
                .antialiased(true)
                .frame(width: 22, height: 22)

            if showPercent, let u = usage {
                Text("\(u.weeklyRemaining)%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .contentTransition(.numericText())
            }
        }
    }

    // MARK: - Gauge NSImage (lockFocusFlipped = y-up, same coords as icon generator)

    private var gaugeImage: NSImage {
        let ptSize: CGFloat = 22
        let img = NSImage(size: NSSize(width: ptSize, height: ptSize))
        img.lockFocusFlipped(false)             // y-up, origin bottom-left

        guard let ctx = NSGraphicsContext.current?.cgContext else {
            img.unlockFocus(); return img
        }

        // AppKit scales to backing resolution automatically — draw in points
        let s  = ptSize
        let cx = s / 2, cy = s / 2
        let r  = s * 0.41
        let lw = s * 0.14   // bolder stroke for visual weight at menu bar scale

        ctx.setLineCap(.round)

        // ── Track: 225° → 315° clockwise (y-up) = 270° arc over the top ──
        ctx.setLineWidth(lw)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.35))
        ctx.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                   startAngle: deg(225), endAngle: deg(315), clockwise: true)
        ctx.strokePath()

        // ── Fill ───────────────────────────────────────────────────────────
        let pct: Double
        if isLoading          { pct = 0.5 }
        else if let u = usage { pct = Double(u.weeklyUsedPercent) / 100.0 }
        else                  { pct = 0 }

        if pct > 0 {
            let fillEndDeg = 225.0 - pct * 270.0
            let fillEndA   = deg(fillEndDeg)

            let remaining = usage?.weeklyRemaining ?? 100
            let fillColor: CGColor
            if (usage?.limitReached ?? false) || remaining < 5 {
                fillColor = CGColor(red: 1.0, green: 0.25, blue: 0.25, alpha: 1)   // red
            } else if remaining <= 15 {
                fillColor = CGColor(red: 1.0, green: 0.65, blue: 0.0,  alpha: 1)   // amber
            } else {
                fillColor = CGColor(red: 0.62, green: 0.22, blue: 0.93, alpha: 1)  // purple
            }
            ctx.setStrokeColor(fillColor)
            ctx.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                       startAngle: deg(225), endAngle: fillEndA, clockwise: true)
            ctx.strokePath()

            // Needle dot
            let tx = cx + r * CoreGraphics.cos(fillEndA)
            let ty = cy + r * CoreGraphics.sin(fillEndA)
            let dr = lw * 0.55
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
            ctx.addEllipse(in: CGRect(x: tx - dr, y: ty - dr, width: dr * 2, height: dr * 2))
            ctx.fillPath()
        }

        // ── Sparkle ────────────────────────────────────────────────────────
        let ss = s * 0.17
        let sparkPath = CGMutablePath()
        for i in 0..<4 {
            let oa = CGFloat(i) * (.pi / 2) + (.pi / 2)
            let ia = oa + .pi / 4
            let op = CGPoint(x: cx + ss        * CoreGraphics.cos(oa),
                             y: cy + ss        * CoreGraphics.sin(oa))
            let ip = CGPoint(x: cx + ss * 0.22 * CoreGraphics.cos(ia),
                             y: cy + ss * 0.22 * CoreGraphics.sin(ia))
            if i == 0 { sparkPath.move(to: op) } else { sparkPath.addLine(to: op) }
            sparkPath.addLine(to: ip)
        }
        sparkPath.closeSubpath()
        ctx.addPath(sparkPath)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
        ctx.fillPath()

        img.unlockFocus()
        return img
    }

    private func deg(_ d: Double) -> CGFloat { CGFloat(d * .pi / 180) }
}

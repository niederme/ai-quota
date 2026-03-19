#if canImport(AppKit)
import AppKit
import CoreGraphics

/// Shared arc-gauge image renderer used by both the main app menu bar icon and the widget.
public enum GaugeImageMaker {

    /// Renders a dual-arc gauge into an `NSImage` of the given point size.
    /// - Parameters:
    ///   - primaryPercent: 0–100, short window (5h) consumption.
    ///   - secondaryPercent: 0–100, long window (7-day) consumption.
    ///   - limitReached: whether the primary (5h) cap is fully hit.
    ///   - isLoading: show a neutral half-fill while data is in flight.
    ///   - size: point size of the square image (rendered at backing scale).
    public static func image(
        primaryPercent: Int,
        secondaryPercent: Int,
        limitReached: Bool,
        isLoading: Bool,
        size: CGFloat
    ) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocusFlipped(false)         // y-up, origin bottom-left

        guard let ctx = NSGraphicsContext.current?.cgContext else {
            img.unlockFocus()
            return img
        }

        let s  = size
        let cx = s / 2, cy = s / 2
        let lw = s * 0.12              // slightly thinner to fit two rings
        let r1 = s * 0.41              // outer ring (5h / primary)
        let r2 = r1 - lw              // inner ring (7-day / secondary), touching

        ctx.setLineCap(.round)
        ctx.setLineWidth(lw)

        // ── Tracks ─────────────────────────────────────────────────────────
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.2))
        ctx.addArc(center: CGPoint(x: cx, y: cy), radius: r1,
                   startAngle: deg(225), endAngle: deg(315), clockwise: true)
        ctx.strokePath()

        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.12))
        ctx.addArc(center: CGPoint(x: cx, y: cy), radius: r2,
                   startAngle: deg(225), endAngle: deg(315), clockwise: true)
        ctx.strokePath()

        // ── Outer fill: primary (5h) ───────────────────────────────────────
        let pct1: Double = isLoading ? 0.5 : Double(primaryPercent) / 100.0
        if pct1 > 0 {
            let fillEnd1 = deg(225.0 - pct1 * 270.0)
            let color1 = ringColor(pct: pct1, limitReached: limitReached)
            ctx.setStrokeColor(color1)
            ctx.addArc(center: CGPoint(x: cx, y: cy), radius: r1,
                       startAngle: deg(225), endAngle: fillEnd1, clockwise: true)
            ctx.strokePath()

            // Needle dot — anchors the fill tip so a near-full arc still reads as a gauge
            let tx = cx + r1 * cos(fillEnd1)
            let ty = cy + r1 * sin(fillEnd1)
            let dr = lw * 0.5
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
            ctx.addEllipse(in: CGRect(x: tx - dr, y: ty - dr, width: dr * 2, height: dr * 2))
            ctx.fillPath()
        }

        // ── Inner fill: secondary (7-day) ─────────────────────────────────
        // Dimmed at 45% opacity when healthy — only brightens to amber/red
        // when the 7-day window itself is approaching the limit.
        let pct2: Double = isLoading ? 0.5 : Double(secondaryPercent) / 100.0
        if pct2 > 0 {
            let remaining2 = 1.0 - pct2
            let isWarning2 = remaining2 <= 0.20   // amber/red territory
            let alpha2: CGFloat = isWarning2 ? 1.0 : 0.45
            let base2 = ringColor(pct: pct2, limitReached: pct2 >= 1.0)
            ctx.setStrokeColor(base2.copy(alpha: alpha2) ?? base2)
            ctx.addArc(center: CGPoint(x: cx, y: cy), radius: r2,
                       startAngle: deg(225), endAngle: deg(225.0 - pct2 * 270.0), clockwise: true)
            ctx.strokePath()
        }

        // ── Sparkle ────────────────────────────────────────────────────────
        let ss = s * 0.14
        let sparkPath = CGMutablePath()
        for i in 0..<4 {
            let oa = CGFloat(i) * (.pi / 2) + (.pi / 2)
            let ia = oa + .pi / 4
            let op = CGPoint(x: cx + ss        * cos(oa), y: cy + ss        * sin(oa))
            let ip = CGPoint(x: cx + ss * 0.22 * cos(ia), y: cy + ss * 0.22 * sin(ia))
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

    /// Color for an arc fill segment based on how much has been consumed.
    private static func ringColor(pct: Double, limitReached: Bool) -> CGColor {
        let remaining = 1.0 - pct
        if limitReached || remaining < 0.05 {
            return CGColor(red: 1.0, green: 0.25, blue: 0.25, alpha: 1)  // red
        } else if remaining <= 0.15 {
            return CGColor(red: 1.0, green: 0.65, blue: 0.0,  alpha: 1)  // amber
        } else {
            return CGColor(red: 1.0, green: 1.0, blue: 1.0,  alpha: 1)   // white
        }
    }

    private static func deg(_ d: Double) -> CGFloat { CGFloat(d * .pi / 180) }
}
#endif

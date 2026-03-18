#if canImport(AppKit)
import AppKit
import CoreGraphics

/// Shared arc-gauge image renderer used by both the main app menu bar icon and the widget.
public enum GaugeImageMaker {

    /// Renders the arc gauge into an `NSImage` of the given point size.
    /// - Parameters:
    ///   - usedPercent: 0–100, how much of the quota has been consumed.
    ///   - limitReached: whether the weekly cap is fully hit.
    ///   - isLoading: show a neutral half-fill while data is in flight.
    ///   - size: point size of the square image (rendered at backing scale).
    public static func image(
        usedPercent: Int,
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
        let r  = s * 0.41
        let lw = s * 0.14

        ctx.setLineCap(.round)

        // ── Track: 225° → 315° clockwise (y-up) = 270° arc over the top ──
        ctx.setLineWidth(lw)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.35))
        ctx.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                   startAngle: deg(225), endAngle: deg(315), clockwise: true)
        ctx.strokePath()

        // ── Fill ───────────────────────────────────────────────────────────
        let pct: Double
        if isLoading { pct = 0.5 }
        else         { pct = Double(usedPercent) / 100.0 }

        let remaining = 100 - usedPercent

        if pct > 0 {
            let fillEndA = deg(225.0 - pct * 270.0)

            let fillColor: CGColor
            if limitReached || remaining < 5 {
                fillColor = CGColor(red: 1.0, green: 0.25, blue: 0.25, alpha: 1)  // red
            } else if remaining <= 15 {
                fillColor = CGColor(red: 1.0, green: 0.65, blue: 0.0,  alpha: 1)  // amber
            } else {
                fillColor = CGColor(red: 1.0, green: 1.0, blue: 1.0,  alpha: 1)  // white
            }

            ctx.setStrokeColor(fillColor)
            ctx.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                       startAngle: deg(225), endAngle: fillEndA, clockwise: true)
            ctx.strokePath()

            // Needle dot
            let tx = cx + r * cos(fillEndA)
            let ty = cy + r * sin(fillEndA)
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

    private static func deg(_ d: Double) -> CGFloat { CGFloat(d * .pi / 180) }
}
#endif

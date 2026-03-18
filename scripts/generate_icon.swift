#!/usr/bin/env swift
// Run: swift scripts/generate_icon.swift
// Generates gauge+sparkle app icons into AIQuota/Resources/Assets.xcassets/AppIcon.appiconset/

import AppKit
import CoreGraphics

func rad(_ deg: Double) -> CGFloat { CGFloat(deg * .pi / 180) }
func cos(_ a: CGFloat) -> CGFloat { CoreGraphics.cos(a) }
func sin(_ a: CGFloat) -> CGFloat { CoreGraphics.sin(a) }

func drawIcon(size: Int) -> Data? {
    // Draw at exact pixel size using NSBitmapImageRep (avoids Retina @2x doubling)
    guard let bmp = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bmp)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(size)

    // ── Background ──────────────────────────────────────────────────────
    let corner = s * 0.225
    let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.addPath(bgPath)
    ctx.setFillColor(CGColor(red: 0.08, green: 0.07, blue: 0.15, alpha: 1))
    ctx.fillPath()
    ctx.addPath(bgPath)
    ctx.clip()

    // Subtle inner glow at top
    let glowColors = [CGColor(red:0.4,green:0.2,blue:0.8,alpha:0.18), CGColor(red:0,green:0,blue:0,alpha:0)] as CFArray
    let glowLocs: [CGFloat] = [0, 1]
    if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glowColors, locations: glowLocs) {
        ctx.drawRadialGradient(grad,
            startCenter: CGPoint(x: s*0.5, y: s*0.85), startRadius: 0,
            endCenter:   CGPoint(x: s*0.5, y: s*0.85), endRadius: s*0.7,
            options: [])
    }

    // ── Gauge ────────────────────────────────────────────────────────────
    let cx = s * 0.5
    let cy = s * 0.46
    let gr = s * 0.305          // gauge radius
    let lw = s * 0.072          // stroke width

    // Start = 225° (8 o'clock), End = 315° (4 o'clock), clockwise sweep = 270°
    let startA = rad(225)
    let endA   = rad(315)
    let fillPct: Double = 0.74
    let fillEndA = rad(225 - fillPct * 270)   // clockwise → subtract

    ctx.setLineCap(.round)

    // Track (dim)
    ctx.setLineWidth(lw)
    ctx.setStrokeColor(CGColor(red:1,green:1,blue:1,alpha:0.10))
    ctx.addArc(center: CGPoint(x:cx,y:cy), radius:gr, startAngle:startA, endAngle:endA, clockwise:true)
    ctx.strokePath()

    // Pre-glow (wide, behind fill)
    ctx.setLineWidth(lw * 1.7)
    ctx.setStrokeColor(CGColor(red:0.60,green:0.20,blue:0.95,alpha:0.22))
    ctx.addArc(center: CGPoint(x:cx,y:cy), radius:gr, startAngle:startA, endAngle:fillEndA, clockwise:true)
    ctx.strokePath()

    // Fill (solid purple)
    ctx.setLineWidth(lw)
    ctx.setStrokeColor(CGColor(red:0.62,green:0.22,blue:0.93,alpha:1))
    ctx.addArc(center: CGPoint(x:cx,y:cy), radius:gr, startAngle:startA, endAngle:fillEndA, clockwise:true)
    ctx.strokePath()

    // Needle dot at fill tip
    let nx = cx + gr * cos(fillEndA)
    let ny = cy + gr * sin(fillEndA)
    let dr = lw * 0.72
    ctx.setFillColor(CGColor(red:1,green:1,blue:1,alpha:0.95))
    ctx.addEllipse(in: CGRect(x:nx-dr, y:ny-dr, width:dr*2, height:dr*2))
    ctx.fillPath()

    // ── Sparkle ──────────────────────────────────────────────────────────
    // Place sparkle center inside the arc, slightly upper-right
    let sx = cx                  // centered on gauge
    let sy = cy                  // centered on gauge
    let ss = s * 0.13

    func drawSparkle(x: CGFloat, y: CGFloat, sz: CGFloat, alpha: CGFloat = 1) {
        let path = CGMutablePath()
        let outer = sz
        let inner = sz * 0.16
        for i in 0..<4 {
            let oa = CGFloat(i) * (.pi / 2) + (.pi / 2)  // first point up
            let ia = oa + .pi / 4
            let op = CGPoint(x: x + outer * cos(oa), y: y + outer * sin(oa))
            let ip = CGPoint(x: x + inner * cos(ia), y: y + inner * sin(ia))
            if i == 0 { path.move(to: op) } else { path.addLine(to: op) }
            path.addLine(to: ip)
        }
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setFillColor(CGColor(red:1,green:1,blue:1,alpha:alpha))
        ctx.fillPath()
    }

    drawSparkle(x: sx, y: sy, sz: ss)

    // Smaller accent sparkles (only at larger sizes)
    if s >= 64 {
        drawSparkle(x: sx - ss*1.15, y: sy + ss*0.55, sz: ss*0.35, alpha: 0.55)
        drawSparkle(x: sx + ss*1.05, y: sy + ss*0.45, sz: ss*0.25, alpha: 0.40)
    }

    NSGraphicsContext.restoreGraphicsState()
    return bmp.representation(using: .png, properties: [:])
}

// ── Output ───────────────────────────────────────────────────────────────
let outDir = "./AIQuota/Resources/Assets.xcassets/AppIcon.appiconset"
let sizes: [(String, Int)] = [
    ("16", 16), ("32", 32), ("64", 64),
    ("128", 128), ("256", 256), ("512", 512), ("1024", 1024)
]

for (name, sz) in sizes {
    let url = URL(fileURLWithPath: "\(outDir)/icon_\(name).png")
    guard let png = drawIcon(size: sz) else { print("✗ \(name)"); continue }
    try! png.write(to: url)
    print("✓ icon_\(name).png (\(sz)×\(sz))")
}
print("Done → \(outDir)")

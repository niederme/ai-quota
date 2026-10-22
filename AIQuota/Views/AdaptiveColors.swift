import SwiftUI

extension Color {
    static let brand = Color("BrandAccent")
    static let gaugeAccent = Color(nsColor: .systemPurple)
    static let warningAmber = Color(nsColor: .systemOrange)
    static let critical = Color(nsColor: .systemRed)
    /// Small text on the translucent sheet. Purple drops below 4.5:1 once the
    /// desktop shows through, so captions go near-white (dark) or deep plum (light)
    /// and colour stays on the rings.
    static let gaugeAccentInk = Color(light: (0x5c, 0x16, 0x88, 1), dark: (0xea, 0xd2, 0xff, 1))

    // Tinted glass sheet (see prototypes/sheet-material)
    static let sheetTint = Color(light: (246, 241, 251, 0.58), dark: (26, 21, 36, 0.45))
    static let sheetGlow = Color(light: (191, 120, 242, 0.34), dark: (150, 86, 214, 0.40))
    static let sheetGlowTrailing = Color(light: (175, 82, 222, 0.10), dark: (110, 60, 170, 0.18))
    static let sheetRim = Color(light: (255, 255, 255, 1), dark: (255, 255, 255, 0.55))

    private init(light: (Int, Int, Int, Double), dark: (Int, Int, Int, Double)) {
        let light = NSColor(srgbRed: CGFloat(light.0) / 255, green: CGFloat(light.1) / 255,
                            blue: CGFloat(light.2) / 255, alpha: light.3)
        let dark = NSColor(srgbRed: CGFloat(dark.0) / 255, green: CGFloat(dark.1) / 255,
                           blue: CGFloat(dark.2) / 255, alpha: dark.3)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

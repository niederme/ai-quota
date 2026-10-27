import SwiftUI

extension Color {
    static let brand = Color("BrandAccent")
    /// Rings and dial readouts. systemPurple is too pale on the light glass sheet
    /// (2.9:1), so light mode uses a deeper purple and dark mode a slightly lifted one.
    static let gaugeAccent = Color(light: (0x85, 0x30, 0xbd, 1), dark: (0xc8, 0x6c, 0xf5, 1))
    static let warningAmber = Color(nsColor: .systemOrange)
    static let critical = Color(nsColor: .systemRed)
    /// Small text on the translucent sheet. Purple drops below 4.5:1 once the
    /// desktop shows through, so captions go near-white (dark) or deep plum (light)
    /// and colour stays on the rings.
    static let gaugeAccentInk = Color(light: (0x5c, 0x16, 0x88, 1), dark: (0xea, 0xd2, 0xff, 1))

    // The Mac account list uses the accepted iOS overview's semantic colors.
    // Keep the values aligned with iOS/App/Assets.xcassets/Overview*.colorset.
    static let overviewAccent = Color(light: (0xaf, 0x52, 0xde, 1), dark: (0xbf, 0x5a, 0xf2, 1))
    static let overviewResetAccent = Color(light: (0x7a, 0x24, 0xa6, 1), dark: (0xd7, 0x7e, 0xf7, 1))
    static let overviewPrimary = Color(light: (0x0b, 0x06, 0x0f, 1), dark: (0xff, 0xff, 0xff, 1))
    static let overviewSecondary = Color(light: (0x3c, 0x3c, 0x43, 0.62), dark: (0xeb, 0xeb, 0xf5, 0.62))
    static let overviewTertiary = Color(light: (0x3c, 0x3c, 0x43, 0.32), dark: (0xeb, 0xeb, 0xf5, 0.32))
    static let overviewWarning = Color(light: (0xff, 0x95, 0x00, 1), dark: (0xff, 0x9f, 0x0a, 1))
    static let overviewCritical = Color(light: (0xff, 0x3b, 0x30, 1), dark: (0xff, 0x45, 0x3a, 1))

    // Keep the underlying sheet visible without washing its purple toward gray.
    static let overviewGlass = overviewAccent.opacity(0.06)
    static let overviewGlassHighlight = overviewAccent.opacity(0.10)
    static let overviewTrack = Color(light: (0, 0, 0, 0.10), dark: (255, 255, 255, 0.10))

    // Tinted glass sheet (see prototypes/sheet-material)
    static let sheetTint = Color(light: (246, 241, 251, 0.66), dark: (26, 21, 36, 0.53))
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

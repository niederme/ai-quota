import SwiftUI

extension Color {
    static let brand = Color("BrandAccent")
    static let gaugeAccent = Color(nsColor: .systemPurple)
    static let warningAmber = Color(nsColor: .systemOrange)
    static let critical = Color(nsColor: .systemRed)
    /// Small purple text on the tinted sheet. systemPurple drops below 4.5:1
    /// there at caption size, so captions use the deeper/lighter reset ink.
    static let gaugeAccentInk = Color(light: (0x7a, 0x24, 0xa6, 1), dark: (0xd7, 0x7e, 0xf7, 1))

    // Tinted glass sheet (see prototypes/sheet-material)
    static let sheetTint = Color(light: (246, 241, 251, 0.9), dark: (26, 21, 36, 0.9))
    static let sheetGlow = Color(light: (191, 120, 242, 0.34), dark: (150, 86, 214, 0.40))
    static let sheetGlowTrailing = Color(light: (175, 82, 222, 0.10), dark: (110, 60, 170, 0.18))

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

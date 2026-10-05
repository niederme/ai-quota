#if canImport(AppKit)
import AppKit
import Testing
@testable import AIQuotaKit

@Suite("Compact gauge rendering")
struct CompactGaugeRenderingTests {
    @MainActor private func bitmap(secondary: Bool, loading: Bool = false) throws -> NSBitmapImageRep {
        let image = GaugeImageMaker.image(primaryPercent: 56, secondaryPercent: 100,
            limitReached: false, isLoading: loading, size: 100, showsSecondaryMetric: secondary)
        let data = try #require(image.tiffRepresentation)
        return try #require(NSBitmapImageRep(data: data))
    }
    @MainActor private func sample(_ bitmap: NSBitmapImageRep, x: Double, y: Double) throws -> NSColor {
        try #require(bitmap.colorAt(x: Int(Double(bitmap.pixelsWide) * x), y: Int(Double(bitmap.pixelsHigh) * y))?.usingColorSpace(.deviceRGB))
    }
    @Test @MainActor func singleOmitsInnerTrackAndHiddenSecondaryStatus() throws {
        let single = try bitmap(secondary: false)
        let dual = try bitmap(secondary: true)
        #expect(try sample(single, x: 0.5, y: 0.21).alphaComponent < 0.01)
        #expect(try sample(dual, x: 0.5, y: 0.21).alphaComponent > 0.1)
        let outer = try sample(single, x: 0.5, y: 0.09)
        #expect(abs(outer.redComponent - outer.blueComponent) < 0.01)
        #expect(outer.alphaComponent > 0.9)
    }
    @Test @MainActor func refreshingRetainsKnownRingImage() throws {
        let current = try bitmap(secondary: false)
        let loading = try bitmap(secondary: false, loading: true)
        #expect(current.representation(using: .png, properties: [:]) == loading.representation(using: .png, properties: [:]))
    }
}
#endif

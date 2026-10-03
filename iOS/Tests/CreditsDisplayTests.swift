import XCTest
import SwiftUI
import MobileAccessCore
@testable import AIQuota_iOS

final class CreditsDisplayTests: XCTestCase {
    @MainActor func testZeroAndMissingSpendOmitRowWithoutSpacing() throws {
        for name in ["Codex", "Claude"] {
            for (size, width) in [(DynamicTypeSize.large, CGFloat(280)), (.large, 360), (.accessibility3, 280)] {
                func render(_ spent: Double?, currency: String? = "USD") throws -> UIImage {
                    let weekly = try JSONDecoder().decode(QuotaWindow.self,
                        from: Data(#"{"usedPercent":4,"durationSeconds":604800}"#.utf8))
                    let reading = QuotaReading(fetchedAt: Date(timeIntervalSince1970: 0), shortTerm: nil, weekly: weekly,
                        metadata: AccountMetadata(plan: "Pro", balanceUSD: 25, usageSpent: spent, usageCurrency: currency))
                    let content = ProviderDialCardContent(name: name,
                        icon: name == "Codex" ? "logo-openai" : "logo-claude", availableWidth: width,
                        reading: reading, connected: true, busy: false, error: nil)
                        .frame(width: width).environment(\.dynamicTypeSize, size).environment(\.colorScheme, .dark)
                    let renderer = ImageRenderer(content: content)
                    renderer.scale = 2
                    return try XCTUnwrap(renderer.uiImage)
                }
                let missing = try render(nil)
                let zero = try render(0)
                let positive = try render(12.40)
                let providerUnits = try render(12.40, currency: nil)
                XCTAssertEqual(zero.pngData(), missing.pngData(), "\(name): zero must leave no row or spacing")
                XCTAssertNotEqual(positive.pngData(), zero.pngData())
                XCTAssertNotEqual(providerUnits.pngData(), zero.pngData())
                if width == 280 {
                    XCTAssertGreaterThan(positive.size.height, zero.size.height)
                    XCTAssertGreaterThan(providerUnits.size.height, zero.size.height)
                }
                for (label, image) in [("zero", zero), ("positive", positive)] {
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "credits-\(name)-\(size)-\(Int(width))-\(label)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                    try image.pngData()?.write(to: URL(fileURLWithPath: "/tmp/credits-\(name)-\(size)-\(Int(width))-\(label).png"))
                }
            }
        }
    }
}

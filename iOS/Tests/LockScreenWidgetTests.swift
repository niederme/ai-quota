import XCTest
import SwiftUI
import MobileAccessCore
@testable import AIQuota_iOS

@MainActor final class LockScreenWidgetTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1791158400)
    private func reading(reset: Date?, dual: Bool = false, fetchedAt: Date? = nil) throws -> QuotaReading {
        let window: [String: Any] = ["usedPercent": 28, "durationSeconds": 604800,
                                    "resetsAt": reset.map { $0.timeIntervalSinceReferenceDate } ?? NSNull()]
        var object: [String: Any] = ["fetchedAt": (fetchedAt ?? now).timeIntervalSinceReferenceDate, "weekly": window]
        if dual { object["shortTerm"] = ["usedPercent": 12, "durationSeconds": 18000] }
        return try JSONDecoder().decode(QuotaReading.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func testResetUsesAccountShapeAndHidesUnavailableOrStaleEvidence() throws {
        let reset = now.addingTimeInterval(86400)
        let single = try reading(reset: reset)
        XCTAssertNotNil(LockScreenResetPresentation.make(reading: single, needsApp: false, at: now))
        for value in [nil, try reading(reset: nil), try reading(reset: now), try reading(reset: now.addingTimeInterval(-1)),
                      try reading(reset: reset, dual: true), try reading(reset: reset, fetchedAt: now.addingTimeInterval(1)),
                      try reading(reset: reset, fetchedAt: now.addingTimeInterval(-1800)), try reading(reset: Date(timeIntervalSince1970: 1e300))] {
            XCTAssertNil(LockScreenResetPresentation.make(reading: value, needsApp: false, at: now))
        }
        XCTAssertNil(LockScreenResetPresentation.make(reading: single, needsApp: true, at: now))
        XCTAssertNotNil(LockScreenResetPresentation.make(reading: single, needsApp: false, at: now.addingTimeInterval(1799)))
        XCTAssertNil(LockScreenResetPresentation.make(reading: single, needsApp: false, at: now.addingTimeInterval(1800)))
        let soon = try reading(reset: now.addingTimeInterval(60))
        XCTAssertNil(LockScreenResetPresentation.make(reading: soon, needsApp: false, at: now.addingTimeInterval(60)))
    }
    func testThreeLetterCopyUsesLocalTimeAndFullSpokenDateAcrossDST() throws {
        var utc = Calendar(identifier: .gregorian); utc.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var ny = utc; ny.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let reset = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-07T14:44:00Z"))
        let value = try reading(reset: reset)
        let local = try XCTUnwrap(LockScreenResetPresentation.make(reading: value, needsApp: false, at: now, calendar: ny, locale: Locale(identifier: "en_US")))
        XCTAssertEqual(local.text, "Wed 10:44 AM")
        XCTAssertTrue(local.accessibilityText.contains("Wednesday"))
        XCTAssertTrue(local.accessibilityText.contains("2026"))
        XCTAssertEqual(LockScreenResetPresentation.make(reading: value, needsApp: false, at: now, calendar: utc)?.text, "Wed 2:44 PM")
        for stamp in ["2026-11-01T05:30:00Z", "2026-11-01T06:30:00Z"] {
            let end = try XCTUnwrap(ISO8601DateFormatter().date(from: stamp))
            let start = end.addingTimeInterval(-60)
            XCTAssertEqual(LockScreenResetPresentation.make(reading: try reading(reset: end, fetchedAt: start), needsApp: false, at: start, calendar: ny)?.text, "Sun 1:30 AM")
        }
    }
    func testLargestThreeLetterTimeFitsWithoutScaling() {
        let font = UIFont.monospacedDigitSystemFont(ofSize: 16, weight: .regular)
        let combinedFont = UIFont.systemFont(ofSize: 11, weight: .medium)
        for day in ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"] {
            for hour in 1...12 { for minute in 0...59 { for period in ["AM", "PM"] {
                let text = "\(day) \(hour):" + String(format: "%02d", minute) + " " + period
                XCTAssertLessThanOrEqual((text as NSString).size(withAttributes: [.font: font]).width, 112, text)
                XCTAssertLessThanOrEqual((text as NSString).size(withAttributes: [.font: combinedFont]).width, 79, text)
            } } }
        }
    }
    func testCombinedAllowanceDetailsRendersAtNativeSize() throws {
        for dual in [false, true] { for dark in [false, true] {
            let sample = try reading(reset: now.addingTimeInterval(86400), dual: dual)
            let view = HStack(spacing: 2) {
                ForEach(QuotaService.allCases, id: \.self) { service in
                    CompactQuotaView(service: service, reading: sample, needsApp: false, date: self.now, compact: true)
                }
            }.frame(width: 160, height: 72).background(Color(uiColor: .systemGroupedBackground))
                .environment(\.colorScheme, dark ? .dark : .light)
            let renderer = ImageRenderer(content: view); renderer.scale = 3
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size, CGSize(width: 160, height: 72))
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("combined-lock-\(dual ? "dual" : "single")-\(dark ? "dark" : "light").png")
            try image.pngData()?.write(to: path); print("WIDGET_REVIEW " + path.path)
            let attachment = XCTAttachment(image: image); attachment.lifetime = .keepAlways; add(attachment)
        } }
        var utc = Calendar(identifier: .gregorian); utc.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        XCTAssertEqual(LockScreenResetPresentation.make(reading: try reading(reset: now.addingTimeInterval(86400)), needsApp: false, at: now, calendar: utc)?.text, "Tue 12:00 AM")
    }
    func testRestoredAccessoryGaugeAndResetFitAtNativeSize() throws {
        // A 44pt dial frame plus 4pt gap leaves 112pt for full-size 16pt reset copy.
        // Its inset visible ring stays subordinate to the three text rows.
        let sample = try reading(reset: now.addingTimeInterval(86400))
        let account = WidgetAccountContent(id: "codex:work", value: .init(service: .codex, reading: sample, needsApp: false), label: "Account With A Long Name")
        for showName in [false, true] {
            let view = AccountLockView(account: account, date: now, showAccountNames: showName)
                .frame(width: 160, height: 72).foregroundStyle(.white).background(Color.black)
            let renderer = ImageRenderer(content: view); renderer.scale = 3
            let image = try XCTUnwrap(renderer.uiImage)
            let attachment = XCTAttachment(image: image)
            attachment.name = "restored-rectangular-account-names-\(showName)"; attachment.lifetime = .keepAlways; add(attachment)
            let cg = try XCTUnwrap(image.cgImage)
            var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
            let context = try XCTUnwrap(CGContext(data: &pixels, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            var minX = 132, maxX = 0
            for y in 0..<cg.height { for x in 0..<132 {
                if pixels[(y * cg.width + x) * 4] > 20 { minX = min(minX, x); maxX = max(maxX, x) }
            } }
            let gaugeWidth = Double(maxX - minX + 1) / 3
            XCTAssertGreaterThan(gaugeWidth, 35)
            XCTAssertLessThan(gaugeWidth, 38, "Home dial geometry must not leak into the rectangular accessory")
        }
    }

    func testAccessoryTextSpacingWithNamesAndWindows() throws {
        for weight in [UIFont.Weight.regular, .medium] {
            let font = UIFont.systemFont(ofSize: 16, weight: weight)
            print("ACCESSORY_FONT \(weight): lineHeight=\(font.lineHeight), ascender=\(font.ascender), descender=\(font.descender), capHeight=\(font.capHeight)")
        }
        for service in QuotaService.allCases { for dual in [false, true] { for showName in [false, true] {
            let sample = try reading(reset: now.addingTimeInterval(86400), dual: dual)
            let account = WidgetAccountContent(id: "\(service.rawValue):work", value: .init(service: service, reading: sample, needsApp: false), label: "Account With A Long Name")
            let view = AccountLockView(account: account, date: now, showAccountNames: showName)
                .frame(width: 160, height: 72).foregroundStyle(.white).background(Color.black)
            let renderer = ImageRenderer(content: view); renderer.scale = 3
            let image = try XCTUnwrap(renderer.uiImage)
            let attachment = XCTAttachment(image: image)
            attachment.name = "spacing-\(service)-dual-\(dual)-names-\(showName)"; attachment.lifetime = .keepAlways; add(attachment)
            let cg = try XCTUnwrap(image.cgImage)
            var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
            let context = try XCTUnwrap(CGContext(data: &pixels, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            var bands: [ClosedRange<Int>] = []
            for y in 0..<cg.height {
                let hasInk = (144..<cg.width).contains { pixels[(y * cg.width + $0) * 4] > 30 }
                if hasInk {
                    if let last = bands.last, last.upperBound == y - 1 { bands[bands.count - 1] = last.lowerBound...y }
                    else { bands.append(y...y) }
                }
            }
            print("ACCESSORY_INK \(service) dual=\(dual) names=\(showName): \(bands)")
            XCTAssertEqual(bands.count, 3)
            var dialTop = cg.height, dialBottom = 0
            for y in 0..<cg.height { for x in 0..<132 {
                if pixels[(y * cg.width + x) * 4] > 20 {
                    dialTop = min(dialTop, y); dialBottom = max(dialBottom, y)
                }
            } }
            if bands.count == 3 {
                let textCentre = Double(bands[0].lowerBound + bands[2].upperBound) / 6
                let dialCentre = Double(dialTop + dialBottom) / 6
                print("ACCESSORY_CENTRES \(service) dual=\(dual) names=\(showName): text=\(textCentre), dial=\(dialCentre)")
                XCTAssertEqual(textCentre, dialCentre, accuracy: 0.75, "Text must align with the visible dial, not its empty lower quadrant")
                let firstGap = bands[1].lowerBound - bands[0].upperBound - 1
                let lastGap = bands[2].lowerBound - bands[1].upperBound - 1
                XCTAssertEqual(lastGap, firstGap, accuracy: 1, "\(service), dual=\(dual), names=\(showName): last line has extra optical spacing")
            }
        } } }
    }

    func testProductionViewStateMatrixRenders() throws {
        let samples: [(String, QuotaReading?, Bool)] = [
            ("single", try reading(reset: now.addingTimeInterval(86400)), false),
            ("dual", try reading(reset: now.addingTimeInterval(86400), dual: true), false),
            ("missing", try reading(reset: nil), false), ("loading", nil, false),
            ("stale", try reading(reset: now.addingTimeInterval(86400), fetchedAt: now.addingTimeInterval(-1800)), false),
            ("reconnect", try reading(reset: now.addingTimeInterval(86400)), true)]
        for service in QuotaService.allCases { for dark in [false, true] { for size in [DynamicTypeSize.large, .accessibility3] {
            for (name, reading, needsApp) in samples {
                let view = ServiceDetailsView(value: .init(service: service, reading: reading, needsApp: needsApp), date: now)
                    .frame(width: 160, height: 72).background(Color(uiColor: .systemGroupedBackground))
                    .environment(\.colorScheme, dark ? .dark : .light).environment(\.dynamicTypeSize, size)
                let renderer = ImageRenderer(content: view); renderer.scale = 3
                let image = try XCTUnwrap(renderer.uiImage)
                XCTAssertEqual(image.size, CGSize(width: 160, height: 72))
                if dark && size == .large {
                    let attachment = XCTAttachment(image: image); attachment.name = "production-lock-\(service)-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
                    let path = FileManager.default.temporaryDirectory.appendingPathComponent("production-lock-\(service)-\(name).png")
                    try image.pngData()?.write(to: path); print("WIDGET_REVIEW " + path.path)
                }
            }
        } } }
    }
}

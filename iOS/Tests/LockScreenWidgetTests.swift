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
        let font = UIFont.systemFont(ofSize: 14, weight: .medium)
        for day in ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"] {
            for hour in 1...12 { for minute in 0...59 { for period in ["AM", "PM"] {
                let text = "\(day) \(hour):" + String(format: "%02d", minute) + " " + period
                XCTAssertLessThanOrEqual((text as NSString).size(withAttributes: [.font: font]).width, 98, text)
            } } }
        }
    }
    func testCombinedAllowanceDetailsRendersAtNativeSize() throws {
        for dual in [false, true] { for dark in [false, true] {
            let sample = try reading(reset: now.addingTimeInterval(86400), dual: dual)
            let view = HStack(spacing: 4) {
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

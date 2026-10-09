import XCTest
import SwiftUI
import MobileAccessCore
@testable import AIQuota_iOS

@MainActor final class WidgetReadingStatusTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1791345600)
    private func reading(age: TimeInterval, dual: Bool = true) throws -> QuotaReading {
        var object: [String: Any] = ["fetchedAt": now.addingTimeInterval(-age).timeIntervalSinceReferenceDate,
            "weekly": ["usedPercent":44, "durationSeconds":604800, "resetsAt":now.addingTimeInterval(86400).timeIntervalSinceReferenceDate]]
        if dual { object["shortTerm"] = ["usedPercent":72,"durationSeconds":18000,"resetsAt":now.addingTimeInterval(3600).timeIntervalSinceReferenceDate] }
        return try JSONDecoder().decode(QuotaReading.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func testStatusUsesLastSuccessAndTreatsFreshFailuresAsSaved() throws {
        let fresh = try reading(age: 120)
        XCTAssertFalse(WidgetReadingStatus.isSaved(fresh, needsApp: false, updateFailed: false, at: now))
        XCTAssertTrue(WidgetReadingStatus.isSaved(fresh, needsApp: false, updateFailed: true, at: now))
        XCTAssertTrue(WidgetReadingStatus.isSaved(fresh, needsApp: true, updateFailed: false, at: now))
        XCTAssertTrue(WidgetReadingStatus.isSaved(try reading(age: 1800), needsApp: false, updateFailed: false, at: now))
        XCTAssertFalse(WidgetReadingStatus.isSaved(nil, needsApp: false, updateFailed: true, at: now))
        XCTAssertEqual(WidgetReadingStatus.savedLabel(fresh, at: now), "Saved · 2m ago")
        XCTAssertEqual(WidgetReadingStatus.savedLabel(try reading(age: 7200), at: now), "Saved · 2h ago")
        XCTAssertEqual(WidgetReadingStatus.savedLabel(try reading(age: 172800), at: now), "Saved · 2d ago")
        XCTAssertEqual(WidgetReadingStatus.savedLabel(try reading(age: -30), at: now), "Saved reading")
        XCTAssertEqual(fresh.fetchedAt, now.addingTimeInterval(-120))
    }
    func testNativeFreshStaleTemporaryFailureReconnectAndMissingViews() throws {
        let states: [(String, QuotaReading?, Bool, Bool)] = [
            ("fresh", try reading(age: 120), false, false), ("stale", try reading(age: 7200), false, false),
            ("failed", try reading(age: 120), false, true), ("reconnect", try reading(age: 120), true, true), ("missing", nil, false, true),
            ("single-fresh", try reading(age: 120, dual: false), false, false),
            ("single-failed", try reading(age: 120, dual: false), false, true),
            ("single-stale", try reading(age: 7200, dual: false), false, false)]
        for (name, reading, needsApp, failed) in states {
            let value = ProviderReading(service: .claude, reading: reading, needsApp: needsApp, updateFailed: failed)
            let views: [(String, AnyView, CGFloat, CGFloat)] = [
                ("details", AnyView(ServiceDetailsView(value: value, date: now)),160,72),
                ("compact", AnyView(CompactQuotaView(service: .claude, reading: reading, needsApp: needsApp, date: now, compact: true, updateFailed: failed)),79,72),
                ("circular", AnyView(CodexDial(value: value, date: now)),72,72),
                ("home", AnyView(HomeQuotaView(values: [value], date: now, layout: .small)),158,158)]
            for (surface, view, width, height) in views {
                let renderer = ImageRenderer(content: view.frame(width: width, height: height).background(Color.black).environment(\.colorScheme,.dark))
                renderer.scale = 3
                let image = try XCTUnwrap(renderer.uiImage)
                XCTAssertEqual(image.size, CGSize(width: width, height: height))
                let file = FileManager.default.temporaryDirectory.appendingPathComponent("freshness-\(surface)-\(name).png")
                try image.pngData()?.write(to: file); print("FRESHNESS_REVIEW " + file.path)
                let attachment = XCTAttachment(image: image); attachment.lifetime = .keepAlways; add(attachment)
            }
        }
    }
}

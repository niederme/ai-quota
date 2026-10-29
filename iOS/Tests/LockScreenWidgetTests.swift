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
        // October 22 reset copy uses proportional digits; only usage percentages are monospaced.
        let font = UIFont.systemFont(ofSize: 14, weight: .medium)
        let combinedFont = UIFont.systemFont(ofSize: 11, weight: .medium)
        for day in ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"] {
            for hour in 1...12 { for minute in 0...59 { for period in ["AM", "PM"] {
                let text = "\(day) \(hour):" + String(format: "%02d", minute) + " " + period
                XCTAssertLessThanOrEqual((text as NSString).size(withAttributes: [.font: font]).width, 98, text)
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
    func testOctober22StyleMatchesHistoricalRendering() throws {
        for service in QuotaService.allCases { for dual in [false, true] { for dark in [false, true] {
            let sample = try reading(reset: now.addingTimeInterval(86400), dual: dual)
            let value = ProviderReading(service: service, reading: sample, needsApp: false)
            let account = WidgetAccountContent(id: "\(service.rawValue):work", value: value, label: "A Longer Account Name")
            func image<V: View>(_ view: V) throws -> UIImage {
                let renderer = ImageRenderer(content: view.frame(width: 160, height: 72)
                    .foregroundStyle(.white).background(.black)
                    .environment(\.colorScheme, dark ? .dark : .light))
                renderer.scale = 3
                return try XCTUnwrap(renderer.uiImage)
            }
            let historical = try image(October22ServiceDetailsView(value: value, date: now))
            let restored = try image(AccountLockView(account: account, date: now))
            XCTAssertEqual(restored.pngData(), historical.pngData(), "October 22 styling differs: \(service), dual=\(dual), dark=\(dark)")
            for (label, capture) in [("oct22-original", historical), ("restored", restored),
                ("long-name", try image(AccountLockView(account: account, date: now, showAccountNames: true)))] {
                let attachment = XCTAttachment(image: capture)
                attachment.name = "\(label)-\(service)-dual-\(dual)-dark-\(dark)"
                attachment.lifetime = .keepAlways; add(attachment)
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

// Verbatim October 22 a82fbdb rendering fixture; only type names are changed.
private struct October22CodexDial: View {
    let value: ProviderReading
    let date: Date
    var logoScale: CGFloat = 1
    private var stale: Bool { WidgetReadingStatus.isSaved(value.reading, needsApp: value.needsApp, updateFailed: value.updateFailed, at: date) }
    private var warning: Bool { WidgetFreshness.limitReached(value.reading) }
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                ring(value.reading?.primaryDisplayWindow, width: (value.reading?.windows.count == 1 || value.reading?.budgetOnly != nil) ? size * 0.13 : size * 0.12, opacity: 1)
                    .padding((value.reading?.windows.count == 1 || value.reading?.budgetOnly != nil) ? size * 0.095 : size * 0.09)
                if let secondary = value.reading?.secondaryWindow {
                    ring(secondary, width: size * 0.12, opacity: 0.6)
                        .padding(size * 0.21 + 1)
                }
                if value.reading?.metadata?.plan == "Demo" {
                    Text("Demo").font(.system(size: size * 0.16, weight: .semibold))
                } else if value.needsApp {
                    Image(systemName: "exclamationmark").font(.system(size: size * 0.3, weight: .bold))
                } else {
                Image(value.service.logo)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.324 * logoScale, height: size * 0.324 * logoScale)
                    .foregroundStyle(.primary)
                }
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(3)
        .opacity(stale ? 0.45 : 1)
        .overlay(alignment: .bottomTrailing) {
            if stale && !value.needsApp { Image(systemName: "clock.fill").font(.system(size: 11)).accessibilityHidden(true) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value.service.name) \(value.reading?.metadata?.plan == "Demo" ? "sample" : "allowance") used")
        .accessibilityValue("\(value.reading?.accessibilitySummary ?? "Allowance unavailable"). \(value.needsApp ? "Reconnect in AIQuota." : "") \(stale ? WidgetReadingStatus.savedLabel(value.reading, at: date) + ". Reading needs refreshing." : "") \(warning ? "An allowance limit is reached." : "")")
        .accessibilityHint("Opens AIQuota")
    }

    private func ring(_ window: QuotaWindow?, width: CGFloat, opacity: Double) -> some View {
        ZStack {
            Circle().trim(from: 0, to: 0.75)
                .stroke(.primary.opacity(0.18), style: StrokeStyle(lineWidth: width, dash: window == nil ? [2, 3] : []))
            if let window {
                Circle().trim(from: 0, to: 0.75 * min(1, max(0, window.usedPercent / 100)))
                    .stroke(.primary.opacity(opacity),
                            style: StrokeStyle(lineWidth: width, dash: []))
            }
        }.rotationEffect(.degrees(135))
    }
}


private struct October22ServiceDetailsView: View {
    let value: ProviderReading
    let date: Date
    private var reset: LockScreenResetPresentation? {
        value.updateFailed ? nil : .make(reading: value.reading, needsApp: value.needsApp, at: date)
    }
    private var accessibilityValue: String {
        var parts = [value.reading?.accessibilitySummary ?? "Allowance unavailable"]
        if let reset { parts.append(reset.accessibilityText) }
        if value.needsApp { parts.append("Reconnect in AIQuota.") }
        if WidgetReadingStatus.isSaved(value.reading, needsApp: value.needsApp, updateFailed: value.updateFailed, at: date) {
            parts.append(WidgetReadingStatus.savedLabel(value.reading, at: date) + ". Reading needs refreshing.")
        }
        return parts.joined(separator: ". ")
    }
    var body: some View {
        HStack(spacing: 2) {
            October22CodexDial(value: value, date: date, logoScale: 0.8).frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 0) {
                Text(value.service.name).font(.system(size: 14, weight: .regular)).lineLimit(1)
                if let budget = value.reading?.budgetOnly {
                    Text("\(budget.amountText(budget.used)) / \(budget.amountText(budget.limit))")
                        .font(.system(size: 14, weight: .medium)).lineLimit(1).minimumScaleFactor(0.75)
                } else {
                    metric(value.reading?.primaryWindow).foregroundStyle(.primary)
                }
                if let secondary = value.reading?.secondaryWindow {
                    metric(secondary).foregroundStyle(.secondary).offset(y: 1)
                } else if let reset {
                    Text(reset.text).font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary).lineLimit(1).offset(y: 1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value.service.name) \(value.reading?.metadata?.plan == "Demo" ? "sample" : "allowance") used")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Opens AIQuota")
    }
    private func metric(_ window: QuotaWindow?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(window.map { "\(Int($0.usedPercent.rounded()))%" } ?? "N/A").monospacedDigit()
            Text(window?.compactLabel ?? "")
        }.font(.system(size: 14, weight: .medium)).lineLimit(1)
    }
}

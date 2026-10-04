import XCTest
import SwiftUI
import MobileAccessCore
@testable import AIQuota_iOS

final class ClaudeAnalyticsTests: XCTestCase {
    @MainActor func testClaudeCardsRenderAllStatesAndLargeText() throws {
        let fixture = Data(#"{"seven_day":{"utilization":56},"extra_usage":{"used_credits":12.4,"currency":"USD"},"seven_day_breakdown":{"as_of":"2026-10-04T09:16:00Z","window_started_at":"2026-09-30T09:16:00Z","rows":[{"key":"code","display_name":"Claude Code with a longer product name","percent":72},{"key":"chat","display_name":"Chats","percent":21},{"key":"cowork","display_name":"Cowork","percent":7},{"key":"other","display_name":"Other","percent":0}]}}"#.utf8)
        let reading = try ClaudeAPI.decodeUsage(fixture, now: .now)
        let breakdown = try XCTUnwrap(reading.claudeBreakdown)
        for scheme in [ColorScheme.dark, .light] {
            for size in [DynamicTypeSize.large, .accessibility3] {
                let cards: [AnyView] = [
                    AnyView(ClaudeAnalyticsView(reading: reading, busy: false, failed: false, refresh: {})),
                    AnyView(ClaudeAnalyticsView(reading: reading, busy: true, failed: false, refresh: {})),
                    AnyView(ClaudeAnalyticsView(reading: reading, busy: false, failed: true, refresh: {})),
                    AnyView(ClaudeAnalyticsView(reading: nil, busy: true, failed: false, refresh: {})),
                    AnyView(ClaudeAnalyticsView(reading: nil, busy: false, failed: true, refresh: {})),
                    AnyView(ClaudeProductDetail(row: breakdown.rows[0], breakdown: breakdown, failed: false))
                ]
                for (index, card) in cards.enumerated() {
                    let renderer = ImageRenderer(content: card.padding(20).frame(width: 402)
                        .background(OverviewStyle.base).environment(\.colorScheme, scheme)
                        .environment(\.dynamicTypeSize, size))
                    renderer.scale = 2
                    let image = try XCTUnwrap(renderer.uiImage)
                    XCTAssertEqual(image.size.width, 402)
                    XCTAssertGreaterThan(image.size.height, 100)
                    let path = FileManager.default.temporaryDirectory.appendingPathComponent("claude-analytics-\(scheme)-\(size)-\(index).png")
                    try XCTUnwrap(image.pngData()).write(to: path)
                    print("CLAUDE_REVIEW " + path.path)
                }
            }
        }
    }
}

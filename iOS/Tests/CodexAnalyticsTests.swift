import XCTest
import SwiftUI
import MobileAccessCore
@testable import AIQuota_iOS

final class CodexAnalyticsTests: XCTestCase {
    @MainActor func testTrendsRenderWithPartialAttributionAndLargeText() throws {
        let now = Date.now
        let rows = (0..<7).filter { $0 != 3 }.map { offset in
            let date = CodexUsageHistory.dateString(now.addingTimeInterval(-Double(offset) * 86400))
            return """
            {"date":"\(date)","product_surface_usage_values":{"cli":\(offset * 2),"desktop_app":\(offset)},
             "models":[{"model":"gpt-model-with-a-long-name","credits":\(offset * 2)},
                       {"model":"gpt-other","credits":\(offset)}]}
            """
        }.joined(separator: ",")
        let history = try CodexUsageHistory.decode(Data("{\"data\":[\(rows)]}".utf8), now: now)
        let data = CodexHistoryPeriod(history: history, count: 7)
        for scheme in [ColorScheme.dark, .light] {
            for size in [DynamicTypeSize.large, .accessibility3] {
                let cards: [AnyView] = [
                    AnyView(CodexTrendCard(title: "Daily usage", data: data, breakdown: nil)),
                    AnyView(CodexTrendCard(title: "By model", data: data, breakdown: .models)),
                    AnyView(CodexTrendCard(title: "By app", data: data, breakdown: .surfaces)),
                    AnyView(CodexTrendCard(title: "CLI", data: data, breakdown: .surfaces, focusedID: "cli")),
                    AnyView(CodexAnalyticsView(reading: nil, history: nil, historyUnavailable: true, busy: false, refresh: {}))
                ]
                for (index, card) in cards.enumerated() {
                    let content = card.padding(16).frame(width: 360)
                        .background(OverviewStyle.base)
                        .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, size)
                    let renderer = ImageRenderer(content: content)
                    renderer.scale = 2
                    let image = try XCTUnwrap(renderer.uiImage)
                    XCTAssertEqual(image.size.width, 360)
                    XCTAssertGreaterThan(image.size.height, 100)
                    let label = "\(scheme)-\(size)-\(index)"
                    let path = FileManager.default.temporaryDirectory.appendingPathComponent("codex-analytics-\(label).png")
                    try XCTUnwrap(image.pngData()).write(to: path)
                    print("ANALYTICS_REVIEW " + path.path)
                }
            }
        }
    }
}

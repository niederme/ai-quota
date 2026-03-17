import WidgetKit
import SwiftUI
import AIQuotaKit

struct AIQuotaWidgetView: View {
    let entry: QuotaEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:
            WidgetSmallView(entry: entry)
        case .systemMedium:
            WidgetMediumView(entry: entry)
        default:
            WidgetSmallView(entry: entry)
        }
    }
}

struct AIQuotaWidget: Widget {
    let kind = "AIQuotaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuotaTimelineProvider()) { entry in
            AIQuotaWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Codex Quota")
        .description("Track your OpenAI Codex weekly usage.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    AIQuotaWidget()
} timeline: {
    QuotaEntry.placeholder
    QuotaEntry.empty
}

#Preview(as: .systemMedium) {
    AIQuotaWidget()
} timeline: {
    QuotaEntry.placeholder
}

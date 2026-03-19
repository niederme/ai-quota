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
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: QuotaTimelineProvider()) { entry in
            AIQuotaWidgetView(entry: entry)
                .containerBackground(.ultraThinMaterial, for: .widget)
        }
        .configurationDisplayName("AI Quota")
        .description("Track your AI service usage quota.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
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

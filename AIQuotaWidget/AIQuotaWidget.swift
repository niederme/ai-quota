import WidgetKit
import SwiftUI
import AIQuotaKit

private struct ConfigurableQuotaWidgetView: View {
    let entry: QuotaEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium:
            WidgetSingleServiceMediumView(entry: entry)
        default:
            WidgetSmallView(entry: entry)
        }
    }
}

private struct StaticQuotaWidgetView: View {
    let entry: QuotaEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemLarge:
            WidgetLargeView(entry: entry)
        default:
            WidgetMediumView(entry: entry)
        }
    }
}

// MARK: - Configurable widget (small + medium, one service)

struct AIQuotaSmallWidget: Widget {
    let kind = "AIQuotaWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: QuotaTimelineProvider()) { entry in
            // Keep medium support on the original kind so pre-split installed widgets
            // continue rendering after updates instead of going blank.
            ConfigurableQuotaWidgetView(entry: entry)
                .containerBackground(Color(white: 0.1), for: .widget)
        }
        .configurationDisplayName("AI Quota")
        .description("Track your AI service usage quota.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

// MARK: - Static widget (medium + large, both services)

struct AIQuotaMediumWidget: Widget {
    let kind = "AIQuotaWidgetMedium"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StaticQuotaTimelineProvider()) { entry in
            StaticQuotaWidgetView(entry: entry)
                .containerBackground(Color(white: 0.1), for: .widget)
        }
        .configurationDisplayName("AI Quota")
        .description("Track both Codex and Claude Code with room for more detail.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Previews

#Preview(as: .systemSmall) {
    AIQuotaSmallWidget()
} timeline: {
    QuotaEntry.placeholder
    QuotaEntry.empty
}

#Preview(as: .systemMedium) {
    AIQuotaSmallWidget()
} timeline: {
    QuotaEntry.placeholder
}

#Preview(as: .systemMedium) {
    AIQuotaMediumWidget()
} timeline: {
    QuotaEntry.placeholder
}

#Preview(as: .systemLarge) {
    AIQuotaMediumWidget()
} timeline: {
    QuotaEntry.placeholder
}

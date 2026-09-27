import WidgetKit
import SwiftUI
import AIQuotaKit

private struct WidgetSurface: View {
    var body: some View {
        Color(red: 0x14 / 255.0, green: 0x0E / 255.0, blue: 0x18 / 255.0)
    }
}

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
                .environment(\.colorScheme, .dark)
                .containerBackground(for: .widget) { WidgetSurface() }
        }
        .configurationDisplayName("AIQuota")
        .description("Track your AI service usage quota.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}

// MARK: - Static widget (medium + large, both services)

struct AIQuotaMediumWidget: Widget {
    let kind = "AIQuotaWidgetMedium"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StaticQuotaTimelineProvider()) { entry in
            StaticQuotaWidgetView(entry: entry)
                .environment(\.colorScheme, .dark)
                .containerBackground(for: .widget) { WidgetSurface() }
        }
        .configurationDisplayName("AIQuota")
        .description("Track both Codex and Claude Code with room for more detail.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
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

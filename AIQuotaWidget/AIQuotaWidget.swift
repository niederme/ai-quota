import WidgetKit
import SwiftUI
import AIQuotaKit

// MARK: - Small widget (configurable service)

struct AIQuotaSmallWidget: Widget {
    let kind = "AIQuotaWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: QuotaTimelineProvider()) { entry in
            WidgetSmallView(entry: entry)
                .containerBackground(Color(white: 0.1), for: .widget)
        }
        .configurationDisplayName("AI Quota")
        .description("Track your AI service usage quota.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

// MARK: - Medium widget (always both services, no configuration)

struct AIQuotaMediumWidget: Widget {
    let kind = "AIQuotaWidgetMedium"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: MediumConfigurationAppIntent.self, provider: MediumQuotaTimelineProvider()) { entry in
            WidgetMediumView(entry: entry)
                .containerBackground(Color(white: 0.1), for: .widget)
        }
        .configurationDisplayName("AI Quota")
        .description("Track both Codex and Claude Code side by side.")
        .supportedFamilies([.systemMedium])
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
    AIQuotaMediumWidget()
} timeline: {
    QuotaEntry.placeholder
}

import Foundation

public enum CountdownTextFormatter {
    public enum Style: Sendable {
        case full
        case compact
    }

    public static func duration(_ seconds: Int, style: Style = .full) -> String {
        let clampedSeconds = max(0, seconds)
        let days = clampedSeconds / 86_400
        let hours = (clampedSeconds % 86_400) / 3_600
        let minutes = (clampedSeconds % 3_600) / 60

        if days > 0 {
            let components = [unit(days, singular: "day", style: style), optionalUnit(hours, singular: "hour", style: style)]
            return join(components, style: style)
        }

        if hours > 0 {
            let components = [unit(hours, singular: "hour", style: style), optionalUnit(minutes, singular: "minute", style: style)]
            return join(components, style: style)
        }

        if minutes > 0 {
            return unit(minutes, singular: "minute", style: style)
        }

        return style == .full ? "less than a minute" : "<1m"
    }

    private static func optionalUnit(_ value: Int, singular: String, style: Style) -> String? {
        value > 0 ? unit(value, singular: singular, style: style) : nil
    }

    private static func unit(_ value: Int, singular: String, style: Style) -> String {
        switch style {
        case .full:
            let plural = value == 1 ? singular : "\(singular)s"
            return "\(value) \(plural)"
        case .compact:
            let suffix: String = switch singular {
            case "day": "d"
            case "hour": "h"
            default: "m"
            }
            return "\(value)\(suffix)"
        }
    }

    private static func join(_ components: [String?], style: Style) -> String {
        let values = components.compactMap { $0 }
        switch style {
        case .full:
            return values.joined(separator: ", ")
        case .compact:
            return values.joined(separator: " ")
        }
    }
}

import Foundation
import MobileAccessCore

public enum CountdownTextFormatter {
    public enum Style: Sendable {
        case full
        case compact
    }

    public static func duration(_ seconds: Int, style: Style = .full, locale: Locale = .autoupdatingCurrent) -> String {
        let clampedSeconds = max(0, seconds)
        guard locale.language.languageCode == .english else {
            return localizedDuration(clampedSeconds, style: style, locale: locale)
        }
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

    /// Non-English languages get Foundation's own unit names and plurals in full
    /// ("1 Tag, 3 Stunden"); compact countdowns use the same keys as the dials
    /// ("1 T 3 Std."). English keeps the house style.
    private static func localizedDuration(_ seconds: Int, style: Style, locale: Locale) -> String {
        guard seconds >= 60 else {
            return style == .full
                ? String(localized: "less than a minute", bundle: .module, locale: locale, comment: "Countdown shown when a reset is under a minute away.")
                : String(localized: "<1m", bundle: .module, locale: locale, comment: "Compact countdown shown when a reset is under a minute away.")
        }
        if style == .compact {
            let days = seconds / 86_400
            let hours = (seconds % 86_400) / 3_600
            let minutes = (seconds % 3_600) / 60
            if days > 0 {
                return hours > 0 ? "\(WindowKeyText.days(days)) \(WindowKeyText.hours(hours))" : WindowKeyText.days(days)
            }
            if hours > 0 {
                return minutes > 0 ? "\(WindowKeyText.hours(hours)) \(WindowKeyText.minutes(minutes))" : WindowKeyText.hours(hours)
            }
            return WindowKeyText.minutes(minutes)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.unitsStyle = .full
        formatter.allowedUnits = seconds >= 86_400 ? [.day, .hour] : [.hour, .minute]
        formatter.zeroFormattingBehavior = .dropAll
        formatter.maximumUnitCount = 2
        return formatter.string(from: TimeInterval(seconds - seconds % 60)) ?? ""
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

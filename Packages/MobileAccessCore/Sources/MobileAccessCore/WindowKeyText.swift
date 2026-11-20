import Foundation

/// Compact usage-window keys ("5h", "7d", "30d") shown in dials, cards, widgets and reset captions.
/// Code still uses the raw English keys as identifiers; localize only at display time.
public enum WindowKeyText {
    public static func days(_ count: Int) -> String {
        String(localized: "\(count)d", bundle: .module,
               comment: "Compact usage-window key: a number of days, such as “7d” or “30d”. Keep it as short as possible; it sits inside a small dial.")
    }

    public static func hours(_ count: Int) -> String {
        String(localized: "\(count)h", bundle: .module,
               comment: "Compact usage-window key: a number of hours, such as “5h”. Keep it as short as possible; it sits inside a small dial.")
    }

    /// Localizes a raw key such as "5h", "7d", "28d" or "7-day". Anything else is returned unchanged.
    public static func display(_ key: String) -> String {
        if key.hasSuffix("-day"), let count = Int(key.dropLast(4)) {
            return String(localized: "\(count)-day", bundle: .module,
                          comment: "Short usage-window name, such as “7-day”. Shown next to a percentage in a widget.")
        }
        if key.hasSuffix("-hour"), let count = Int(key.dropLast(5)) {
            return String(localized: "\(count)-hour", bundle: .module,
                          comment: "Short usage-window name, such as “5-hour”. Shown next to a percentage in a widget.")
        }
        guard let unit = key.last, let count = Int(key.dropLast()) else { return key }
        switch unit {
        case "d": return days(count)
        case "h": return hours(count)
        default: return key
        }
    }
}

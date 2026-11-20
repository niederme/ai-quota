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

    /// Compact minutes in a countdown, such as "45m".
    public static func minutes(_ count: Int) -> String {
        String(localized: "\(count)m", bundle: .module,
               comment: "Compact minutes in a countdown, such as “45m” or the “15m” in “2h 15m”. Keep it as short as possible.")
    }

    /// Two compact units of one countdown, such as "2d 3h" or "2h 15m".
    public static func pair(_ larger: String, _ smaller: String) -> String {
        String(localized: "duration.pair", defaultValue: "\(larger) \(smaller)", bundle: .module,
               comment: "Joins the two parts of a compact countdown, such as “2d” and “3h” in “2d 3h”. Leave out the space if your language writes them together.")
    }

    /// Localizes a raw key such as "5h", "7d" or "28d". Anything else is returned unchanged.
    public static func display(_ key: String) -> String {
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

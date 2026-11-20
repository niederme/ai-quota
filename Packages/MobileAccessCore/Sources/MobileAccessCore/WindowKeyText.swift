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

    /// Localizes a raw key such as "5h", "7d" or "28d". Anything else is returned unchanged.
    public static func display(_ key: String) -> String {
        guard let unit = key.last, let count = Int(key.dropLast()) else { return key }
        switch unit {
        case "d": return days(count)
        case "h": return hours(count)
        default: return key
        }
    }
}

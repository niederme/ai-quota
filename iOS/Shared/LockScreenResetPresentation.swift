import Foundation
import MobileAccessCore

/// Account-reported reset only; public reset announcements are unrelated.
struct LockScreenResetPresentation: Equatable {
    let text: String
    let accessibilityText: String

    static func make(reading: QuotaReading?, needsApp: Bool, at date: Date,
                     calendar: Calendar = .autoupdatingCurrent,
                     locale: Locale = .autoupdatingCurrent) -> Self? {
        guard !needsApp, let reading, reading.windows.count == 1,
              reading.fetchedAt.timeIntervalSince1970.isFinite,
              date.timeIntervalSince1970.isFinite,
              !WidgetFreshness.isOld(reading, at: date),
              let reset = reading.primaryWindow?.resetsAt,
              reset.timeIntervalSince1970.isFinite,
              reset.timeIntervalSince1970 < 253402300800, reset > date else { return nil }
        let weekday = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][calendar.component(.weekday, from: reset) - 1]
        let time = DateFormatter()
        // Explicitly requested three-letter English days and 12-hour AM/PM copy.
        time.locale = Locale(identifier: "en_US_POSIX")
        time.calendar = calendar
        time.timeZone = calendar.timeZone
        time.dateFormat = "h:mm a"
        let spoken = DateFormatter()
        spoken.locale = locale
        spoken.calendar = calendar
        spoken.timeZone = calendar.timeZone
        spoken.dateStyle = .full
        spoken.timeStyle = .short
        return Self(text: weekday + " " + time.string(from: reset),
                    accessibilityText: "Reset expected " + spoken.string(from: reset))
    }
}

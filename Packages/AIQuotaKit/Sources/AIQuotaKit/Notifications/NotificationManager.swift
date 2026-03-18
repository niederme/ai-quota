import Foundation
import UserNotifications

/// Fires local notifications when quota crosses key thresholds or resets.
///
/// Threshold state is persisted in the shared App Group UserDefaults so it
/// survives app restarts and doesn't spam the user on every refresh.
public actor NotificationManager {

    public static let shared = NotificationManager()

    // MARK: - Persistence keys

    private enum Key {
        static let notifiedThresholds = "notificationThresholds"   // [String]
        static let lastWeeklyResetAt  = "notificationLastResetAt"  // Double (Unix timestamp)
    }

    private var defaults: UserDefaults {
        UserDefaults(suiteName: "group.com.niederme.AIQuota") ?? .standard
    }

    // MARK: - Public API

    /// Asks the system for notification permission. Safe to call multiple times.
    public func requestPermission() async {
        try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    /// Called after every successful quota fetch. Fires at most one notification
    /// per threshold per weekly window, and one "reset" notification when the
    /// weekly window rolls over.
    public func evaluate(current: CodexUsage) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let storedResetAt = defaults.object(forKey: Key.lastWeeklyResetAt) as? Double
        let currentResetAt = current.weeklyResetAt.timeIntervalSince1970

        // ── Quota reset: week rolled over ──────────────────────────────────
        if let stored = storedResetAt, stored != currentResetAt {
            clearThresholds()
            defaults.set(currentResetAt, forKey: Key.lastWeeklyResetAt)
            await send(
                id: "quotaReset",
                title: "Codex quota reset",
                body: "Your weekly Codex quota has reset — you're back to 100%."
            )
            return
        }

        // First run: just store the reset date, no notification
        if storedResetAt == nil {
            defaults.set(currentResetAt, forKey: Key.lastWeeklyResetAt)
            return
        }

        // ── Threshold notifications (fire once per threshold per week) ─────
        let notified = loadThresholds()
        let remaining = current.weeklyRemaining

        if current.limitReached && !notified.contains("limitReached") {
            markThreshold("limitReached")
            await send(
                id: "limitReached",
                title: "Codex quota reached",
                body: "Your weekly Codex quota is fully used. Resets in \(timeString(current.weeklyResetAfterSeconds))."
            )
        } else if remaining < 5 && !notified.contains("below5") {
            markThreshold("below5")
            await send(
                id: "below5",
                title: "Codex quota critical",
                body: "Less than 5% of your weekly Codex quota remains."
            )
        } else if remaining < 15 && !notified.contains("below15") {
            markThreshold("below15")
            await send(
                id: "below15",
                title: "Codex quota low",
                body: "Less than 15% of your weekly Codex quota remains."
            )
        }
    }

    // MARK: - Test helper

    /// Fires all four notification types with a 2-second delay between each.
    /// Ignores threshold state — for development/QA only.
    public func fireTestNotifications() async {
        let notifications: [(String, String, String)] = [
            ("test.below15",     "Codex quota low",      "Less than 15% of your weekly Codex quota remains."),
            ("test.below5",      "Codex quota critical", "Less than 5% of your weekly Codex quota remains."),
            ("test.limitReached","Codex quota reached",  "Your weekly Codex quota is fully used. Resets in 9h 30m."),
            ("test.reset",       "Codex quota reset",    "Your weekly Codex quota has reset — you're back to 100%."),
        ]
        for (id, title, body) in notifications {
            await send(id: id, title: title, body: body)
            do { try await Task.sleep(for: .seconds(2)) } catch {}
        }
    }

    // MARK: - Private helpers

    private func send(id: String, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        do { try await UNUserNotificationCenter.current().add(request) } catch {}
    }

    private func loadThresholds() -> Set<String> {
        Set(defaults.stringArray(forKey: Key.notifiedThresholds) ?? [])
    }

    private func markThreshold(_ threshold: String) {
        var set = loadThresholds()
        set.insert(threshold)
        defaults.set(Array(set), forKey: Key.notifiedThresholds)
    }

    private func clearThresholds() {
        defaults.removeObject(forKey: Key.notifiedThresholds)
    }

    private func timeString(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

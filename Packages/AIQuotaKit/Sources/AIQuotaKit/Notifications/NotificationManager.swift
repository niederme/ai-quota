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
        // Codex
        static let codexThresholds  = "notificationThresholds"
        static let codexLastResetAt = "notificationLastResetAt"
        // Claude 5h window
        static let claudeThresholds  = "claudeNotificationThresholds"
        static let claudeLastResetAt = "claudeNotificationLastResetAt"
        // Claude 7-day window
        static let claudeSevenDayThresholds  = "claudeSevenDayThresholds"
        static let claudeSevenDayLastResetAt = "claudeSevenDayLastResetAt"
    }

    private var defaults: UserDefaults {
        UserDefaults(suiteName: "group.com.niederme.AIQuota") ?? .standard
    }

    // MARK: - Public API

    /// Asks the system for notification permission. Safe to call multiple times.
    public func requestPermission() async {
        do {
            try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {}
    }

    // MARK: - Codex evaluation

    /// Called after every successful Codex fetch. Fires at most one notification
    /// per threshold per weekly window, and one "reset" notification when the week rolls over.
    public func evaluate(current: CodexUsage) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let storedResetAt  = defaults.object(forKey: Key.codexLastResetAt) as? Double
        let currentResetAt = current.weeklyResetAt.timeIntervalSince1970

        // ── Quota reset: week rolled over ──────────────────────────────────
        if let stored = storedResetAt {
            let storedDate = Date(timeIntervalSince1970: stored)
            if storedDate < .now {
                clearThresholds(key: Key.codexThresholds)
                defaults.set(currentResetAt, forKey: Key.codexLastResetAt)
                await send(
                    id: "codexReset",
                    title: "Codex quota reset",
                    body: "Your weekly Codex quota has reset — you're back to 100%."
                )
                return
            } else if stored != currentResetAt {
                defaults.set(currentResetAt, forKey: Key.codexLastResetAt)
            }
        } else {
            // First run: just store the reset date, no notification
            defaults.set(currentResetAt, forKey: Key.codexLastResetAt)
            return
        }

        // ── Threshold notifications (fire once per threshold per week) ─────
        let notified  = loadThresholds(key: Key.codexThresholds)
        let remaining = current.weeklyRemaining

        if current.limitReached && !notified.contains("limitReached") {
            markThreshold("limitReached", key: Key.codexThresholds)
            await send(
                id: "codexLimitReached",
                title: "Codex quota reached",
                body: "Your weekly Codex quota is fully used. Resets in \(timeString(current.weeklyResetAfterSeconds))."
            )
        } else if remaining < 5 && !notified.contains("below5") {
            markThreshold("below5", key: Key.codexThresholds)
            await send(
                id: "codexBelow5",
                title: "Codex quota critical",
                body: "Less than 5% of your weekly Codex quota remains."
            )
        } else if remaining < 15 && !notified.contains("below15") {
            markThreshold("below15", key: Key.codexThresholds)
            await send(
                id: "codexBelow15",
                title: "Codex quota low",
                body: "Less than 15% of your weekly Codex quota remains."
            )
        }
    }

    // MARK: - Claude evaluation

    /// Called after every successful Claude fetch. Fires once per threshold
    /// per rate-limit window, and once when the window resets.
    public func evaluate(claude: ClaudeUsage) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let storedResetAt  = defaults.object(forKey: Key.claudeLastResetAt) as? Double
        let currentResetAt = claude.resetAt.timeIntervalSince1970

        // ── Window reset ────────────────────────────────────────────────────
        // Use a time-has-passed check rather than timestamp equality.
        // resetAt is a rolling server-computed value that drifts by seconds on
        // every fetch, so != would fire on every refresh even with no real reset.
        if let stored = storedResetAt {
            let storedDate = Date(timeIntervalSince1970: stored)
            if storedDate < .now {
                // Old window has genuinely expired — notify and start fresh.
                clearThresholds(key: Key.claudeThresholds)
                defaults.set(currentResetAt, forKey: Key.claudeLastResetAt)
                await send(
                    id: "claudeReset",
                    title: "Claude window reset",
                    body: "Your Claude 5-hour window has reset — you're back to full capacity."
                )
                return
            } else if stored != currentResetAt {
                // Timestamp drifted but the window is still live — update silently.
                defaults.set(currentResetAt, forKey: Key.claudeLastResetAt)
            }
        } else {
            // First run: store the reset date, no notification.
            defaults.set(currentResetAt, forKey: Key.claudeLastResetAt)
            return
        }

        // ── 5h threshold notifications ─────────────────────────────────────
        let notified  = loadThresholds(key: Key.claudeThresholds)
        let remaining = claude.remainingPercent

        if claude.limitReached && !notified.contains("limitReached") {
            markThreshold("limitReached", key: Key.claudeThresholds)
            await send(
                id: "claudeLimitReached",
                title: "Claude rate limit reached",
                body: "Your 5-hour Claude window is fully used. Resets in \(timeString(claude.resetAfterSeconds))."
            )
        } else if remaining < 5 && !notified.contains("below5") {
            markThreshold("below5", key: Key.claudeThresholds)
            await send(
                id: "claudeBelow5",
                title: "Claude quota critical",
                body: "Less than 5% of your Claude 5-hour window capacity remains."
            )
        } else if remaining < 15 && !notified.contains("below15") {
            markThreshold("below15", key: Key.claudeThresholds)
            await send(
                id: "claudeBelow15",
                title: "Claude quota low",
                body: "Less than 15% of your Claude 5-hour window capacity remains."
            )
        }

        // ── 7-day threshold notifications ──────────────────────────────────
        // These fire on a separate cadence — the 7-day window is what causes
        // extended blackouts, so we warn early (80%) and critically (95%).
        let sevenDayUsed     = Int(claude.sevenDayUtilization.rounded())
        let sevenDayNotified = loadThresholds(key: Key.claudeSevenDayThresholds)
        let sevenDayResetAt  = claude.sevenDayResetsAt.timeIntervalSince1970
        let storedSevenDay   = defaults.object(forKey: Key.claudeSevenDayLastResetAt) as? Double

        if let stored = storedSevenDay {
            let storedDate = Date(timeIntervalSince1970: stored)
            if storedDate < .now {
                clearThresholds(key: Key.claudeSevenDayThresholds)
                defaults.set(sevenDayResetAt, forKey: Key.claudeSevenDayLastResetAt)
                await send(
                    id: "claudeSevenDayReset",
                    title: "Claude 7-day window reset",
                    body: "Your 7-day Claude allowance has reset — you're back to full capacity."
                )
            } else {
                if stored != sevenDayResetAt {
                    defaults.set(sevenDayResetAt, forKey: Key.claudeSevenDayLastResetAt)
                }
                if sevenDayUsed >= 100 && !sevenDayNotified.contains("limitReached") {
                    markThreshold("limitReached", key: Key.claudeSevenDayThresholds)
                    await send(
                        id: "claudeSevenDayLimit",
                        title: "Claude 7-day limit reached",
                        body: "Your 7-day Claude allowance is fully used. Resets in \(timeString(claude.sevenDayResetAfterSeconds))."
                    )
                } else if sevenDayUsed >= 95 && !sevenDayNotified.contains("above95") {
                    markThreshold("above95", key: Key.claudeSevenDayThresholds)
                    await send(
                        id: "claudeSevenDay95",
                        title: "Claude 7-day limit critical",
                        body: "You've used 95% of your 7-day Claude allowance. Resets in \(timeString(claude.sevenDayResetAfterSeconds))."
                    )
                } else if sevenDayUsed >= 80 && !sevenDayNotified.contains("above80") {
                    markThreshold("above80", key: Key.claudeSevenDayThresholds)
                    await send(
                        id: "claudeSevenDay80",
                        title: "Claude 7-day usage high",
                        body: "You've used 80% of your 7-day Claude allowance — consider slowing down."
                    )
                }
            }
        } else {
            defaults.set(sevenDayResetAt, forKey: Key.claudeSevenDayLastResetAt)
        }
    }

    // MARK: - Test helper

    /// Fires all notification types with a 2-second gap. For development/QA only.
    public func fireTestNotifications() async {
        let notifications: [(String, String, String)] = [
            ("test.codex.below15",          "Codex quota low",              "Less than 15% of your weekly Codex quota remains."),
            ("test.codex.below5",           "Codex quota critical",         "Less than 5% of your weekly Codex quota remains."),
            ("test.codex.limitReached",     "Codex quota reached",          "Your weekly Codex quota is fully used. Resets in 9h 30m."),
            ("test.codex.reset",            "Codex quota reset",            "Your weekly Codex quota has reset — you're back to 100%."),
            ("test.claude.below15",         "Claude quota low",             "Less than 15% of your Claude 5-hour window capacity remains."),
            ("test.claude.limitReached",    "Claude rate limit reached",    "Your 5-hour Claude window is fully used. Resets in 2h 15m."),
            ("test.claude.7day80",          "Claude 7-day usage high",      "You've used 80% of your 7-day Claude allowance — consider slowing down."),
            ("test.claude.7day95",          "Claude 7-day limit critical",  "You've used 95% of your 7-day Claude allowance. Resets in 4d 12h."),
            ("test.claude.7dayLimit",       "Claude 7-day limit reached",   "Your 7-day Claude allowance is fully used. Resets in 4d 12h."),
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

    private func loadThresholds(key: String) -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    private func markThreshold(_ threshold: String, key: String) {
        var set = loadThresholds(key: key)
        set.insert(threshold)
        defaults.set(Array(set), forKey: key)
    }

    private func clearThresholds(key: String) {
        defaults.removeObject(forKey: key)
    }

    private func timeString(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

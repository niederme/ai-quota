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
        // Codex — 5h window
        static let codex5hThresholds  = "codex5hThresholds"
        static let codex5hLastResetAt = "codex5hLastResetAt"
        // Codex — weekly window
        static let codexThresholds  = "notificationThresholds"
        static let codexLastResetAt = "notificationLastResetAt"
        // Codex — credit top-up diffing
        static let codexLastBalance = "codexLastBalance"
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
    public func evaluate(current: CodexUsage, prefs: NotificationPreferences) async {
        guard prefs.enabled, prefs.codexEnabled else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let storedResetAt  = defaults.object(forKey: Key.codexLastResetAt) as? Double
        let currentResetAt = current.weeklyResetAt.timeIntervalSince1970

        if let stored = storedResetAt {
            let storedDate = Date(timeIntervalSince1970: stored)
            if storedDate < .now {
                clearThresholds(key: Key.codexThresholds)
                defaults.set(currentResetAt, forKey: Key.codexLastResetAt)
                if prefs.codexReset {
                    await send(
                        id: "codexReset",
                        title: "Codex 7-day window reset",
                        body: "Your Codex 7-day window has reset. You're back to full capacity."
                    )
                }
                return
            } else if stored != currentResetAt {
                defaults.set(currentResetAt, forKey: Key.codexLastResetAt)
            }
        } else {
            defaults.set(currentResetAt, forKey: Key.codexLastResetAt)
            return
        }

        // ── 5-hour threshold notifications ────────────────────────────────
        let hourlyResetAt   = current.hourlyResetAt.timeIntervalSince1970
        let storedHourly    = defaults.object(forKey: Key.codex5hLastResetAt) as? Double

        if let stored5h = storedHourly {
            let storedDate5h = Date(timeIntervalSince1970: stored5h)
            if storedDate5h < .now {
                clearThresholds(key: Key.codex5hThresholds)
                defaults.set(hourlyResetAt, forKey: Key.codex5hLastResetAt)
                if prefs.codex5hReset {
                    await send(
                        id: "codex5hReset",
                        title: "Codex 5-hour window reset",
                        body: "Your Codex 5-hour window has reset. You're back to full capacity."
                    )
                }
            } else {
                if stored5h != hourlyResetAt { defaults.set(hourlyResetAt, forKey: Key.codex5hLastResetAt) }
                let notified5h  = loadThresholds(key: Key.codex5hThresholds)
                let remaining5h = max(0, 100 - current.hourlyUsedPercent)
                if current.limitReached && !notified5h.contains("limitReached") && prefs.codex5hLimitReached {
                    markThreshold("limitReached", key: Key.codex5hThresholds)
                    await send(id: "codex5hLimitReached", title: "Codex 5-hour limit reached",
                               body: "You've hit the limit for your Codex 5-hour window. Resets in \(timeString(current.hourlyResetAfterSeconds)).")
                } else if remaining5h < 5 && !notified5h.contains("below5") && prefs.codex5hAt5 {
                    markThreshold("below5", key: Key.codex5hThresholds)
                    await send(id: "codex5hBelow5", title: "Codex 5-hour near limit",
                               body: "You're almost at the limit for your Codex 5-hour window. Resets in \(timeString(current.hourlyResetAfterSeconds)).")
                } else if remaining5h < 15 && !notified5h.contains("below15") && prefs.codex5hAt15 {
                    markThreshold("below15", key: Key.codex5hThresholds)
                    await send(id: "codex5hBelow15", title: "Codex 5-hour usage high",
                               body: "You've used most of your Codex 5-hour window. Resets in \(timeString(current.hourlyResetAfterSeconds)).")
                }
            }
        } else {
            defaults.set(hourlyResetAt, forKey: Key.codex5hLastResetAt)
        }

        // ── Weekly threshold notifications ────────────────────────────────
        let notified  = loadThresholds(key: Key.codexThresholds)
        let remaining = current.weeklyRemaining

        if current.limitReached && !notified.contains("limitReached") && prefs.codexLimitReached {
            markThreshold("limitReached", key: Key.codexThresholds)
            await send(
                id: "codexLimitReached",
                title: "Codex 7-day limit reached",
                body: "You've hit the limit for your Codex 7-day window. Resets in \(timeString(current.weeklyResetAfterSeconds))."
            )
        } else if remaining < 5 && !notified.contains("below5") && prefs.codexAt5 {
            markThreshold("below5", key: Key.codexThresholds)
            await send(
                id: "codexBelow5",
                title: "Codex 7-day near limit",
                body: "You're almost at the limit for your Codex 7-day window. Resets in \(timeString(current.weeklyResetAfterSeconds))."
            )
        } else if remaining < 15 && !notified.contains("below15") && prefs.codexAt15 {
            markThreshold("below15", key: Key.codexThresholds)
            await send(
                id: "codexBelow15",
                title: "Codex 7-day usage high",
                body: "You've used most of your Codex 7-day window. Resets in \(timeString(current.weeklyResetAfterSeconds))."
            )
        }
    }

    // MARK: - Codex top-up detection

    /// Noise floor for top-up detection. Daily consumption commonly reaches
    /// 100–300 credits; real refills are typically ≥ 125 (recharge_target − recharge_threshold).
    /// 50 is well above normal variance without missing genuine top-ups.
    private let topUpNoiseFloor: Double = 50

    /// Called after every successful Codex usage fetch. Compares the current balance
    /// against the previously stored value; fires a notification when a top-up is
    /// detected (balance increased by more than the noise floor).
    ///
    /// Always updates the stored balance regardless of whether a notification fires —
    /// including on first launch (where it stores and returns without firing).
    public func evaluateTopUp(currentBalance: Double, autoReload: CodexAutoReload?, prefs: NotificationPreferences) async {
        let lastBalance = defaults.object(forKey: Key.codexLastBalance) as? Double
        defaults.set(currentBalance, forKey: Key.codexLastBalance)

        guard let lastBalance else { return }  // first launch — stored, don't fire
        guard currentBalance > lastBalance + topUpNoiseFloor else { return }

        // Real top-up detected; fire if permitted
        guard prefs.enabled, prefs.codexTopUp else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let title: String
        let body: String
        if autoReload?.isEnabled == true {
            title = "Codex credits topped up"
            body  = "Auto-reload added credits. New balance: \(Int(currentBalance))."
        } else {
            title = "Codex credits added"
            body  = "New balance: \(Int(currentBalance))."
        }
        await send(id: "codexTopUp", title: title, body: body)
    }

    // MARK: - Claude evaluation

    /// Called after every successful Claude fetch. Fires once per threshold
    /// per rate-limit window, and once when the window resets.
    public func evaluate(claude: ClaudeUsage, prefs: NotificationPreferences) async {
        guard prefs.enabled, prefs.claudeEnabled else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        if let fiveHourUsed = claude.fiveHourUtilization,
           let fiveHourResetAt = claude.fiveHourResetsAt {
            let storedResetAt  = defaults.object(forKey: Key.claudeLastResetAt) as? Double
            let currentResetAt = fiveHourResetAt.timeIntervalSince1970

            if let stored = storedResetAt {
                let storedDate = Date(timeIntervalSince1970: stored)
                if storedDate < .now {
                    clearThresholds(key: Key.claudeThresholds)
                    defaults.set(currentResetAt, forKey: Key.claudeLastResetAt)
                    if prefs.claude5hReset {
                        await send(
                            id: "claudeReset",
                            title: "Claude 5-hour window reset",
                            body: "Your Claude 5-hour window has reset. You're back to full capacity."
                        )
                    }
                    return
                } else if stored != currentResetAt {
                    defaults.set(currentResetAt, forKey: Key.claudeLastResetAt)
                }
            } else {
                defaults.set(currentResetAt, forKey: Key.claudeLastResetAt)
                return
            }

            let notified = loadThresholds(key: Key.claudeThresholds)
            let used = Int(fiveHourUsed.rounded())
            let remaining = max(0, 100 - used)
            let resetSeconds = max(0, Int(fiveHourResetAt.timeIntervalSinceNow))

            if fiveHourUsed >= 100 && !notified.contains("limitReached") && prefs.claude5hLimitReached {
                markThreshold("limitReached", key: Key.claudeThresholds)
                await send(
                    id: "claudeLimitReached",
                    title: "Claude 5-hour limit reached",
                    body: "You've hit the limit for your Claude 5-hour window. Resets in \(timeString(resetSeconds))."
                )
            } else if remaining < 5 && !notified.contains("below5") && prefs.claude5hAt5 {
                markThreshold("below5", key: Key.claudeThresholds)
                await send(
                    id: "claudeBelow5",
                    title: "Claude 5-hour near limit",
                    body: "You're almost at the limit for your Claude 5-hour window. Resets in \(timeString(resetSeconds))."
                )
            } else if remaining < 15 && !notified.contains("below15") && prefs.claude5hAt15 {
                markThreshold("below15", key: Key.claudeThresholds)
                await send(
                    id: "claudeBelow15",
                    title: "Claude 5-hour usage high",
                    body: "You've used most of your Claude 5-hour window. Resets in \(timeString(resetSeconds))."
                )
            }
        } else {
            clearThresholds(key: Key.claudeThresholds)
            defaults.removeObject(forKey: Key.claudeLastResetAt)
        }

        // ── 7-day threshold notifications ──────────────────────────────────
        guard let sevenDayUtilization = claude.sevenDayUtilization,
              let sevenDayResetsAt = claude.sevenDayResetsAt
        else {
            clearThresholds(key: Key.claudeSevenDayThresholds)
            defaults.removeObject(forKey: Key.claudeSevenDayLastResetAt)
            return
        }
        let sevenDayUsed     = Int(sevenDayUtilization.rounded())
        let sevenDayNotified = loadThresholds(key: Key.claudeSevenDayThresholds)
        let sevenDayResetAt  = sevenDayResetsAt.timeIntervalSince1970
        let sevenDayResetSeconds = max(0, Int(sevenDayResetsAt.timeIntervalSinceNow))
        let storedSevenDay   = defaults.object(forKey: Key.claudeSevenDayLastResetAt) as? Double

        if let stored = storedSevenDay {
            let storedDate = Date(timeIntervalSince1970: stored)
            if storedDate < .now {
                clearThresholds(key: Key.claudeSevenDayThresholds)
                defaults.set(sevenDayResetAt, forKey: Key.claudeSevenDayLastResetAt)
                if prefs.claude7dReset {
                    await send(
                        id: "claudeSevenDayReset",
                        title: "Claude 7-day window reset",
                        body: "Your Claude 7-day window has reset. You're back to full capacity."
                    )
                }
            } else {
                if stored != sevenDayResetAt {
                    defaults.set(sevenDayResetAt, forKey: Key.claudeSevenDayLastResetAt)
                }
                if sevenDayUsed >= 100 && !sevenDayNotified.contains("limitReached") && prefs.claude7dLimitReached {
                    markThreshold("limitReached", key: Key.claudeSevenDayThresholds)
                    await send(
                        id: "claudeSevenDayLimit",
                        title: "Claude 7-day limit reached",
                        body: "You've hit the limit for your Claude 7-day window. Resets in \(timeString(sevenDayResetSeconds))."
                    )
                } else if sevenDayUsed >= 95 && !sevenDayNotified.contains("above95") && prefs.claude7dAt95 {
                    markThreshold("above95", key: Key.claudeSevenDayThresholds)
                    await send(
                        id: "claudeSevenDay95",
                        title: "Claude 7-day near limit",
                        body: "You're almost at the limit for your Claude 7-day window. Resets in \(timeString(sevenDayResetSeconds))."
                    )
                } else if sevenDayUsed >= 80 && !sevenDayNotified.contains("above80") && prefs.claude7dAt80 {
                    markThreshold("above80", key: Key.claudeSevenDayThresholds)
                    await send(
                        id: "claudeSevenDay80",
                        title: "Claude 7-day usage high",
                        body: "You've used most of your Claude 7-day window. Resets in \(timeString(sevenDayResetSeconds))."
                    )
                }
            }
        } else {
            defaults.set(sevenDayResetAt, forKey: Key.claudeSevenDayLastResetAt)
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
        CountdownTextFormatter.duration(seconds)
    }
}

import Foundation
import UserNotifications
import MobileAccessCore

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

    /// Called only after a successful authenticated usage response, including recovery retries.
    public func notifyPlanChange(service: String, previous: String?, current: String?, enabled: Bool) async {
        guard enabled, let change = PlanChange(previous: previous, current: current) else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        await send(id: "plan-change.\(service.lowercased())", title: "\(service) plan changed to \(change.current)",
                   body: "Previously \(change.previous). Connection checked and usage is up to date.")
    }

    // MARK: - Codex evaluation

    /// Called after every successful Codex fetch. Fires at most one notification
    /// per threshold per weekly window, and one "reset" notification when the week rolls over.
    public func evaluate(current: CodexUsage, prefs: NotificationPreferences) async {
        guard prefs.enabled, prefs.codexEnabled else { return }
        guard current.reportedWindowShape != nil else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let weeklyResetPeak = observeReset(key: Key.codexLastResetAt, used: Double(current.weeklyUsedPercent), end: current.weeklyResetAt)
        let hourlyResetPeak = current.hasHourlyWindow ? observeReset(key: Key.codex5hLastResetAt, used: Double(current.hourlyUsedPercent), end: current.hourlyResetAt) : nil

        if prefs.codexReset && ResetAlertObservation.allows(priorPeak: weeklyResetPeak, minimum: prefs.codexResetMinimum) {
            await send(
                id: "codexReset",
                title: "Codex 7-day window reset",
                body: "Your Codex 7-day window has reset. You're back to full capacity."
            )
        }
        if prefs.codex5hReset && ResetAlertObservation.allows(priorPeak: hourlyResetPeak, minimum: prefs.codex5hResetMinimum) {
            await send(
                id: "codex5hReset",
                title: "Codex 5-hour window reset",
                body: "Your Codex 5-hour window has reset. You're back to full capacity."
            )
        }

        if current.hasHourlyWindow {
            await evaluateUsage(key: Key.codex5hThresholds, legacyEndKey: Key.codex5hLastResetAt,
                service: "Codex", window: "5-hour", used: Double(current.hourlyUsedPercent),
                end: current.hourlyResetAt, enabled: prefs.codex5hThresholdAlerts, threshold: prefs.codexUsageThreshold)
        }
        await evaluateUsage(key: Key.codexThresholds, legacyEndKey: Key.codexLastResetAt,
            service: "Codex", window: "7-day", used: Double(current.weeklyUsedPercent),
            end: current.weeklyResetAt, enabled: prefs.codexWeeklyThresholdAlerts, threshold: prefs.codexUsageThreshold)
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
        guard prefs.enabled, prefs.codexEnabled, prefs.codexTopUp else { return }
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

        let hourlyResetPeak = claude.fiveHourUtilization.flatMap { used in
            claude.fiveHourResetsAt.flatMap { observeReset(key: Key.claudeLastResetAt, used: used, end: $0) }
        }
        let weeklyResetPeak = claude.sevenDayUtilization.flatMap { used in
            claude.sevenDayResetsAt.flatMap { observeReset(key: Key.claudeSevenDayLastResetAt, used: used, end: $0) }
        }
        if prefs.claude5hReset && ResetAlertObservation.allows(priorPeak: hourlyResetPeak, minimum: prefs.claude5hResetMinimum) {
            await send(
                id: "claudeReset",
                title: "Claude 5-hour window reset",
                body: "Your Claude 5-hour window has reset. You're back to full capacity."
            )
        }
        if prefs.claude7dReset && ResetAlertObservation.allows(priorPeak: weeklyResetPeak, minimum: prefs.claude7dResetMinimum) {
            await send(
                id: "claudeSevenDayReset",
                title: "Claude 7-day window reset",
                body: "Your Claude 7-day window has reset. You're back to full capacity."
            )
        }

        if let used = claude.fiveHourUtilization, let end = claude.fiveHourResetsAt {
            await evaluateUsage(key: Key.claudeThresholds, legacyEndKey: Key.claudeLastResetAt,
                service: "Claude", window: "5-hour", used: used, end: end,
                enabled: prefs.claude5hThresholdAlerts, threshold: prefs.claudeUsageThreshold)
        }
        if let used = claude.sevenDayUtilization, let end = claude.sevenDayResetsAt {
            await evaluateUsage(key: Key.claudeSevenDayThresholds, legacyEndKey: Key.claudeSevenDayLastResetAt,
                service: "Claude", window: "7-day", used: used, end: end,
                enabled: prefs.claude7dThresholdAlerts, threshold: prefs.claudeUsageThreshold)
        }
    }

    private func evaluateUsage(key: String, legacyEndKey: String, service: String, window: String,
                               used: Double, end: Date, enabled: Bool, threshold: Int) async {
        guard end > .now else { return }
        let stateKey = key + ".singleUsage"
        var state = defaults.data(forKey: stateKey).flatMap { try? JSONDecoder().decode(UsageAlertState.self, from: $0) }
        // An alert already delivered by the old version counts for this window too.
        if state == nil, let oldEnd = defaults.object(forKey: legacyEndKey) as? Double,
           oldEnd == end.timeIntervalSince1970, !loadThresholds(key: key).isEmpty {
            state = UsageAlertState(windowEnd: end, highestNotified: Double(threshold))
        }
        var observation = state ?? UsageAlertState(windowEnd: end)
        observation.updateWindow(end: end, now: .now)
        defaults.set(try? JSONEncoder().encode(observation), forKey: stateKey)
        guard let level = observation.next(used: used, now: .now, enabled: enabled, threshold: Double(threshold)) else { return }
        observation.highestNotified = level
        // Reserve before awaiting delivery so concurrent refreshes cannot duplicate the alert.
        defaults.set(try? JSONEncoder().encode(observation), forKey: stateKey)
        let delivered = await send(id: key + ".usage", title: "\(service) \(window) usage at \(Int(used.rounded()))%",
            body: "Your \(threshold)% threshold was reached. Resets in \(timeString(max(0, Int(end.timeIntervalSinceNow)))).")
        if !delivered { defaults.removeObject(forKey: stateKey) }
    }

    // MARK: - Private helpers

    @discardableResult
    private func send(id: String, title: String, body: String) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        do { try await UNUserNotificationCenter.current().add(request); return true } catch { return false }
    }

    private func loadThresholds(key: String) -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    public func clearResetHistory(for service: ServiceType) {
        let keys = service == .codex ? [Key.codexLastResetAt, Key.codex5hLastResetAt] : [Key.claudeLastResetAt, Key.claudeSevenDayLastResetAt]
        for key in keys {
            defaults.removeObject(forKey: key + ".resetObservation")
            defaults.removeObject(forKey: key)
        }
        let usageKeys = service == .codex ? [Key.codexThresholds, Key.codex5hThresholds] : [Key.claudeThresholds, Key.claudeSevenDayThresholds]
        for key in usageKeys {
            defaults.removeObject(forKey: key + ".singleUsage")
            defaults.removeObject(forKey: key)
        }
    }

    private func observeReset(key: String, used: Double, end: Date) -> Double? {
        let storageKey = key + ".resetObservation"
        var observation = defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(ResetAlertObservation.self, from: $0) }
            ?? ResetAlertObservation(end: end, peak: used)
        let priorPeak = observation.observe(used: used, end: end, now: .now)
        if let data = try? JSONEncoder().encode(observation) { defaults.set(data, forKey: storageKey) }
        return priorPeak
    }

    private func timeString(_ seconds: Int) -> String {
        CountdownTextFormatter.duration(seconds)
    }
}

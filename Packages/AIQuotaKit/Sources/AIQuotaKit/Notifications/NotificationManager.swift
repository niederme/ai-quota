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
        let account = Self.name(provider: service == "Codex" ? .codex : .claude, providerID: nil, plan: current)
        await send(id: "plan-change.\(service.lowercased())",
                   title: String(localized: "\(account) plan changed to \(change.current)", bundle: .module,
                                 comment: "Notification title. First value is the account name, second the new plan name (Pro, Max…)."),
                   body: String(localized: "Previously \(change.previous). Connection checked and usage is up to date.", bundle: .module,
                                comment: "Notification body. The value is the previous plan name."))
    }

    // MARK: - Codex evaluation

    /// Called after every successful Codex fetch. Fires at most one notification
    /// per threshold per weekly window, and one "reset" notification when the week rolls over.
    public func evaluate(current: CodexUsage, prefs: NotificationPreferences) async {
        let display = Self.name(provider: .codex, providerID: current.accountID, plan: current.displayPlan)
        guard prefs.enabled, prefs.codexEnabled else { return }
        guard current.reportedWindowShape != nil else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let weeklyResetPeak = observeReset(key: Key.codexLastResetAt, used: Double(current.weeklyUsedPercent), end: current.weeklyResetAt)
        let hourlyResetPeak = current.hasHourlyWindow ? observeReset(key: Key.codex5hLastResetAt, used: Double(current.hourlyUsedPercent), end: current.hourlyResetAt) : nil

        if prefs.codexReset && ResetAlertObservation.allows(priorPeak: weeklyResetPeak, minimum: prefs.codexResetMinimum) {
            await send(id: "codexReset", title: Self.resetTitle(display, window: .sevenDay), body: Self.resetBody(display, window: .sevenDay))
        }
        if prefs.codex5hReset && ResetAlertObservation.allows(priorPeak: hourlyResetPeak, minimum: prefs.codex5hResetMinimum) {
            await send(id: "codex5hReset", title: Self.resetTitle(display, window: .fiveHour), body: Self.resetBody(display, window: .fiveHour))
        }

        if current.hasHourlyWindow {
            await evaluateUsage(key: Key.codex5hThresholds, legacyEndKey: Key.codex5hLastResetAt,
                service: display, window: .fiveHour, used: Double(current.hourlyUsedPercent),
                end: current.hourlyResetAt, enabled: prefs.codex5hThresholdAlerts, threshold: prefs.codexUsageThreshold)
        }
        await evaluateUsage(key: Key.codexThresholds, legacyEndKey: Key.codexLastResetAt,
            service: display, window: .sevenDay, used: Double(current.weeklyUsedPercent),
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
        let display = AccountRegistry.accounts(for: .codex).first(where: { $0.connectionKind == .legacyPrimary })?.presentation().notificationTitle ?? "Codex"
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
            title = String(localized: "\(display) credits topped up", bundle: .module, comment: "Notification title. The value is the account name.")
            body  = String(localized: "Auto-reload added credits. New balance: \(Int(currentBalance)).", bundle: .module,
                           comment: "Notification body. The value is the new credit balance.")
        } else {
            title = String(localized: "\(display) credits added", bundle: .module, comment: "Notification title. The value is the account name.")
            body  = String(localized: "New balance: \(Int(currentBalance)).", bundle: .module,
                           comment: "Notification body. The value is the new credit balance.")
        }
        await send(id: "codexTopUp", title: title, body: body)
    }

    // MARK: - Claude evaluation

    /// Called after every successful Claude fetch. Fires once per threshold
    /// per rate-limit window, and once when the window resets.
    public func evaluate(claude: ClaudeUsage, prefs: NotificationPreferences) async {
        let display = Self.name(provider: .claude, providerID: claude.quotaScopeID, plan: claude.planDisplayName)
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
            await send(id: "claudeReset", title: Self.resetTitle(display, window: .fiveHour), body: Self.resetBody(display, window: .fiveHour))
        }
        if prefs.claude7dReset && ResetAlertObservation.allows(priorPeak: weeklyResetPeak, minimum: prefs.claude7dResetMinimum) {
            await send(id: "claudeSevenDayReset", title: Self.resetTitle(display, window: .sevenDay), body: Self.resetBody(display, window: .sevenDay))
        }

        if let used = claude.fiveHourUtilization, let end = claude.fiveHourResetsAt {
            await evaluateUsage(key: Key.claudeThresholds, legacyEndKey: Key.claudeLastResetAt,
                service: display, window: .fiveHour, used: used, end: end,
                enabled: prefs.claude5hThresholdAlerts, threshold: prefs.claudeUsageThreshold)
        }
        if let used = claude.sevenDayUtilization, let end = claude.sevenDayResetsAt {
            await evaluateUsage(key: Key.claudeSevenDayThresholds, legacyEndKey: Key.claudeSevenDayLastResetAt,
                service: display, window: .sevenDay, used: used, end: end,
                enabled: prefs.claude7dThresholdAlerts, threshold: prefs.claudeUsageThreshold)
        }
    }

    enum AlertWindow { case fiveHour, sevenDay }

    static func resetTitle(_ account: String, window: AlertWindow) -> String {
        switch window {
        case .fiveHour: String(localized: "\(account) 5-hour window reset", bundle: .module, comment: "Notification title. The value is the account name.")
        case .sevenDay: String(localized: "\(account) 7-day window reset", bundle: .module, comment: "Notification title. The value is the account name.")
        }
    }

    static func resetBody(_ account: String, window: AlertWindow) -> String {
        switch window {
        case .fiveHour: String(localized: "Your \(account) 5-hour window has reset. You're back to full capacity.", bundle: .module,
                               comment: "Notification body. The value is the account name.")
        case .sevenDay: String(localized: "Your \(account) 7-day window has reset. You're back to full capacity.", bundle: .module,
                               comment: "Notification body. The value is the account name.")
        }
    }

    static func usageTitle(_ account: String, window: AlertWindow, used: Int) -> String {
        switch window {
        case .fiveHour: String(localized: "\(account) 5-hour usage at \(used)%", bundle: .module,
                               comment: "Notification title. First value is the account name, second the percent of the 5-hour limit used.")
        case .sevenDay: String(localized: "\(account) 7-day usage at \(used)%", bundle: .module,
                               comment: "Notification title. First value is the account name, second the percent of the 7-day limit used.")
        }
    }

    private func evaluateUsage(key: String, legacyEndKey: String, service: String, window: AlertWindow,
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
        let resetsIn = timeString(max(0, Int(end.timeIntervalSinceNow)))
        let delivered = await send(id: key + ".usage", title: Self.usageTitle(service, window: window, used: Int(used.rounded())),
            body: String(localized: "Your \(threshold)% threshold was reached. Resets in \(resetsIn).", bundle: .module,
                         comment: "Notification body. First value is the alert threshold percent, second a duration such as “2h 15m”."))
        if !delivered { defaults.removeObject(forKey: stateKey) }
    }

    static func name(provider: ServiceType, providerID: String?, plan: String?) -> String {
        let peers = AccountRegistry.accounts(for: provider)
        if let account = peers.first(where: { $0.connectionKind == .legacyPrimary && (providerID == nil || $0.workspaceID == providerID) }) {
            return account.presentation(plan: plan, among: peers).notificationTitle
        }
        let identity = AccountIdentity(key: "unmatched", service: provider == .codex ? "Codex" : "Claude", label: "", plan: plan)
        return AccountPresentation.resolve(identity, among: []).notificationTitle
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

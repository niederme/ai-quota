import Foundation
import AIQuotaKit

// MARK: - Demo keyframe engine (DEMO_MODE builds only)

#if DEMO_MODE

/// Drives a `QuotaViewModel` through a scripted timelapse of all usage states.
/// Claude and Codex advance on **independent** timers — reflecting heavier Claude
/// usage. Activate by calling `startIfNeeded(driving:)` once. Resets automatically
/// whenever the AIQuota menu bar popover opens.
@MainActor
final class DemoDriver {

    // MARK: - Per-service frame

    private struct ServiceFrame {
        /// 5-hour utilization 0–100.
        var fiveH: Double
        /// 7-day utilization 0–100.
        var sevenD: Double
        /// Seconds until 5h window resets (drives caption text).
        var resetSecs: Int
        /// Days until 7d window resets.
        var weeklyResetDays: Int
        /// How long to display this frame before advancing.
        var tick: Double
    }

    // MARK: - Claude timeline  (heavy user — weekly quota gone in ~2.5 days)
    //
    // Slow-motion time-lapse: each 5h cycle represents roughly half a
    // simulated day, so the 7-day window is exhausted after ~2.5 days with
    // 4 days still to go before it resets — while extra usage burns dollars.
    // Base ticks: normal 1.0s · amber 1.2s · red 1.4s · reset 0.5s → ~25s total.
    // ±25% jitter applied in scheduleNextClaude for a natural feel.
    // Frame 0 is applied immediately on open — no loading state.

    private let claudeFrames: [ServiceFrame] = [
        // Cycle 1 — day 1, morning: 0 → limit → reset  (7d: 0 → 26%)
        // Frame 0 is a clean slate, held for `startHold` before the climb.
        .init(fiveH:   0, sevenD:   0, resetSecs: 18000, weeklyResetDays: 6, tick: 1.0),
        .init(fiveH:  34, sevenD:   9, resetSecs: 11700, weeklyResetDays: 6, tick: 1.0),
        .init(fiveH:  62, sevenD:  16, resetSecs:  7800, weeklyResetDays: 6, tick: 1.0),
        .init(fiveH:  88, sevenD:  22, resetSecs:  2400, weeklyResetDays: 6, tick: 1.2), // amber
        .init(fiveH: 100, sevenD:  25, resetSecs: 15600, weeklyResetDays: 6, tick: 1.4), // red
        .init(fiveH:   0, sevenD:  26, resetSecs: 18000, weeklyResetDays: 6, tick: 0.5), // reset

        // Cycle 2 — day 1, evening: 7d climbs to ~52%
        .init(fiveH:  18, sevenD:  33, resetSecs: 14700, weeklyResetDays: 5, tick: 1.0),
        .init(fiveH:  46, sevenD:  40, resetSecs: 10800, weeklyResetDays: 5, tick: 1.0),
        .init(fiveH:  74, sevenD:  47, resetSecs:  6300, weeklyResetDays: 5, tick: 1.0),
        .init(fiveH:  91, sevenD:  50, resetSecs:  1500, weeklyResetDays: 5, tick: 1.2), // amber
        .init(fiveH: 100, sevenD:  51, resetSecs: 15900, weeklyResetDays: 5, tick: 1.4), // red
        .init(fiveH:   0, sevenD:  52, resetSecs: 18000, weeklyResetDays: 5, tick: 0.5),

        // Cycle 3 — day 2: 7d climbs to ~78%, Max upgrade + extra usage starts
        .init(fiveH:  22, sevenD:  59, resetSecs: 13800, weeklyResetDays: 5, tick: 1.0),
        .init(fiveH:  51, sevenD:  66, resetSecs:  9300, weeklyResetDays: 5, tick: 1.0),
        .init(fiveH:  78, sevenD:  72, resetSecs:  4800, weeklyResetDays: 5, tick: 1.0),
        .init(fiveH:  93, sevenD:  76, resetSecs:  1200, weeklyResetDays: 4, tick: 1.2), // amber
        .init(fiveH: 100, sevenD:  77, resetSecs: 16200, weeklyResetDays: 4, tick: 1.4), // red
        .init(fiveH:   0, sevenD:  78, resetSecs: 18000, weeklyResetDays: 4, tick: 0.5),

        // Cycle 4 — day 2.5: 7d exhausted with 4 days still on the clock
        .init(fiveH:  26, sevenD:  84, resetSecs: 12900, weeklyResetDays: 4, tick: 1.0),
        .init(fiveH:  54, sevenD:  90, resetSecs:  8400, weeklyResetDays: 4, tick: 1.2), // 7d amber
        .init(fiveH:  79, sevenD:  95, resetSecs:  4200, weeklyResetDays: 4, tick: 1.2),
        .init(fiveH:  92, sevenD:  98, resetSecs:  1800, weeklyResetDays: 4, tick: 1.2), // both amber
        .init(fiveH: 100, sevenD: 100, resetSecs: 15300, weeklyResetDays: 4, tick: 1.4), // both red
        .init(fiveH:   0, sevenD: 100, resetSecs: 18000, weeklyResetDays: 4, tick: 0.5), // 5h back, week gone

        // FINAL FRAME — held indefinitely (tick unused): weekly spent by
        // mid-week, extra usage over the cap, 4 days until relief.
        .init(fiveH:  36, sevenD: 100, resetSecs: 11400, weeklyResetDays: 4, tick: 0),
    ]

    // MARK: - Codex timeline  (lighter user — same 2.5 simulated days, 7d → ~58%)
    //
    // Shares Claude's simulated clock (weekly reset 6 → 4 days out) so both
    // gauges tell one coherent story. The drama here is the credits arc:
    // balance drains to zero, the exception bar appears, auto-reload tops up.
    // Base ticks: normal 1.1s · amber 1.3s · red 1.4s · reset 0.5s → ~25s total.
    // ±25% jitter applied in scheduleNextCodex for a natural feel.

    private let codexFrames: [ServiceFrame] = [
        // Cycle 1 — day 1: slow fill, 0 → limit → reset  (7d: 0 → 18%)
        // Frame 0 is a clean slate, held for `startHold` before the climb.
        .init(fiveH:   0, sevenD:   0, resetSecs: 18000, weeklyResetDays: 6, tick: 1.1),
        .init(fiveH:  19, sevenD:   5, resetSecs: 13200, weeklyResetDays: 6, tick: 1.1),
        .init(fiveH:  41, sevenD:   8, resetSecs: 10500, weeklyResetDays: 6, tick: 1.1),
        .init(fiveH:  66, sevenD:  12, resetSecs:  6900, weeklyResetDays: 6, tick: 1.1),
        .init(fiveH:  84, sevenD:  15, resetSecs:  2700, weeklyResetDays: 6, tick: 1.3), // amber
        .init(fiveH:  96, sevenD:  17, resetSecs:   600, weeklyResetDays: 6, tick: 1.1),
        .init(fiveH: 100, sevenD:  18, resetSecs: 15400, weeklyResetDays: 6, tick: 1.4), // red
        .init(fiveH:   0, sevenD:  18, resetSecs: 18000, weeklyResetDays: 6, tick: 0.5),

        // Cycle 2 — day 1.5: 7d climbs to ~38%
        .init(fiveH:  12, sevenD:  23, resetSecs: 15000, weeklyResetDays: 5, tick: 1.1),
        .init(fiveH:  33, sevenD:  27, resetSecs: 12000, weeklyResetDays: 5, tick: 1.1),
        .init(fiveH:  58, sevenD:  31, resetSecs:  8100, weeklyResetDays: 5, tick: 1.1),
        .init(fiveH:  80, sevenD:  35, resetSecs:  3600, weeklyResetDays: 5, tick: 1.3), // amber
        .init(fiveH:  97, sevenD:  37, resetSecs:   420, weeklyResetDays: 5, tick: 1.1),
        .init(fiveH: 100, sevenD:  38, resetSecs: 15700, weeklyResetDays: 5, tick: 1.4), // red
        .init(fiveH:   0, sevenD:  38, resetSecs: 18000, weeklyResetDays: 5, tick: 0.5),

        // Cycle 3 — day 2+: 7d climbs to ~58%, credits drain to zero and reload
        .init(fiveH:  10, sevenD:  43, resetSecs: 15300, weeklyResetDays: 4, tick: 1.1),
        .init(fiveH:  29, sevenD:  47, resetSecs: 12600, weeklyResetDays: 4, tick: 1.1),
        .init(fiveH:  50, sevenD:  51, resetSecs:  9300, weeklyResetDays: 4, tick: 1.1),
        .init(fiveH:  71, sevenD:  54, resetSecs:  5700, weeklyResetDays: 4, tick: 1.1),
        .init(fiveH:  85, sevenD:  56, resetSecs:  2400, weeklyResetDays: 4, tick: 1.3), // amber
        .init(fiveH: 100, sevenD:  57, resetSecs: 15700, weeklyResetDays: 4, tick: 1.4), // red + credits empty
        .init(fiveH:   0, sevenD:  57, resetSecs: 18000, weeklyResetDays: 4, tick: 0.6), // reload kicks in
        // FINAL FRAME — held indefinitely (tick unused)
        .init(fiveH:  21, sevenD:  58, resetSecs: 14700, weeklyResetDays: 4, tick: 0),
    ]

    // MARK: - Extra-usage progression (mirrors Claude timeline cycle indices)
    //
    // Cycles 1–2: no extra usage (Pro plan, strip hidden).
    // Cycle 3 onwards: Max plan with a $50 monthly extra-usage cap. Values are
    // cents, matching web-source production data, so the "Spent" row renders
    // real dollars ($22.50 → $51.50) while money is burning.
    // The strip itself appears only once monthly extra usage reaches the cap,
    // matching the "bars are exception states" rule — and it must persist on
    // the final held frame so the demo's resting state shows the overage.

    // MARK: - Codex balance progression
    //
    // First half: no known reload target — plain balance text slowly drains.
    // Just before auto-reload kicks in, the demo shows the exception state:
    // credits empty with reload configured but off, so the red bar earns space.
    // Then auto-reload turns on and the balance jumps to the target.

    private let codexBalance: [Int: Double] = {
        var map: [Int: Double] = [:]
        // Cycles 1–2: healthy balance, slowly drawing down
        for i in 0...14   { map[i] = 197.18 - Double(i) * 8 }   // 197 → 85
        // Cycle 3: visibly dropping into amber territory
        map[15] = 60
        map[16] = 36
        map[17] = 18
        map[18] = 11
        // Frame 19: red text, but no bar; without a reload target there is no
        // honest denominator to draw against.
        map[19] = 6
        // Frame 20: exhausted with reload configured but off — exception bar,
        // landing on the same beat as the 5h limit for maximum drama.
        map[20] = 0
        // Frame 21: auto-reload kicks in — balance jumps from 0 → 250.
        // This triggers the top-up notification (delta = 250 >> noise floor 50).
        map[21] = 250
        // Frame 22 (final): healthy balance, auto-reload on, warning softened
        map[22] = 238
        return map
    }()

    // MARK: - Codex auto-reload progression
    //
    // Frames 0–19: no auto-reload settings known, so Codex remains text-only.
    // Frame 20: reload is configured but off and credits hit zero, which shows
    // the exception bar.
    // Frames 21–22: auto-reload is on; normal/caution states stay text-only,
    // and the balance jump at frame 21 fires the top-up notification.

    private let codexAutoReloadFrames: [Int: CodexAutoReload] = {
        var map: [Int: CodexAutoReload] = [:]
        let off = CodexAutoReload(isEnabled: false, rechargeThreshold: 125, rechargeTarget: 250)
        let on = CodexAutoReload(isEnabled: true, rechargeThreshold: 125, rechargeTarget: 250)
        map[20] = off
        for i in 21...22 { map[i] = on }
        return map
    }()

    private let claudeExtraUsage: [Int: ClaudeUsage.ExtraUsage] = {
        // Monthly extra-usage cap in cents ($50), like web-source production data.
        let cap = 5000
        func extra(_ cents: Double) -> ClaudeUsage.ExtraUsage {
            .init(
                isEnabled: true,
                monthlyLimit: cap,
                usedCredits: cents,
                utilization: cents / Double(cap) * 100
            )
        }
        var map: [Int: ClaudeUsage.ExtraUsage] = [:]
        // Cycle 3 (frames 12–17): moderate spend, $22.50 → $36, plain text row.
        let cycle3: [Double] = [2250, 2600, 2950, 3250, 3450, 3600]
        for (i, cents) in cycle3.enumerated() { map[12 + i] = extra(cents) }
        // Cycle 4 (frames 18–23): climbs through amber (≥ 85%) and hits the
        // cap on the frame where the 5h resets but the week stays gone.
        let cycle4: [Double] = [3850, 4150, 4400, 4650, 4900, 5000]
        for (i, cents) in cycle4.enumerated() { map[18 + i] = extra(cents) }
        // Final frame (24) is held forever, so the exception strip stays on
        // screen at the demo's resting state.
        map[24] = extra(5150)
        return map
    }()

    // MARK: - State

    /// Hold on frame 0 for this long before the time-lapse starts, so the
    /// freshly opened popover has a beat of calm before things move.
    private let startHold: TimeInterval = 5

    private weak var target: QuotaViewModel?

    private var claudeIndex = 0
    private var codexIndex  = 0
    private var claudeTimer: Timer?
    private var codexTimer:  Timer?

    // MARK: - Public API

    /// Store the view model target. Call once from `.task` in `AIQuotaApp`.
    func prepare(for viewModel: QuotaViewModel) {
        target = viewModel
    }

    /// Restart the sequence from frame 0. Call from `.onAppear` and ⌘R.
    func reset() {
        claudeTimer?.invalidate()
        codexTimer?.invalidate()
        claudeTimer = nil
        codexTimer  = nil
        claudeIndex = 0
        codexIndex  = 0
        target?.prepareForDemo()

        // Apply frame 0 of each service immediately — no loading state shown.
        applyNextClaudeFrame()
        applyNextCodexFrame()
    }

    /// Stop timers without resetting progress. Call from `.onDisappear`.
    func pause() {
        claudeTimer?.invalidate()
        codexTimer?.invalidate()
        claudeTimer = nil
        codexTimer  = nil
    }

    // MARK: Claude advancement

    private func scheduleNextClaude() {
        guard claudeIndex < claudeFrames.count else { return }
        // A frame's tick is how long it stays on screen; the frame just
        // shown is claudeIndex - 1. The final frame schedules nothing, so
        // it is held indefinitely.
        let base = claudeFrames[claudeIndex - 1].tick
        var duration = base * Double.random(in: 0.75...1.25)
        if claudeIndex == 1 { duration += startHold }  // hold on the opening frame
        claudeTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.applyNextClaudeFrame() }
        }
    }

    private func applyNextClaudeFrame() {
        guard claudeIndex < claudeFrames.count, let target else { return }
        let f = claudeFrames[claudeIndex]
        claudeIndex += 1

        let now = Date.now
        let extra = claudeExtraUsage[claudeIndex - 1]
        // Web-source production data reports extra usage in cents with a
        // currency code, so the "Spent" row shows dollars burning.
        let bonus = extra.map {
            ClaudeUsage.BonusUsage(
                spent: $0.usedCredits / 100,
                monthlyLimit: Double($0.monthlyLimit) / 100,
                utilization: $0.utilization,
                currencyCode: "USD"
            )
        }
        let claude = ClaudeUsage(
            fiveHourUtilization: f.fiveH,
            fiveHourResetsAt:    now.addingTimeInterval(TimeInterval(f.resetSecs)),
            sevenDayUtilization: f.sevenD,
            sevenDayResetsAt:    now.addingTimeInterval(TimeInterval(f.weeklyResetDays * 86400)),
            extraUsage:          extra,
            bonusUsage:          bonus,
            fetchedAt:           now
        )

        target.applyDemoFrame(claude: claude, codex: target.codexUsage,
                              claudeLoading: false,
                              codexLoading: target.isCodexLoading,
                              codexAutoReload: target.codexAutoReload)

        if claudeIndex < claudeFrames.count {
            scheduleNextClaude()
        }
    }

    // MARK: Codex advancement

    private func scheduleNextCodex() {
        guard codexIndex < codexFrames.count else { return }
        // A frame's tick is how long it stays on screen; the frame just
        // shown is codexIndex - 1. The final frame schedules nothing, so
        // it is held indefinitely.
        let base = codexFrames[codexIndex - 1].tick
        var duration = base * Double.random(in: 0.75...1.25)
        if codexIndex == 1 { duration += startHold }  // hold on the opening frame
        codexTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.applyNextCodexFrame() }
        }
    }

    private func applyNextCodexFrame() {
        guard codexIndex < codexFrames.count, let target else { return }
        let f = codexFrames[codexIndex]
        codexIndex += 1

        let now = Date.now
        let autoReload = codexAutoReloadFrames[codexIndex - 1]
        let balance    = codexBalance[codexIndex - 1] ?? 197.18
        // Spend-this-month is the cumulative drain from the opening balance;
        // the frame-21 auto-reload adds purchased credits, not spend.
        let reloaded: Double = codexIndex - 1 >= 21 ? 250 : 0
        let spent = 197.18 + reloaded - balance
        let codex = CodexUsage(
            weeklyUsedPercent:       Int(f.sevenD.rounded()),
            weeklyResetAt:           now.addingTimeInterval(TimeInterval(f.weeklyResetDays * 86400)),
            weeklyResetAfterSeconds: f.weeklyResetDays * 86400,
            hourlyUsedPercent:       Int(f.fiveH.rounded()),
            hourlyResetAt:           now.addingTimeInterval(TimeInterval(f.resetSecs)),
            hourlyResetAfterSeconds: f.resetSecs,
            hourlyWindowSeconds:     18000,
            limitReached:            f.fiveH >= 100,
            allowed:                 f.fiveH < 100,
            planType:                "plus",
            creditBalance:           balance,
            bonusCreditsSpentThisMonth: spent > 1 ? spent : nil,
            approxLocalMessages:     nil,
            approxCloudMessages:     nil,
            fetchedAt:               now
        )

        target.applyDemoFrame(claude: target.claudeUsage, codex: codex,
                              claudeLoading: target.isClaudeLoading,
                              codexLoading: false,
                              codexAutoReload: autoReload)

        // Mirror production: evaluate top-up notification for each simulated refresh
        Task {
            await NotificationManager.shared.evaluateTopUp(
                currentBalance: balance,
                autoReload: autoReload,
                prefs: target.settings.notifications
            )
        }

        if codexIndex < codexFrames.count {
            scheduleNextCodex()
        }
    }
}

#endif

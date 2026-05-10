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

    // MARK: - Claude timeline  (heavier user — faster cycling, 7d climbs to 100%)
    //
    // Tick durations ~1.4–2.2s. Four full 5h cycles.
    // Frame 0 is applied immediately on open — no loading state.

    // MARK: - Claude timeline  (heavier user — faster cycling, 7d climbs to 100%)
    //
    // Base ticks: normal 0.5s · amber 0.6s · red 0.7s · reset 0.3s → ~14s total.
    // ±25% jitter applied in scheduleNextClaude for a natural feel.

    private let claudeFrames: [ServiceFrame] = [
        // Cycle 1: 0 → limit → reset  (7d: 0 → 14%)
        .init(fiveH:   5, sevenD:   2, resetSecs: 15000, weeklyResetDays: 5, tick: 0.5),
        .init(fiveH:  25, sevenD:   5, resetSecs: 12600, weeklyResetDays: 5, tick: 0.5),
        .init(fiveH:  52, sevenD:   8, resetSecs:  9000, weeklyResetDays: 5, tick: 0.5),
        .init(fiveH:  75, sevenD:  11, resetSecs:  4500, weeklyResetDays: 5, tick: 0.5),
        .init(fiveH:  88, sevenD:  12, resetSecs:  1800, weeklyResetDays: 5, tick: 0.6), // amber
        .init(fiveH:  96, sevenD:  13, resetSecs:   480, weeklyResetDays: 5, tick: 0.5),
        .init(fiveH: 100, sevenD:  13, resetSecs: 15120, weeklyResetDays: 5, tick: 0.7), // red
        .init(fiveH:   0, sevenD:  14, resetSecs: 18000, weeklyResetDays: 5, tick: 0.3), // reset

        // Cycle 2: 7d climbs to ~35%
        .init(fiveH:  14, sevenD:  20, resetSecs: 16200, weeklyResetDays: 4, tick: 0.5),
        .init(fiveH:  38, sevenD:  24, resetSecs: 13200, weeklyResetDays: 4, tick: 0.5),
        .init(fiveH:  62, sevenD:  28, resetSecs: 10200, weeklyResetDays: 4, tick: 0.5),
        .init(fiveH:  85, sevenD:  31, resetSecs:  2700, weeklyResetDays: 4, tick: 0.6), // amber
        .init(fiveH:  94, sevenD:  32, resetSecs:   540, weeklyResetDays: 4, tick: 0.5),
        .init(fiveH: 100, sevenD:  33, resetSecs: 15480, weeklyResetDays: 4, tick: 0.7), // red
        .init(fiveH:   0, sevenD:  35, resetSecs: 18000, weeklyResetDays: 4, tick: 0.3),

        // Cycle 3: 7d climbs to ~66%
        .init(fiveH:  18, sevenD:  46, resetSecs: 15900, weeklyResetDays: 3, tick: 0.5),
        .init(fiveH:  45, sevenD:  53, resetSecs: 12000, weeklyResetDays: 3, tick: 0.5),
        .init(fiveH:  72, sevenD:  59, resetSecs:  8400, weeklyResetDays: 3, tick: 0.5),
        .init(fiveH:  87, sevenD:  62, resetSecs:  2100, weeklyResetDays: 3, tick: 0.6), // amber
        .init(fiveH: 100, sevenD:  64, resetSecs: 15900, weeklyResetDays: 3, tick: 0.7), // red
        .init(fiveH:   0, sevenD:  66, resetSecs: 18000, weeklyResetDays: 3, tick: 0.3),

        // Cycle 4: 7d hits amber (≥ 85%), budget strip escalates
        .init(fiveH:  22, sevenD:  73, resetSecs: 14400, weeklyResetDays: 2, tick: 0.5),
        .init(fiveH:  48, sevenD:  79, resetSecs: 11400, weeklyResetDays: 2, tick: 0.5),
        .init(fiveH:  70, sevenD:  85, resetSecs:  8400, weeklyResetDays: 2, tick: 0.6), // 7d amber
        .init(fiveH:  87, sevenD:  88, resetSecs:  2700, weeklyResetDays: 2, tick: 0.6), // both amber
        .init(fiveH: 100, sevenD:  90, resetSecs: 16200, weeklyResetDays: 2, tick: 0.7), // red
        .init(fiveH:   0, sevenD:  92, resetSecs: 18000, weeklyResetDays: 2, tick: 0.3),

        // Final: Claude 7d → 100%
        .init(fiveH:  24, sevenD:  96, resetSecs: 13800, weeklyResetDays: 1, tick: 0.6),
        // FINAL FRAME — timer halts after this
        .init(fiveH:  36, sevenD: 100, resetSecs: 11400, weeklyResetDays: 1, tick: 86400),
    ]

    // MARK: - Codex timeline  (lighter user — slower cycling, 7d climbs to ~80%)
    //
    // Base ticks: normal 0.5s · amber 0.6s · red 0.7s · reset 0.3s → ~14s total.
    // ±25% jitter applied in scheduleNextCodex for a natural feel.

    private let codexFrames: [ServiceFrame] = [
        // Cycle 1: slow fill — 0 → limit → reset  (7d: 0 → 13%)
        .init(fiveH:   4, sevenD:   1, resetSecs: 15200, weeklyResetDays: 5, tick: 0.5),
        .init(fiveH:  16, sevenD:   3, resetSecs: 13800, weeklyResetDays: 5, tick: 0.5),
        .init(fiveH:  34, sevenD:   6, resetSecs: 11400, weeklyResetDays: 5, tick: 0.5),
        .init(fiveH:  55, sevenD:   8, resetSecs:  8100, weeklyResetDays: 5, tick: 0.5),
        .init(fiveH:  74, sevenD:  10, resetSecs:  4500, weeklyResetDays: 5, tick: 0.5),
        .init(fiveH:  86, sevenD:  11, resetSecs:  1980, weeklyResetDays: 5, tick: 0.6), // amber
        .init(fiveH:  94, sevenD:  12, resetSecs:   600, weeklyResetDays: 5, tick: 0.5),
        .init(fiveH: 100, sevenD:  12, resetSecs: 15360, weeklyResetDays: 5, tick: 0.7), // red
        .init(fiveH:   0, sevenD:  13, resetSecs: 18000, weeklyResetDays: 5, tick: 0.3),

        // Cycle 2: 7d climbs to ~30%
        .init(fiveH:   9, sevenD:  18, resetSecs: 16200, weeklyResetDays: 4, tick: 0.5),
        .init(fiveH:  26, sevenD:  22, resetSecs: 13500, weeklyResetDays: 4, tick: 0.5),
        .init(fiveH:  48, sevenD:  25, resetSecs: 10800, weeklyResetDays: 4, tick: 0.5),
        .init(fiveH:  68, sevenD:  27, resetSecs:  7200, weeklyResetDays: 4, tick: 0.5),
        .init(fiveH:  82, sevenD:  29, resetSecs:  3060, weeklyResetDays: 4, tick: 0.6), // amber
        .init(fiveH:  96, sevenD:  30, resetSecs:   360, weeklyResetDays: 4, tick: 0.5),
        .init(fiveH: 100, sevenD:  30, resetSecs: 15600, weeklyResetDays: 4, tick: 0.7), // red
        .init(fiveH:   0, sevenD:  32, resetSecs: 18000, weeklyResetDays: 4, tick: 0.3),

        // Cycle 3: 7d climbs to ~62%
        .init(fiveH:  11, sevenD:  42, resetSecs: 15600, weeklyResetDays: 3, tick: 0.5),
        .init(fiveH:  30, sevenD:  48, resetSecs: 13200, weeklyResetDays: 3, tick: 0.5),
        .init(fiveH:  52, sevenD:  54, resetSecs:  9900, weeklyResetDays: 3, tick: 0.5),
        .init(fiveH:  74, sevenD:  58, resetSecs:  5400, weeklyResetDays: 3, tick: 0.5),
        .init(fiveH:  86, sevenD:  60, resetSecs:  2160, weeklyResetDays: 3, tick: 0.6), // amber
        .init(fiveH:  97, sevenD:  61, resetSecs:   300, weeklyResetDays: 3, tick: 0.5),
        .init(fiveH: 100, sevenD:  62, resetSecs: 16200, weeklyResetDays: 3, tick: 0.7), // red
        .init(fiveH:   0, sevenD:  63, resetSecs: 18000, weeklyResetDays: 3, tick: 0.3),

        // Final approach: Codex 7d → 80%
        .init(fiveH:  14, sevenD:  70, resetSecs: 15000, weeklyResetDays: 2, tick: 0.6),
        .init(fiveH:  22, sevenD:  76, resetSecs: 12600, weeklyResetDays: 2, tick: 0.6),
        // FINAL FRAME — timer halts after this
        .init(fiveH:  28, sevenD:  80, resetSecs: 11700, weeklyResetDays: 2, tick: 86400),
    ]

    // MARK: - Extra-usage progression (mirrors Claude timeline cycle indices)
    //
    // Cycles 1–2: no extra usage (Pro plan, strip hidden).
    // Cycle 3 onwards: Max plan, extra usage climbs from ~55% → ~92%,
    // triggering the budget strip at ≥ 70% and escalating to red at ≥ 85%.

    // MARK: - Codex balance progression
    //
    // Drains gradually so the demo also showcases the credits row's
    // amber (< $20) and red (< $5) treatment alongside the Claude strip.

    private let codexBalance: [Int: Double] = {
        var map: [Int: Double] = [:]
        // Cycles 1–2: healthy balance, slowly drawing down
        for i in 0...16   { map[i] = 197.18 - Double(i) * 4 }   // 197 → 133
        // Cycle 3: still normal but visibly dropping
        for i in 17...20  { map[i] = 90 - Double(i - 17) * 18 } // 90 → 36
        // Final approach: amber territory
        map[21] = 18
        map[22] = 11
        // Last frames: red
        map[23] = 6
        map[24] = 3
        map[25] = 1
        map[26] = 0
        map[27] = 0
        return map
    }()

    private let claudeExtraUsage: [Int: ClaudeUsage.ExtraUsage] = {
        var map: [Int: ClaudeUsage.ExtraUsage] = [:]
        // Cycle 3 starts at frame index 15 — moderate usage, below threshold
        for i in 15...19 { map[i] = .init(isEnabled: true, monthlyLimit: 2000, usedCredits: Double(i - 15) * 55 + 1100, utilization: Double(i - 15) * 3.5 + 55) }
        // Cycle 4: strip appears (≥ 70%) and climbs toward red (≥ 85%)
        for i in 20...25 { map[i] = .init(isEnabled: true, monthlyLimit: 2000, usedCredits: Double(i - 20) * 60 + 1400, utilization: Double(i - 20) * 5 + 70) }
        // Final frames: clearly in the red zone
        map[26] = .init(isEnabled: true, monthlyLimit: 2000, usedCredits: 1840, utilization: 92)
        map[27] = .init(isEnabled: true, monthlyLimit: 2000, usedCredits: 1860, utilization: 93)
        return map
    }()

    // MARK: - State

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
        let base = claudeFrames[claudeIndex].tick
        let duration = base < 1 ? base * Double.random(in: 0.75...1.25) : base
        claudeTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.applyNextClaudeFrame() }
        }
    }

    private func applyNextClaudeFrame() {
        guard claudeIndex < claudeFrames.count, let target else { return }
        let f = claudeFrames[claudeIndex]
        claudeIndex += 1

        let now = Date.now
        let claude = ClaudeUsage(
            fiveHourUtilization: f.fiveH,
            fiveHourResetsAt:    now.addingTimeInterval(TimeInterval(f.resetSecs)),
            sevenDayUtilization: f.sevenD,
            sevenDayResetsAt:    now.addingTimeInterval(TimeInterval(f.weeklyResetDays * 86400)),
            extraUsage:          claudeExtraUsage[claudeIndex - 1],
            fetchedAt:           now
        )

        target.applyDemoFrame(claude: claude, codex: target.codexUsage,
                              claudeLoading: false,
                              codexLoading: target.isCodexLoading)

        if claudeIndex < claudeFrames.count {
            scheduleNextClaude()
        }
    }

    // MARK: Codex advancement

    private func scheduleNextCodex() {
        guard codexIndex < codexFrames.count else { return }
        let base = codexFrames[codexIndex].tick
        let duration = base < 1 ? base * Double.random(in: 0.75...1.25) : base
        codexTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.applyNextCodexFrame() }
        }
    }

    private func applyNextCodexFrame() {
        guard codexIndex < codexFrames.count, let target else { return }
        let f = codexFrames[codexIndex]
        codexIndex += 1

        let now = Date.now
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
            creditBalance:           codexBalance[codexIndex - 1] ?? 197.18,
            approxLocalMessages:     nil,
            approxCloudMessages:     nil,
            fetchedAt:               now
        )

        target.applyDemoFrame(claude: target.claudeUsage, codex: codex,
                              claudeLoading: target.isClaudeLoading,
                              codexLoading: false)

        if codexIndex < codexFrames.count {
            scheduleNextCodex()
        }
    }
}

#endif

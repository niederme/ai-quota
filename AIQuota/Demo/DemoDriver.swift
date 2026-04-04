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

    private let claudeFrames: [ServiceFrame] = [
        // Cycle 1: 0 → limit → reset  (7d: 0 → 14%)
        .init(fiveH:   5, sevenD:   2, resetSecs: 15000, weeklyResetDays: 5, tick: 1.4),
        .init(fiveH:  25, sevenD:   5, resetSecs: 12600, weeklyResetDays: 5, tick: 1.4),
        .init(fiveH:  52, sevenD:   8, resetSecs:  9000, weeklyResetDays: 5, tick: 1.4),
        .init(fiveH:  75, sevenD:  11, resetSecs:  4500, weeklyResetDays: 5, tick: 1.4),
        .init(fiveH:  88, sevenD:  12, resetSecs:  1800, weeklyResetDays: 5, tick: 1.6), // amber
        .init(fiveH:  96, sevenD:  13, resetSecs:   480, weeklyResetDays: 5, tick: 1.4),
        .init(fiveH: 100, sevenD:  13, resetSecs: 15120, weeklyResetDays: 5, tick: 2.0), // red
        .init(fiveH:   0, sevenD:  14, resetSecs: 18000, weeklyResetDays: 5, tick: 0.8), // reset

        // Cycle 2: 7d climbs to ~35%
        .init(fiveH:  14, sevenD:  20, resetSecs: 16200, weeklyResetDays: 4, tick: 1.4),
        .init(fiveH:  38, sevenD:  24, resetSecs: 13200, weeklyResetDays: 4, tick: 1.4),
        .init(fiveH:  62, sevenD:  28, resetSecs: 10200, weeklyResetDays: 4, tick: 1.4),
        .init(fiveH:  85, sevenD:  31, resetSecs:  2700, weeklyResetDays: 4, tick: 1.6), // amber
        .init(fiveH:  94, sevenD:  32, resetSecs:   540, weeklyResetDays: 4, tick: 1.4),
        .init(fiveH: 100, sevenD:  33, resetSecs: 15480, weeklyResetDays: 4, tick: 2.0), // red
        .init(fiveH:   0, sevenD:  35, resetSecs: 18000, weeklyResetDays: 4, tick: 0.8),

        // Cycle 3: 7d climbs to ~66%
        .init(fiveH:  18, sevenD:  46, resetSecs: 15900, weeklyResetDays: 3, tick: 1.4),
        .init(fiveH:  45, sevenD:  53, resetSecs: 12000, weeklyResetDays: 3, tick: 1.4),
        .init(fiveH:  72, sevenD:  59, resetSecs:  8400, weeklyResetDays: 3, tick: 1.4),
        .init(fiveH:  87, sevenD:  62, resetSecs:  2100, weeklyResetDays: 3, tick: 1.6), // amber
        .init(fiveH: 100, sevenD:  64, resetSecs: 15900, weeklyResetDays: 3, tick: 2.0), // red
        .init(fiveH:   0, sevenD:  66, resetSecs: 18000, weeklyResetDays: 3, tick: 0.8),

        // Cycle 4: 7d hits amber on Claude (≥ 85%)
        .init(fiveH:  22, sevenD:  73, resetSecs: 14400, weeklyResetDays: 2, tick: 1.4),
        .init(fiveH:  48, sevenD:  79, resetSecs: 11400, weeklyResetDays: 2, tick: 1.4),
        .init(fiveH:  70, sevenD:  85, resetSecs:  8400, weeklyResetDays: 2, tick: 1.6), // 7d amber — caption appears
        .init(fiveH:  87, sevenD:  88, resetSecs:  2700, weeklyResetDays: 2, tick: 1.6), // both amber
        .init(fiveH: 100, sevenD:  90, resetSecs: 16200, weeklyResetDays: 2, tick: 2.0), // red
        .init(fiveH:   0, sevenD:  92, resetSecs: 18000, weeklyResetDays: 2, tick: 0.8),

        // Final: Claude 7d → 100%
        .init(fiveH:  24, sevenD:  96, resetSecs: 13800, weeklyResetDays: 1, tick: 1.6),
        // FINAL FRAME — timer halts after this
        .init(fiveH:  36, sevenD: 100, resetSecs: 11400, weeklyResetDays: 1, tick: 86400),
    ]

    // MARK: - Codex timeline  (lighter user — slower cycling, 7d climbs to ~80%)
    //
    // Tick durations ~2.0–2.6s. Three full 5h cycles.

    private let codexFrames: [ServiceFrame] = [
        // Cycle 1: slow fill — 0 → limit → reset  (7d: 0 → 13%)
        .init(fiveH:   4, sevenD:   1, resetSecs: 15200, weeklyResetDays: 5, tick: 2.0),
        .init(fiveH:  16, sevenD:   3, resetSecs: 13800, weeklyResetDays: 5, tick: 2.0),
        .init(fiveH:  34, sevenD:   6, resetSecs: 11400, weeklyResetDays: 5, tick: 2.0),
        .init(fiveH:  55, sevenD:   8, resetSecs:  8100, weeklyResetDays: 5, tick: 2.0),
        .init(fiveH:  74, sevenD:  10, resetSecs:  4500, weeklyResetDays: 5, tick: 2.0),
        .init(fiveH:  86, sevenD:  11, resetSecs:  1980, weeklyResetDays: 5, tick: 2.2), // amber
        .init(fiveH:  94, sevenD:  12, resetSecs:   600, weeklyResetDays: 5, tick: 2.0),
        .init(fiveH: 100, sevenD:  12, resetSecs: 15360, weeklyResetDays: 5, tick: 2.6), // red
        .init(fiveH:   0, sevenD:  13, resetSecs: 18000, weeklyResetDays: 5, tick: 1.0),

        // Cycle 2: 7d climbs to ~30%
        .init(fiveH:   9, sevenD:  18, resetSecs: 16200, weeklyResetDays: 4, tick: 2.0),
        .init(fiveH:  26, sevenD:  22, resetSecs: 13500, weeklyResetDays: 4, tick: 2.0),
        .init(fiveH:  48, sevenD:  25, resetSecs: 10800, weeklyResetDays: 4, tick: 2.0),
        .init(fiveH:  68, sevenD:  27, resetSecs:  7200, weeklyResetDays: 4, tick: 2.0),
        .init(fiveH:  82, sevenD:  29, resetSecs:  3060, weeklyResetDays: 4, tick: 2.2), // amber
        .init(fiveH:  96, sevenD:  30, resetSecs:   360, weeklyResetDays: 4, tick: 2.0),
        .init(fiveH: 100, sevenD:  30, resetSecs: 15600, weeklyResetDays: 4, tick: 2.6), // red
        .init(fiveH:   0, sevenD:  32, resetSecs: 18000, weeklyResetDays: 4, tick: 1.0),

        // Cycle 3: 7d climbs to ~62%
        .init(fiveH:  11, sevenD:  42, resetSecs: 15600, weeklyResetDays: 3, tick: 2.0),
        .init(fiveH:  30, sevenD:  48, resetSecs: 13200, weeklyResetDays: 3, tick: 2.0),
        .init(fiveH:  52, sevenD:  54, resetSecs:  9900, weeklyResetDays: 3, tick: 2.0),
        .init(fiveH:  74, sevenD:  58, resetSecs:  5400, weeklyResetDays: 3, tick: 2.0),
        .init(fiveH:  86, sevenD:  60, resetSecs:  2160, weeklyResetDays: 3, tick: 2.2), // amber
        .init(fiveH:  97, sevenD:  61, resetSecs:   300, weeklyResetDays: 3, tick: 2.0),
        .init(fiveH: 100, sevenD:  62, resetSecs: 16200, weeklyResetDays: 3, tick: 2.6), // red
        .init(fiveH:   0, sevenD:  63, resetSecs: 18000, weeklyResetDays: 3, tick: 1.0),

        // Final approach: Codex 7d → 80%
        .init(fiveH:  14, sevenD:  70, resetSecs: 15000, weeklyResetDays: 2, tick: 2.2),
        .init(fiveH:  22, sevenD:  76, resetSecs: 12600, weeklyResetDays: 2, tick: 2.2),
        // FINAL FRAME — timer halts after this
        .init(fiveH:  28, sevenD:  80, resetSecs: 11700, weeklyResetDays: 2, tick: 86400),
    ]

    // MARK: - State

    private weak var target: QuotaViewModel?

    private var claudeIndex = 0
    private var codexIndex  = 0
    private var claudeTimer: Timer?
    private var codexTimer:  Timer?

    private var hasStarted = false

    // MARK: - Public API

    /// Call once from `AIQuotaApp`. Idempotent — safe to call from `.task`.
    /// The animation runs continuously in the background; opening/closing
    /// the popover has no effect on playback.
    func startIfNeeded(driving viewModel: QuotaViewModel) {
        guard !hasStarted else { return }
        hasStarted = true
        target = viewModel
        reset()
    }

    // MARK: - Private

    private func reset() {
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

    // MARK: Claude advancement

    private func scheduleNextClaude() {
        guard claudeIndex < claudeFrames.count else { return }
        let duration = claudeFrames[claudeIndex].tick
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
            extraUsage:          nil,
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
        let duration = codexFrames[codexIndex].tick
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
            creditBalance:           197.18,
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

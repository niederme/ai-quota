import Foundation
import AppKit
import AIQuotaKit

// MARK: - Demo keyframe engine (DEMO_MODE builds only)

#if DEMO_MODE

/// Drives a `QuotaViewModel` through a scripted timelapse of all usage states.
/// Activate by calling `startIfNeeded(driving:)` once. Resets automatically
/// whenever the AIQuota menu bar popover opens.
@MainActor
final class DemoDriver {

    // MARK: - Frame definition

    private struct DemoFrame {
        /// Claude 5-hour utilization (0–100). `nil` = loading state.
        var claudeFiveH: Double?
        /// Claude 7-day utilization (0–100).
        var claudeSevenD: Double
        /// Seconds until Claude's 5h window resets (used for reset countdown text).
        var claude5hResetSecs: Int
        /// Days until Claude's 7d window resets.
        var claude7dResetDays: Int
        /// Codex 5-hour used percent (0–100). `nil` = loading state.
        var codexFiveH: Int?
        /// Codex 7-day used percent (0–100).
        var codexSevenD: Int
        /// Seconds until Codex's 5h window resets.
        var codex5hResetSecs: Int
        /// Days until Codex's 7d window resets.
        var codex7dResetDays: Int
        /// How long to hold this frame before advancing.
        var tickDuration: Double
    }

    // MARK: - Scripted timeline
    //
    // Four 5h cycles while 7d climbs. Colour transitions:
    //   < 85%  → purple (normal)
    //   ≥ 85%  → amber
    //   ≥ 100% → red + "5h limit reached" / "7d limit reached"
    // The final frame freezes: Claude 7d = 100%, Codex 7d = 80%.

    private let frames: [DemoFrame] = [
        // ── Loading (nil = spinner) ────────────────────────────────────────
        .init(claudeFiveH: nil, claudeSevenD: 0,   claude5hResetSecs: 18000, claude7dResetDays: 5, codexFiveH: nil, codexSevenD: 0,  codex5hResetSecs: 18000, codex7dResetDays: 5, tickDuration: 0.8),
        .init(claudeFiveH: nil, claudeSevenD: 0,   claude5hResetSecs: 18000, claude7dResetDays: 5, codexFiveH: nil, codexSevenD: 0,  codex5hResetSecs: 18000, codex7dResetDays: 5, tickDuration: 0.7),

        // ── Cycle 1: 0 → limit → reset (7d 0 → 14%) ──────────────────────
        .init(claudeFiveH:  5,  claudeSevenD:  2,  claude5hResetSecs: 15000, claude7dResetDays: 5, codexFiveH:  4,  codexSevenD:  1,  codex5hResetSecs: 15200, codex7dResetDays: 5, tickDuration: 0.5),
        .init(claudeFiveH: 18,  claudeSevenD:  4,  claude5hResetSecs: 13500, claude7dResetDays: 5, codexFiveH: 14,  codexSevenD:  3,  codex5hResetSecs: 13800, codex7dResetDays: 5, tickDuration: 0.5),
        .init(claudeFiveH: 38,  claudeSevenD:  6,  claude5hResetSecs: 11000, claude7dResetDays: 5, codexFiveH: 30,  codexSevenD:  5,  codex5hResetSecs: 11200, codex7dResetDays: 5, tickDuration: 0.5),
        .init(claudeFiveH: 62,  claudeSevenD:  9,  claude5hResetSecs:  7200, claude7dResetDays: 5, codexFiveH: 52,  codexSevenD:  7,  codex5hResetSecs:  7500, codex7dResetDays: 5, tickDuration: 0.5),
        .init(claudeFiveH: 80,  claudeSevenD: 11,  claude5hResetSecs:  3600, claude7dResetDays: 5, codexFiveH: 72,  codexSevenD:  9,  codex5hResetSecs:  3800, codex7dResetDays: 5, tickDuration: 0.5),
        // amber (≥ 85)
        .init(claudeFiveH: 88,  claudeSevenD: 12,  claude5hResetSecs:  1800, claude7dResetDays: 5, codexFiveH: 85,  codexSevenD: 10,  codex5hResetSecs:  1900, codex7dResetDays: 5, tickDuration: 0.5),
        .init(claudeFiveH: 95,  claudeSevenD: 13,  claude5hResetSecs:   600, claude7dResetDays: 5, codexFiveH: 92,  codexSevenD: 11,  codex5hResetSecs:   700, codex7dResetDays: 5, tickDuration: 0.5),
        // red / limit reached
        .init(claudeFiveH: 100, claudeSevenD: 13,  claude5hResetSecs: 15120, claude7dResetDays: 5, codexFiveH: 100, codexSevenD: 11,  codex5hResetSecs: 15360, codex7dResetDays: 5, tickDuration: 0.7),
        // reset (snap to 0)
        .init(claudeFiveH:  0,  claudeSevenD: 14,  claude5hResetSecs: 18000, claude7dResetDays: 5, codexFiveH:  0,  codexSevenD: 12,  codex5hResetSecs: 18000, codex7dResetDays: 5, tickDuration: 0.35),

        // ── Cycle 2: 7d climbs to ~35% ────────────────────────────────────
        .init(claudeFiveH: 12,  claudeSevenD: 20,  claude5hResetSecs: 15900, claude7dResetDays: 4, codexFiveH:  9,  codexSevenD: 17,  codex5hResetSecs: 16100, codex7dResetDays: 4, tickDuration: 0.5),
        .init(claudeFiveH: 35,  claudeSevenD: 24,  claude5hResetSecs: 13200, claude7dResetDays: 4, codexFiveH: 28,  codexSevenD: 21,  codex5hResetSecs: 13500, codex7dResetDays: 4, tickDuration: 0.5),
        .init(claudeFiveH: 58,  claudeSevenD: 28,  claude5hResetSecs: 10500, claude7dResetDays: 4, codexFiveH: 48,  codexSevenD: 24,  codex5hResetSecs: 10800, codex7dResetDays: 4, tickDuration: 0.5),
        .init(claudeFiveH: 79,  claudeSevenD: 31,  claude5hResetSecs:  3900, claude7dResetDays: 4, codexFiveH: 70,  codexSevenD: 28,  codex5hResetSecs:  4100, codex7dResetDays: 4, tickDuration: 0.5),
        .init(claudeFiveH: 87,  claudeSevenD: 32,  claude5hResetSecs:  2100, claude7dResetDays: 4, codexFiveH: 83,  codexSevenD: 29,  codex5hResetSecs:  2200, codex7dResetDays: 4, tickDuration: 0.5),
        .init(claudeFiveH: 100, claudeSevenD: 33,  claude5hResetSecs: 15480, claude7dResetDays: 4, codexFiveH: 100, codexSevenD: 30,  codex5hResetSecs: 15600, codex7dResetDays: 4, tickDuration: 0.7),
        .init(claudeFiveH:  0,  claudeSevenD: 35,  claude5hResetSecs: 18000, claude7dResetDays: 4, codexFiveH:  0,  codexSevenD: 32,  codex5hResetSecs: 18000, codex7dResetDays: 4, tickDuration: 0.35),

        // ── Cycle 3: 7d climbs to ~66% ────────────────────────────────────
        .init(claudeFiveH: 15,  claudeSevenD: 45,  claude5hResetSecs: 15300, claude7dResetDays: 3, codexFiveH: 11,  codexSevenD: 41,  codex5hResetSecs: 15500, codex7dResetDays: 3, tickDuration: 0.5),
        .init(claudeFiveH: 42,  claudeSevenD: 52,  claude5hResetSecs: 12600, claude7dResetDays: 3, codexFiveH: 33,  codexSevenD: 47,  codex5hResetSecs: 12900, codex7dResetDays: 3, tickDuration: 0.5),
        .init(claudeFiveH: 70,  claudeSevenD: 58,  claude5hResetSecs:  9000, claude7dResetDays: 3, codexFiveH: 58,  codexSevenD: 54,  codex5hResetSecs:  9300, codex7dResetDays: 3, tickDuration: 0.5),
        .init(claudeFiveH: 86,  claudeSevenD: 62,  claude5hResetSecs:  2400, claude7dResetDays: 3, codexFiveH: 79,  codexSevenD: 58,  codex5hResetSecs:  2600, codex7dResetDays: 3, tickDuration: 0.5),
        .init(claudeFiveH: 100, claudeSevenD: 64,  claude5hResetSecs: 15900, claude7dResetDays: 3, codexFiveH: 96,  codexSevenD: 60,  codex5hResetSecs: 16200, codex7dResetDays: 3, tickDuration: 0.7),
        .init(claudeFiveH:  0,  claudeSevenD: 66,  claude5hResetSecs: 18000, claude7dResetDays: 3, codexFiveH:  0,  codexSevenD: 62,  codex5hResetSecs: 18000, codex7dResetDays: 3, tickDuration: 0.35),

        // ── Cycle 4: 7d hits amber on Claude (≥ 85%), Codex ~80% ──────────
        .init(claudeFiveH: 20,  claudeSevenD: 73,  claude5hResetSecs: 14400, claude7dResetDays: 2, codexFiveH: 14,  codexSevenD: 68,  codex5hResetSecs: 14700, codex7dResetDays: 2, tickDuration: 0.5),
        .init(claudeFiveH: 45,  claudeSevenD: 79,  claude5hResetSecs: 12000, claude7dResetDays: 2, codexFiveH: 35,  codexSevenD: 74,  codex5hResetSecs: 12300, codex7dResetDays: 2, tickDuration: 0.5),
        // Claude 7d hits amber — "7d Resets Xd Xh" caption appears below gauge
        .init(claudeFiveH: 68,  claudeSevenD: 85,  claude5hResetSecs:  9600, claude7dResetDays: 2, codexFiveH: 55,  codexSevenD: 79,  codex5hResetSecs:  9900, codex7dResetDays: 2, tickDuration: 0.5),
        .init(claudeFiveH: 86,  claudeSevenD: 88,  claude5hResetSecs:  3000, claude7dResetDays: 2, codexFiveH: 74,  codexSevenD: 79,  codex5hResetSecs:  3200, codex7dResetDays: 2, tickDuration: 0.5),
        .init(claudeFiveH: 100, claudeSevenD: 90,  claude5hResetSecs: 16200, claude7dResetDays: 2, codexFiveH: 90,  codexSevenD: 80,  codex5hResetSecs: 16500, codex7dResetDays: 2, tickDuration: 0.7),
        .init(claudeFiveH:  0,  claudeSevenD: 92,  claude5hResetSecs: 18000, claude7dResetDays: 2, codexFiveH:  0,  codexSevenD: 80,  codex5hResetSecs: 18000, codex7dResetDays: 2, tickDuration: 0.35),

        // ── Final approach: Claude 7d → 100% ──────────────────────────────
        .init(claudeFiveH: 22,  claudeSevenD: 96,  claude5hResetSecs: 13800, claude7dResetDays: 1, codexFiveH: 16,  codexSevenD: 80,  codex5hResetSecs: 14100, codex7dResetDays: 1, tickDuration: 0.5),
        // FINAL: Claude 7d = 100% (limit reached, red), Codex 7d = 80%.
        // After applying this frame, frameIndex == frames.count — timer halts.
        .init(claudeFiveH: 35,  claudeSevenD: 100, claude5hResetSecs: 11400, claude7dResetDays: 1, codexFiveH: 25,  codexSevenD: 80,  codex5hResetSecs: 11700, codex7dResetDays: 1, tickDuration: 86400),
    ]

    // MARK: - State

    private weak var target: QuotaViewModel?
    private var frameIndex = 0
    private var timer: Timer?
    private var popoverObserver: NSObjectProtocol?
    private var hasStarted = false

    // MARK: - Public API

    /// Call once from `AIQuotaApp`. Idempotent — safe to call from `.task`.
    func startIfNeeded(driving viewModel: QuotaViewModel) {
        guard !hasStarted else { return }
        hasStarted = true
        target = viewModel

        // Reset whenever the popover opens (close + reopen = restart).
        popoverObserver = NotificationCenter.default.addObserver(
            forName: NSPopover.willShowNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reset() }
        }

        reset()
    }

    // MARK: - Private

    private func reset() {
        timer?.invalidate()
        timer = nil
        frameIndex = 0
        target?.prepareForDemo()
        scheduleNext()
    }

    private func scheduleNext() {
        guard frameIndex < frames.count else { return }
        let duration = frames[frameIndex].tickDuration
        timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.applyCurrentFrame() }
        }
    }

    private func applyCurrentFrame() {
        guard frameIndex < frames.count, let target else { return }
        let f = frames[frameIndex]
        frameIndex += 1

        let now = Date.now
        let isLoading = f.claudeFiveH == nil

        let claude: ClaudeUsage? = isLoading ? nil : ClaudeUsage(
            fiveHourUtilization: f.claudeFiveH!,
            fiveHourResetsAt:    now.addingTimeInterval(TimeInterval(f.claude5hResetSecs)),
            sevenDayUtilization: f.claudeSevenD,
            sevenDayResetsAt:    now.addingTimeInterval(TimeInterval(f.claude7dResetDays * 86400)),
            extraUsage:          nil,
            fetchedAt:           now
        )

        let codex: CodexUsage? = isLoading ? nil : CodexUsage(
            weeklyUsedPercent:       f.codexSevenD,
            weeklyResetAt:           now.addingTimeInterval(TimeInterval(f.codex7dResetDays * 86400)),
            weeklyResetAfterSeconds: f.codex7dResetDays * 86400,
            hourlyUsedPercent:       f.codexFiveH!,
            hourlyResetAt:           now.addingTimeInterval(TimeInterval(f.codex5hResetSecs)),
            hourlyResetAfterSeconds: f.codex5hResetSecs,
            hourlyWindowSeconds:     18000,
            limitReached:            f.codexFiveH! >= 100,
            allowed:                 f.codexFiveH! < 100,
            planType:                "plus",
            creditBalance:           197.18,
            approxLocalMessages:     nil,
            approxCloudMessages:     nil,
            fetchedAt:               now
        )

        target.applyDemoFrame(claude: claude, codex: codex,
                              claudeLoading: isLoading, codexLoading: isLoading)

        // After applying the last frame, frameIndex == frames.count so
        // scheduleNext() is a no-op — the timer halts cleanly.
        if frameIndex < frames.count {
            scheduleNext()
        }
    }
}

#endif

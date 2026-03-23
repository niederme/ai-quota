import SwiftUI
import Sparkle
import AppKit
import AIQuotaKit

@main
struct AIQuotaApp: App {
    @State private var viewModel = QuotaViewModel()

    // Sparkle updater — must be held at app scope for its lifetime.
    // gentleDriverDelegate opts into polite (non-focus-stealing) update alerts,
    // which is required for dockless menu bar apps.
    private let gentleDriverDelegate = GentleSparkleDriverDelegate()
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: gentleDriverDelegate
        )
        // Silently check for a newer version on every launch.
        let updater = updaterController.updater
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            updater.checkForUpdatesInBackground()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(viewModel)
                .environment(UpdaterViewModel(updater: updaterController.updater))
        } label: {
            MenuBarIconView(
                usedPercent: menuBarUsedPercent,
                secondaryPercent: menuBarSecondaryPercent,
                limitReached: menuBarLimitReached,
                isLoading: viewModel.isLoading,
                worstPercent: menuBarWorstPercent
            )
        }
        .menuBarExtraStyle(.window)

        Window("Get Started", id: "onboarding") {
            OnboardingView()
                .environment(viewModel)
                .background(WindowVibrancyInstaller())
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Settings {
            SettingsView()
                .environment(viewModel)
                .environment(UpdaterViewModel(updater: updaterController.updater))
        }
    }

    // MARK: - Menu bar gauge selection

    /// Returns the gauge value for the service configured in settings.
    /// Falls back to whichever service is actually authenticated.
    private var menuBarUsedPercent: Int {
        switch resolvedMenuBarService {
        case .codex:  return viewModel.codexUsage?.hourlyUsedPercent ?? 0
        case .claude: return viewModel.claudeUsage?.usedPercent ?? 0
        }
    }

    /// 7-day consumption for the resolved service — drives the inner ring.
    private var menuBarSecondaryPercent: Int {
        switch resolvedMenuBarService {
        case .codex:  return viewModel.codexUsage?.weeklyUsedPercent ?? 0
        case .claude: return Int(viewModel.claudeUsage?.sevenDayUtilization.rounded() ?? 0)
        }
    }

    /// Worst single metric across all authenticated services — used to colour
    /// the menu bar rings regardless of which service's arcs are displayed.
    private var menuBarWorstPercent: Int {
        let codex  = [viewModel.codexUsage?.hourlyUsedPercent  ?? 0,
                      viewModel.codexUsage?.weeklyUsedPercent  ?? 0]
        let claude = [Int(viewModel.claudeUsage?.fiveHourUtilization.rounded() ?? 0),
                      Int(viewModel.claudeUsage?.sevenDayUtilization.rounded() ?? 0)]
        return (codex + claude).max() ?? 0
    }

    private var menuBarLimitReached: Bool {
        (viewModel.codexUsage?.limitReached ?? false) ||
        (viewModel.claudeUsage?.limitReached ?? false)
    }

    /// Respects `settings.menuBarService` but falls back gracefully.
    private var resolvedMenuBarService: ServiceType {
        let preferred = viewModel.settings.menuBarService
        switch preferred {
        case .codex:
            return viewModel.isCodexAuthenticated ? .codex
                 : viewModel.isClaudeAuthenticated ? .claude
                 : .codex
        case .claude:
            return viewModel.isClaudeAuthenticated ? .claude
                 : viewModel.isCodexAuthenticated ? .codex
                 : .codex
        }
    }
}

// MARK: - Sparkle gentle reminders delegate

/// Opts AIQuota into Sparkle's "gentle reminders" mode so scheduled update
/// alerts never steal focus from the user's active app. Required for dockless
/// menu bar apps per Sparkle documentation.
final class GentleSparkleDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }
}

// MARK: - Window vibrancy installer

/// Zero-size view that reaches up to the hosting NSWindow and enables
/// vibrancy + transparency so SwiftUI's .ultraThinMaterial fills the whole window.
private struct WindowVibrancyInstaller: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Defer so the window is attached by the time we walk the hierarchy
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            // Extend content view under the title bar so the material shows through
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            // Float above other apps so it's never lost behind them
            window.level = .floating
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}


import SwiftUI
import Sparkle
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
                limitReached: menuBarLimitReached,
                isLoading: viewModel.isLoading
            )
        }
        .menuBarExtraStyle(.window)

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

    private var menuBarLimitReached: Bool {
        switch resolvedMenuBarService {
        case .codex:  return viewModel.codexUsage?.limitReached ?? false
        case .claude: return viewModel.claudeUsage?.limitReached ?? false
        }
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

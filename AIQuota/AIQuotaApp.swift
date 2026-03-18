import SwiftUI
import Sparkle
import AIQuotaKit

@main
struct AIQuotaApp: App {
    @State private var viewModel = QuotaViewModel()

    // Sparkle updater — must be held at app scope for its lifetime
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    init() {
        // Silently check for a newer version on every launch.
        // checkForUpdatesInBackground() only prompts the user if a new version is found.
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
        case .codex:  return viewModel.codexUsage?.weeklyUsedPercent ?? 0
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

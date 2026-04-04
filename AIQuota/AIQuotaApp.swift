import SwiftUI
import Sparkle
import AppKit
import WidgetKit
import AIQuotaKit

@main
struct AIQuotaApp: App {
    @State private var viewModel: QuotaViewModel
    #if DEMO_MODE
    @State private var demoDriver: DemoDriver
    #endif

    // Sparkle updater — must be held at app scope for its lifetime.
    // gentleDriverDelegate opts into polite (non-focus-stealing) update alerts,
    // which is required for dockless menu bar apps.
    private let gentleDriverDelegate = GentleSparkleDriverDelegate()
    private let updaterController: SPUStandardUpdaterController

    init() {
        LegacyWebKitMigration.migrateIfNeeded(bundleIdentifier: "com.niederme.AIQuota")
        LegacyDefaultsMigration.migrateIfNeeded(bundleIdentifier: "com.niederme.AIQuota")
        LaunchServicesSync.repairIfNeeded()
        _viewModel = State(initialValue: QuotaViewModel())
        #if DEMO_MODE
        _demoDriver = State(initialValue: DemoDriver())
        #endif
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
        DispatchQueue.main.async {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(viewModel)
                .environment(UpdaterViewModel(updater: updaterController.updater))
                .task {
                    #if DEMO_MODE
                    demoDriver.startIfNeeded(driving: viewModel)
                    #endif
                }
        } label: {
            MenuBarIconView(
                usedPercent: menuBarUsedPercent,
                secondaryPercent: menuBarSecondaryPercent,
                limitReached: menuBarLimitReached,
                isLoading: viewModel.isLoading,
                worstPercent: menuBarStatusPercent
            )
            .onboardingLauncher(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)

        Window("Get Started", id: "onboarding") {
            OnboardingView()
                .environment(viewModel)
                .background(WindowVibrancyInstaller())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Settings {
            SettingsView()
                .environment(viewModel)
                .environment(UpdaterViewModel(updater: updaterController.updater))
        }
        .defaultSize(width: 500, height: 720)
        .windowResizability(.contentSize)
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

    /// Worst metric for the resolved service only — keeps the menu bar icon's
    /// warning colour aligned with the user's selected default service.
    private var menuBarStatusPercent: Int {
        switch resolvedMenuBarService {
        case .codex:
            return max(
                viewModel.codexUsage?.hourlyUsedPercent ?? 0,
                viewModel.codexUsage?.weeklyUsedPercent ?? 0
            )
        case .claude:
            return max(
                Int(viewModel.claudeUsage?.fiveHourUtilization.rounded() ?? 0),
                Int(viewModel.claudeUsage?.sevenDayUtilization.rounded() ?? 0)
            )
        }
    }

    private var menuBarLimitReached: Bool {
        switch resolvedMenuBarService {
        case .codex:
            return viewModel.codexUsage?.limitReached ?? false
        case .claude:
            return viewModel.claudeUsage?.limitReached ?? false
        }
    }

    /// Respects `settings.menuBarService` but falls back gracefully.
    private var resolvedMenuBarService: ServiceType {
        let preferred = viewModel.settings.menuBarService
        // Use preferred service if enrolled; otherwise fall back to any enrolled service.
        if viewModel.enrolledServices.contains(preferred) { return preferred }
        return viewModel.enrolledServices.first ?? preferred
    }
}

// MARK: - Sparkle gentle reminders delegate

/// Opts AIQuota into Sparkle's "gentle reminders" mode so scheduled update
/// alerts never steal focus from the user's active app. Required for dockless
/// menu bar apps per Sparkle documentation.
final class GentleSparkleDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }
}

// MARK: - Onboarding launcher

private struct OnboardingLauncherModifier: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    let viewModel: QuotaViewModel

    func body(content: Content) -> some View {
        content.task {
            // Brief pause so the SwiftUI scene graph is ready to open windows at launch.
            try? await Task.sleep(for: .milliseconds(200))
            if viewModel.shouldShowOnboarding {
                viewModel.markOnboardingTriggered()
                openWindow(id: "onboarding")
            }
        }
    }
}

private extension View {
    func onboardingLauncher(viewModel: QuotaViewModel) -> some View {
        modifier(OnboardingLauncherModifier(viewModel: viewModel))
    }
}

// MARK: - Window vibrancy installer

/// Zero-size view that reaches up to the hosting NSWindow and enables
/// vibrancy + transparency so SwiftUI's .thinMaterial fills the whole window.
private struct WindowVibrancyInstaller: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Defer past SwiftUI's own window-configuration pass so our overrides win
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            // Float above other apps so it's never lost behind them
            window.level = .floating
        }
    }
}

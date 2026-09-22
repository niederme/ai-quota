import SwiftUI
#if !APP_STORE
import Sparkle
#endif
import AppKit
import WidgetKit
import AIQuotaKit

@main
struct AIQuotaApp: App {
    @NSApplicationDelegateAdaptor(AnalyticsAppDelegate.self) private var analyticsDelegate
    @State private var viewModel: QuotaViewModel
    #if DEMO_MODE
    @State private var demoDriver: DemoDriver
    #endif

    // Sparkle updater — must be held at app scope for its lifetime.
    // Scheduled checks surface as a quiet badge in AIQuota. Sparkle's standard
    // window is shown only after the user chooses the update from the popover.
    private let updaterViewModel: UpdaterViewModel
    #if !APP_STORE
    private let gentleDriverDelegate: GentleSparkleDriverDelegate
    private let updaterController: SPUStandardUpdaterController
    #endif

    init() {
        #if !APP_STORE
        LegacyWebKitMigration.migrateIfNeeded(bundleIdentifier: "com.niederme.AIQuota")
        LegacyDefaultsMigration.migrateIfNeeded(bundleIdentifier: "com.niederme.AIQuota")
        LaunchServicesSync.repairIfNeeded()
        #endif
        _viewModel = State(initialValue: QuotaViewModel())
        #if DEMO_MODE
        _demoDriver = State(initialValue: DemoDriver())
        #endif
        let updaterViewModel = UpdaterViewModel()
        self.updaterViewModel = updaterViewModel
        #if !APP_STORE
        let gentleDriverDelegate = GentleSparkleDriverDelegate(updaterViewModel: updaterViewModel)
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: gentleDriverDelegate
        )
        updaterViewModel.connect(to: updaterController.updater)
        self.gentleDriverDelegate = gentleDriverDelegate
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-AIQuotaShowUpdateBadge") {
            updaterViewModel.noteAvailableUpdate(version: "1.9.25")
        }
        #endif
        // Silently check for a newer version on every launch.
        let updater = updaterController.updater
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            updater.checkForUpdatesInBackground()
        }
        #endif
        DispatchQueue.main.async {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(viewModel)
                .environment(updaterViewModel)
                .onAppear {
                    viewModel.recordDailyActiveIfNeeded()
                    // Demo builds never fetch real usage — a live refresh here
                    // would overwrite the scripted frames with actual data.
                    #if !DEMO_MODE
                    viewModel.refreshOnPopoverOpenIfNeeded()
                    #endif
                    let enabled = viewModel.settings.analyticsEnabled
                    let params = viewModel.analyticsContextParams
                    Task {
                        await AnalyticsClient.shared.send(
                            "popover_opened",
                            params: params,
                            enabled: enabled
                        )
                    }
                }
                #if DEMO_MODE
                // prepare must precede reset — .task would run after .onAppear,
                // leaving the driver targetless on the first (auto-opened) show.
                .onAppear {
                    demoDriver.prepare(for: viewModel)
                    demoDriver.reset()
                }
                .onDisappear { demoDriver.pause() }
                .background {
                    Button("") { demoDriver.reset() }
                        .keyboardShortcut("r", modifiers: .command)
                        .hidden()
                }
                #endif
        } label: {
            menuBarIcon
                .onboardingLauncher(viewModel: viewModel)
                #if DEMO_MODE
                .demoAutoOpen()
                #endif
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
                .environment(updaterViewModel)
        }
        .defaultSize(width: 500, height: 720)
        .windowResizability(.contentSize)
    }

    // MARK: - Menu bar gauge selection

    @ViewBuilder
    private var menuBarIcon: some View {
        if shouldShowBothMenuBarGauges {
            DoubleMenuBarIconView(
                left: menuBarGaugeInput(for: .codex),
                right: menuBarGaugeInput(for: .claude),
                showsUpdateBadge: updaterViewModel.availableUpdateVersion != nil
            )
        } else {
            MenuBarIconView(
                input: menuBarGaugeInput(for: resolvedMenuBarService),
                showsUpdateBadge: updaterViewModel.availableUpdateVersion != nil
            )
        }
    }

    private var shouldShowBothMenuBarGauges: Bool {
        viewModel.settings.menuBarDisplayMode == .both
            && viewModel.enrolledServices.contains(.codex)
            && viewModel.enrolledServices.contains(.claude)
    }

    private func menuBarGaugeInput(for service: ServiceType) -> MenuBarGaugeInput {
        switch service {
        case .codex:
            let used = viewModel.codexUsage?.hourlyUsedPercent ?? 0
            let secondary = viewModel.codexUsage?.weeklyUsedPercent ?? 0
            return MenuBarGaugeInput(
                usedPercent: used,
                secondaryPercent: secondary,
                limitReached: viewModel.codexUsage?.limitReached ?? false,
                isLoading: viewModel.isLoading,
                worstPercent: max(used, secondary)
            )
        case .claude:
            // Disconnected cached readings are shown only in the stale reconnect card.
            let usage = viewModel.isClaudeAuthenticated ? viewModel.claudeUsage : nil
            let used = usage?.usedPercent ?? 0
            let secondary = Int(usage?.sevenDayUtilization?.rounded() ?? 0)
            return MenuBarGaugeInput(
                usedPercent: used,
                secondaryPercent: secondary,
                limitReached: usage?.limitReached ?? false,
                isLoading: viewModel.isLoading,
                worstPercent: max(used, secondary)
            )
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
#if !APP_STORE
final class GentleSparkleDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    private let updaterViewModel: UpdaterViewModel

    init(updaterViewModel: UpdaterViewModel) {
        self.updaterViewModel = updaterViewModel
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate, !state.userInitiated else { return }
        let updaterViewModel = updaterViewModel
        let version = update.displayVersionString
        Task { @MainActor [updaterViewModel, version] in
            updaterViewModel.noteAvailableUpdate(version: version)
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        let updaterViewModel = updaterViewModel
        Task { @MainActor [updaterViewModel] in updaterViewModel.clearAvailableUpdate() }
    }

    func standardUserDriverWillFinishUpdateSession() {
        let updaterViewModel = updaterViewModel
        Task { @MainActor [updaterViewModel] in updaterViewModel.clearAvailableUpdate() }
    }
}

#endif

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

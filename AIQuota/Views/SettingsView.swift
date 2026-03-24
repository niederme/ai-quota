import SwiftUI
import ServiceManagement
import UserNotifications
import AIQuotaKit

struct SettingsView: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @Environment(UpdaterViewModel.self) private var updater
    @Environment(\.openWindow) private var openWindow

    @State private var showResetConfirmation = false
    @State private var notifPermissionGranted = false
    @State private var formID = UUID()

    private var notifSectionsEnabled: Bool {
        viewModel.settings.notifications.enabled && notifPermissionGranted
    }

    private let refreshOptions = [5, 15, 30, 60]

    var body: some View {
        @Bindable var vm = viewModel
        @Bindable var u = updater

        Form {
            // MARK: General
            Section("General") {
                Picker("Refresh every", selection: $vm.settings.refreshIntervalMinutes) {
                    ForEach(refreshOptions, id: \.self) { Text("\($0) min").tag($0) }
                }
                .pickerStyle(.segmented)

                LabeledContent("Menu bar service") {
                    EnrollmentSegmentedPicker(
                        selection: $vm.settings.menuBarService,
                        enrolledServices: vm.enrolledServices
                    )
                }

                LaunchAtLoginToggle()
            }

            // MARK: Notifications — master toggle
            Section("Notifications") {
                Toggle("Enable notifications", isOn: $vm.settings.notifications.enabled)
                    .onChange(of: vm.settings.notifications.enabled) { _, enabled in
                        if enabled {
                            Task {
                                await NotificationManager.shared.requestPermission()
                                await checkNotifPermission()
                            }
                        } else {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                notifPermissionGranted = false
                            }
                        }
                    }
                if viewModel.settings.notifications.enabled {
                    NotificationStatusRow()
                }
            }

            // MARK: Notifications — Codex
            if viewModel.isCodexEnrolled {
                Section {
                    notifServiceRow(logo: "logo-openai", name: "Codex",
                                    isOn: notifSectionsEnabled ? $vm.settings.notifications.codexEnabled : .constant(false))
                    if notifSectionsEnabled && vm.settings.notifications.codexEnabled {
                        notifSubHeader("5-hour window")
                        Toggle("Less than 15% remaining", isOn: $vm.settings.notifications.codex5hAt15)
                        Toggle("Less than 5% remaining",  isOn: $vm.settings.notifications.codex5hAt5)
                        Toggle("Limit reached",           isOn: $vm.settings.notifications.codex5hLimitReached)
                        Toggle("Window reset",            isOn: $vm.settings.notifications.codex5hReset)

                        notifSubHeader("Weekly usage")
                        Toggle("Less than 15% remaining", isOn: $vm.settings.notifications.codexAt15)
                        Toggle("Less than 5% remaining",  isOn: $vm.settings.notifications.codexAt5)
                        Toggle("Limit reached",           isOn: $vm.settings.notifications.codexLimitReached)
                        Toggle("Weekly reset",            isOn: $vm.settings.notifications.codexReset)
                    }
                }
                .disabled(!notifSectionsEnabled)
                .opacity(notifSectionsEnabled ? 1 : 0.45)
            }

            // MARK: Notifications — Claude Code
            if viewModel.isClaudeEnrolled {
                Section {
                    notifServiceRow(logo: "logo-claude", name: "Claude Code",
                                    isOn: notifSectionsEnabled ? $vm.settings.notifications.claudeEnabled : .constant(false))
                    if notifSectionsEnabled && vm.settings.notifications.claudeEnabled {
                        notifSubHeader("5-hour window")
                        Toggle("Less than 15% remaining", isOn: $vm.settings.notifications.claude5hAt15)
                        Toggle("Less than 5% remaining",  isOn: $vm.settings.notifications.claude5hAt5)
                        Toggle("Limit reached",           isOn: $vm.settings.notifications.claude5hLimitReached)
                        Toggle("Window reset",            isOn: $vm.settings.notifications.claude5hReset)

                        notifSubHeader("7-day window")
                        Toggle("80% used (high)",         isOn: $vm.settings.notifications.claude7dAt80)
                        Toggle("95% used (critical)",     isOn: $vm.settings.notifications.claude7dAt95)
                        Toggle("Limit reached",           isOn: $vm.settings.notifications.claude7dLimitReached)
                        Toggle("Period reset",            isOn: $vm.settings.notifications.claude7dReset)
                    }
                }
                .disabled(!notifSectionsEnabled)
                .opacity(notifSectionsEnabled ? 1 : 0.45)
            }

            if viewModel.enrolledServices.isEmpty {
                Section {
                    Text("Sign in to a service to configure thresholds.")
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: Updates
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $u.automaticallyChecksForUpdates)
                Button("Check Now") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }

            // MARK: Accounts
            Section("Accounts") {
                LabeledContent("Codex") {
                    if viewModel.isCodexAuthenticated {
                        Button("Sign Out", role: .destructive) { viewModel.signOut() }
                    } else {
                        Button("Sign In") { Task { await viewModel.signIn() } }
                    }
                }
                LabeledContent("Claude Code") {
                    if viewModel.isClaudeAuthenticated {
                        Button("Sign Out", role: .destructive) { viewModel.signOutClaude() }
                    } else {
                        Button("Sign In") { Task { await viewModel.signInClaude() } }
                    }
                }
            }

            // MARK: Onboarding
            Section("Onboarding") {
                HStack {
                    Button("Guided Setup…") {
                        viewModel.resetOnboardingForReplay()
                        openWindow(id: "onboarding")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    Spacer()
                    Button("Reset All Settings…", role: .destructive) {
                        showResetConfirmation = true
                    }
                }
            }

            // MARK: About footer
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
            Section {
                VStack(spacing: 3) {
                    Text("AIQuota \(version) (\(build))")
                        .fontWeight(.medium)
                    Text("Made by John Niedermeyer, with a little help from\nClaude, Codex and friends.")
                        .multilineTextAlignment(.center)
                    Text("Need Help?")
                        .padding(.top, 4)
                    HStack(spacing: 12) {
                        Link("GitHub Issues", destination: URL(string: "https://github.com/niederme/ai-quota/issues")!)
                            .foregroundColor(Color.brand)
                        Text("·").foregroundStyle(.quaternary)
                        Link("@niederme on X", destination: URL(string: "https://x.com/niederme")!)
                            .foregroundColor(Color.brand)
                    }
                }
                .font(.callout)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .listRowBackground(Color.clear)
        }
        .id(formID)
        .formStyle(.grouped)
        .frame(width: 400)
        .navigationTitle("Settings")
        .task { await checkNotifPermission() }
        // macOS keeps the Settings window alive between opens (just hides it),
        // so onAppear doesn't re-fire. Observing didBecomeKey resets the Form's
        // identity each time the window is brought to front, scrolling back to top.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            formID = UUID()
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: notifSectionsEnabled)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: viewModel.settings.notifications.codexEnabled)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: viewModel.settings.notifications.claudeEnabled)
        .onChange(of: viewModel.settings) { viewModel.saveSettings() }
        .background(FloatingWindowElevator())
        .confirmationDialog(
            "Clear all Settings and Start Over?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                Task {
                    await viewModel.resetToNewUser()
                    openWindow(id: "onboarding")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Signs out of all services, clears cached data, and resets settings to defaults. System notification permissions are not affected.")
        }
    }

    // MARK: - Notification helpers

    @ViewBuilder
    private func notifServiceRow(logo: String, name: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(logo)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
            Text(name)
                .fontWeight(.semibold)
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    @ViewBuilder
    private func notifSubHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .listRowBackground(Color.clear)
    }

    private func checkNotifPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            notifPermissionGranted = settings.authorizationStatus == .authorized
        }
    }
}

// MARK: - Window level helper

private struct FloatingWindowElevator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.level = .floating }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Notification Status

private struct NotificationStatusRow: View {
    @State private var status: UNAuthorizationStatus = .notDetermined

    var body: some View {
        HStack {
            switch status {
            case .authorized:
                Label("Permission granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .denied:
                Label("Permission denied", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Spacer()
                Button("Open System Settings") {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
                    )
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.blue)
            default:
                Label("Permission not requested yet", systemImage: "questionmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            status = settings.authorizationStatus
        }
    }
}

// MARK: - Launch at Login

private struct LaunchAtLoginToggle: View {
    @State private var isEnabled = (SMAppService.mainApp.status == .enabled)

    var body: some View {
        Toggle("Launch at login", isOn: $isEnabled)
            .onChange(of: isEnabled) { _, newValue in
                do {
                    if newValue { try SMAppService.mainApp.register() }
                    else        { try SMAppService.mainApp.unregister() }
                } catch {
                    isEnabled = !newValue
                }
            }
    }
}

// MARK: - Enrollment-aware segmented picker

/// A segmented-style service picker that visually deactivates unenrolled segments.
private struct EnrollmentSegmentedPicker: View {
    @Binding var selection: ServiceType
    let enrolledServices: Set<ServiceType>

    var body: some View {
        HStack(spacing: 1) {
            ForEach(ServiceType.allCases, id: \.self) { service in
                segmentButton(for: service)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func segmentButton(for service: ServiceType) -> some View {
        let enrolled = enrolledServices.contains(service)
        let selected = selection == service

        Button {
            if enrolled { selection = service }
        } label: {
            Text(service.displayName)
                .font(.system(size: 13))
                .frame(minWidth: 70, maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(
                    selected && enrolled
                        ? Color(NSColor.selectedControlColor)
                        : Color.clear
                )
                .foregroundColor(
                    selected && enrolled
                        ? Color(NSColor.selectedControlTextColor)
                        : enrolled
                            ? Color(NSColor.controlTextColor)
                            : Color(NSColor.disabledControlTextColor)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enrolled)
    }
}

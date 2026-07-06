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

    private let refreshOptions = AppSettings.supportedRefreshIntervalMinutes

    var body: some View {
        @Bindable var vm = viewModel
        @Bindable var u = updater

        Form {
            // MARK: General
            Section("General") {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Refresh every", selection: $vm.settings.refreshIntervalMinutes) {
                        ForEach(refreshOptions, id: \.self) { minutes in
                            Text(refreshLabel(for: minutes)).tag(minutes)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("Auto refreshes every 5 min, speeds up to 1 min when usage is changing or near a threshold, and slows down when your Mac is idle.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LabeledContent("Menu bar display") {
                    let selection = Binding<MenuBarDisplayOption>(
                        get: {
                            MenuBarDisplayOption.current(
                                settings: vm.settings,
                                enrolledServices: vm.enrolledServices
                            )
                        },
                        set: { option in
                            applyMenuBarDisplayOption(option, settings: &vm.settings)
                            let enabled = vm.settings.analyticsEnabled
                            let params = vm.analyticsContextParams.merging(
                                [
                                    "display": option.rawValue,
                                    "service": vm.settings.menuBarService.rawValue
                                ]
                            ) { _, new in new }
                            Task {
                                await AnalyticsClient.shared.send(
                                    "menubar_display_changed",
                                    params: params,
                                    enabled: enabled
                                )
                            }
                        }
                    )

                    MenuBarDisplaySegmentedPicker(
                        selection: selection,
                        enrolledServices: vm.enrolledServices
                    )
                    .frame(width: 260)
                }

                LaunchAtLoginToggle()
            }

            // MARK: Accounts
            Section("Accounts") {
                AccountDiagnosticsRows()
            }

            // MARK: Notifications
            Section("Notifications") {
                VStack(alignment: .leading, spacing: 6) {
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
                        NotificationStatusCaption()
                    }
                }

                if viewModel.settings.notifications.enabled {
                    if viewModel.isCodexEnrolled {
                        NotificationServiceRow(
                            service: .codex,
                            logo: "logo-openai",
                            isOn: $vm.settings.notifications.codexEnabled,
                            isEnabled: notifSectionsEnabled,
                            preferences: $vm.settings.notifications
                        )
                    }

                    if viewModel.isClaudeEnrolled {
                        NotificationServiceRow(
                            service: .claude,
                            logo: "logo-claude",
                            isOn: $vm.settings.notifications.claudeEnabled,
                            isEnabled: notifSectionsEnabled,
                            preferences: $vm.settings.notifications
                        )
                    }

                    if viewModel.enrolledServices.isEmpty {
                        Text("Sign in to a service to configure thresholds.")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // MARK: Privacy
            Section("Privacy") {
                Toggle("Share anonymous usage data",
                       isOn: $vm.settings.analyticsEnabled)
                Text("Share app launches, active use, setup completion, and app version. No prompts, tokens, cookies, or personal info.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link("Privacy Policy", destination: URL(string: "https://aiquota.app/privacy/")!)
                    .foregroundColor(Color.brand)
            }

            // MARK: Updates
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $u.automaticallyChecksForUpdates)
                Button("Check Now") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
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
                    Text("Made by John Niedermeyer, with a little help from\nClaude, Codex, and friends.")
                        .multilineTextAlignment(.center)
                    Text("Need help?")
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
        .frame(width: 500, height: 700)
        .navigationTitle("Settings")
        .task { await checkNotifPermission() }
        // macOS keeps the Settings window alive between opens (just hides it),
        // so onAppear doesn’t re-fire. Observing didBecomeKey resets the Form’s
        // identity each time the window is brought to front, scrolling back to top.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            formID = UUID()
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: notifSectionsEnabled)
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

    private func checkNotifPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            notifPermissionGranted = settings.authorizationStatus == .authorized
        }
    }

    private func refreshLabel(for minutes: Int) -> String {
        minutes == AppSettings.autoRefreshIntervalMinutes ? "Auto" : "\(minutes)"
    }

    private func applyMenuBarDisplayOption(_ option: MenuBarDisplayOption, settings: inout AppSettings) {
        switch option {
        case .codex:
            settings.menuBarDisplayMode = .single
            settings.menuBarService = .codex
        case .claude:
            settings.menuBarDisplayMode = .single
            settings.menuBarService = .claude
        case .both:
            settings.menuBarDisplayMode = .both
        }
    }
}

// MARK: - Notification Details

private struct NotificationServiceRow: View {
    let service: ServiceType
    let logo: String
    @Binding var isOn: Bool
    let isEnabled: Bool
    @Binding var preferences: NotificationPreferences

    @State private var isExpanded = false
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)
                }
                .buttonStyle(.plain)

                HStack(spacing: 10) {
                    Image(logo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)

                    Text(service.displayName)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) {
                        isExpanded.toggle()
                    }
                }

                Toggle("", isOn: $isOn)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!isEnabled)
            }
            .onHover { isHovering = $0 }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? Color.primary.opacity(0.06) : Color.clear)
            )

            if isExpanded {
                NotificationInlineControls(service: service, preferences: $preferences)
                    .padding(.leading, 50)
                    .padding(.top, 2)
                    .padding(.bottom, 4)
                    .disabled(!isOn || !isEnabled)
                    .opacity(isOn && isEnabled ? 1 : 0.45)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .opacity(isEnabled ? 1 : 0.55)
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }
}

private struct NotificationInlineControls: View {
    let service: ServiceType
    @Binding var preferences: NotificationPreferences

    var body: some View {
        switch service {
        case .codex:
            codexControls
        case .claude:
            claudeControls
        }
    }

    @ViewBuilder
    private var codexControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            notificationOptionGroup("5-hour window") {
                notificationCheckbox("Usage alerts", isOn: $preferences.codex5hThresholdAlerts)
                notificationCheckbox("Reset alert", isOn: $preferences.codex5hReset)
            }

            notificationOptionGroup("7-day window") {
                notificationCheckbox("Usage alerts", isOn: $preferences.codexWeeklyThresholdAlerts)
                notificationCheckbox("Reset alert", isOn: $preferences.codexReset)
            }

            notificationOptionGroup("Credits") {
                notificationCheckbox("Top-up events", isOn: $preferences.codexTopUp)
            }
        }
    }

    @ViewBuilder
    private var claudeControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            notificationOptionGroup("5-hour window") {
                notificationCheckbox("Usage alerts", isOn: $preferences.claude5hThresholdAlerts)
                notificationCheckbox("Reset alert", isOn: $preferences.claude5hReset)
            }

            notificationOptionGroup("7-day window") {
                notificationCheckbox("Usage alerts", isOn: $preferences.claude7dThresholdAlerts)
                notificationCheckbox("Reset alert", isOn: $preferences.claude7dReset)
            }
        }
    }

    private func notificationOptionGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                content()
            }
        }
    }

    private func notificationCheckbox(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.checkbox)
    }
}

// MARK: - Accounts + Auth Diagnostics

private struct AccountDiagnosticsRows: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @State private var codexAttempts: [CodexSourceAttempt] = []
    @State private var claudeAttempts: [ClaudeSourceAttempt] = []

    var body: some View {
        AccountServiceStatusRow(
            label: "Codex",
            logo: "logo-openai",
            isAuthenticated: viewModel.isCodexAuthenticated,
            statusDetail: statusDetail(isAuthenticated: viewModel.isCodexAuthenticated, attempt: codexAttempts.last),
            statusColor: statusColor(isAuthenticated: viewModel.isCodexAuthenticated, attempt: codexAttempts.last),
            signIn: { Task { await viewModel.signIn() } },
            signOut: { viewModel.signOut() }
        )

        AccountServiceStatusRow(
            label: "Claude Code",
            logo: "logo-claude",
            isAuthenticated: viewModel.isClaudeAuthenticated,
            statusDetail: statusDetail(isAuthenticated: viewModel.isClaudeAuthenticated, attempt: claudeAttempts.last),
            statusColor: statusColor(isAuthenticated: viewModel.isClaudeAuthenticated, attempt: claudeAttempts.last),
            signIn: { Task { await viewModel.signInClaude() } },
            signOut: { viewModel.signOutClaude() }
        )

        HStack(alignment: .firstTextBaseline) {
            Button("Refresh Status") { reload() }
            Button("Copy Diagnostics") { copyDiagnostics() }
            Spacer()
        }

        VStack(alignment: .leading, spacing: 2) {
            Text("Copy Diagnostics includes both services: auth source, HTTP status, error category, and timestamp.")
            Text("No tokens, headers, cookies, or response bodies are included.")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .task { reload() }
    }

    private func reload() {
        codexAttempts = SharedDefaults.loadCodexSourceAttempts()
        claudeAttempts = SharedDefaults.loadClaudeSourceAttempts()
    }

    private func statusDetail(isAuthenticated: Bool, attempt: CodexSourceAttempt?) -> String {
        guard isAuthenticated else { return "Not signed in" }
        guard let attempt else { return "Not checked yet" }
        if attempt.errorCategory == .success {
            return "\(sourceName(attempt.source)) · checked \(relativeTime(attempt.timestamp))"
        }
        return "\(statusMessage(for: attempt.errorCategory)) · checked \(relativeTime(attempt.timestamp))"
    }

    private func statusDetail(isAuthenticated: Bool, attempt: ClaudeSourceAttempt?) -> String {
        guard isAuthenticated else { return "Not signed in" }
        guard let attempt else { return "Not checked yet" }
        if attempt.errorCategory == .success {
            return "\(sourceName(attempt.source)) · checked \(relativeTime(attempt.timestamp))"
        }
        return "\(statusMessage(for: attempt.errorCategory)) · checked \(relativeTime(attempt.timestamp))"
    }

    private func statusColor(isAuthenticated: Bool, attempt: CodexSourceAttempt?) -> Color {
        guard isAuthenticated, let attempt else { return .secondary }
        switch attempt.errorCategory {
        case .success:
            return .green
        case .authFailed:
            return .red
        case .rateLimited, .serverError, .network, .invalidResponse:
            return .orange
        }
    }

    private func statusColor(isAuthenticated: Bool, attempt: ClaudeSourceAttempt?) -> Color {
        guard isAuthenticated, let attempt else { return .secondary }
        switch attempt.errorCategory {
        case .success:
            return .green
        case .missingCredentials, .expiredCredentials, .missingScope, .malformedCredentials, .authFailed, .policyBlocked:
            return .red
        case .rateLimited, .serverError, .network, .invalidResponse:
            return .orange
        }
    }

    private func copyDiagnostics() {
        reload()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(diagnosticsReport(), forType: .string)
    }

    private func diagnosticsReport() -> String {
        var lines: [String] = [
            "AIQuota auth diagnostics",
            "Generated: \(Self.timestampFormatter.string(from: .now))",
            "",
            "Codex attempts:"
        ]
        lines.append(contentsOf: codexAttempts.map(codexLine))
        if codexAttempts.isEmpty { lines.append("- none") }

        lines.append("")
        lines.append("Claude attempts:")
        lines.append(contentsOf: claudeAttempts.map(claudeLine))
        if claudeAttempts.isEmpty { lines.append("- none") }
        return lines.joined(separator: "\n")
    }

    private func codexLine(_ attempt: CodexSourceAttempt) -> String {
        "- \(Self.timestampFormatter.string(from: attempt.timestamp)) source=\(attempt.source.rawValue) category=\(attempt.errorCategory.rawValue) httpStatus=\(attempt.httpStatus.map(String.init) ?? "none")"
    }

    private func claudeLine(_ attempt: ClaudeSourceAttempt) -> String {
        "- \(Self.timestampFormatter.string(from: attempt.timestamp)) source=\(attempt.source.rawValue) category=\(attempt.errorCategory.rawValue) httpStatus=\(attempt.httpStatus.map(String.init) ?? "none")"
    }

    private func sourceName(_ source: CodexAuthSource) -> String {
        switch source {
        case .codexOAuth: "CLI OAuth"
        case .webSession: "Web"
        case .unknown: "Unknown"
        }
    }

    private func sourceName(_ source: ClaudeUsage.Source) -> String {
        switch source {
        case .oauth: "Claude Code"
        case .web: "Web"
        case .unknown: "Unknown"
        }
    }

    private func categoryName(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(
                of: "([a-z])([A-Z])",
                with: "$1 $2",
                options: .regularExpression
            )
            .capitalized
    }

    private func statusMessage(for category: CodexSourceAttempt.ErrorCategory) -> String {
        switch category {
        case .success:
            "Working"
        case .authFailed:
            "Auth needs attention"
        case .rateLimited:
            "Rate limited"
        case .serverError:
            "Service issue"
        case .network:
            "Network issue"
        case .invalidResponse:
            "Unexpected response"
        }
    }

    private func statusMessage(for category: ClaudeSourceAttempt.ErrorCategory) -> String {
        switch category {
        case .success:
            "Working"
        case .missingCredentials:
            "Claude Code credentials not found"
        case .expiredCredentials:
            "Claude Code credentials expired"
        case .missingScope:
            "Claude Code permissions missing"
        case .malformedCredentials:
            "Claude Code credentials unreadable"
        case .authFailed:
            "Auth needs attention"
        case .policyBlocked:
            "Access blocked by policy"
        case .rateLimited:
            "Rate limited"
        case .serverError:
            "Service issue"
        case .network:
            "Network issue"
        case .invalidResponse:
            "Unexpected response"
        }
    }

    private func relativeTime(_ date: Date) -> String {
        Self.relativeFormatter.localizedString(for: date, relativeTo: .now)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private static let timestampFormatter = ISO8601DateFormatter()
}

private struct AccountServiceStatusRow: View {
    let label: String
    let logo: String
    let isAuthenticated: Bool
    let statusDetail: String
    let statusColor: Color
    let signIn: () -> Void
    let signOut: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(logo)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .foregroundStyle(.primary)

                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)

                    Text(statusDetail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption)
            }

            Spacer(minLength: 12)

            if isAuthenticated {
                Button("Sign Out", role: .destructive, action: signOut)
            } else {
                Button("Sign In", action: signIn)
            }
        }
    }
}

// MARK: - Window level + size enforcer

private struct FloatingWindowElevator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { Self.configure(view.window) }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.configure(nsView.window) }
    }

    private static func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.level = .floating
        // Override any macOS-restored frame — saved sizes from older builds
        // would otherwise produce a window that’s too small to scroll into.
        let size = NSSize(width: 500, height: 700)
        window.minSize = size
        window.maxSize = size
        if window.frame.size != size {
            window.setContentSize(size)
        }
    }
}

// MARK: - Notification Status

private struct NotificationStatusCaption: View {
    @State private var status: UNAuthorizationStatus = .notDetermined

    var body: some View {
        HStack {
            switch status {
            case .authorized:
                statusLabel("Permission granted", systemImage: "checkmark.circle.fill", iconColor: .green)
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
        .font(.caption2.weight(.medium))
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            status = settings.authorizationStatus
        }
    }

    private func statusLabel(_ title: String, systemImage: String, iconColor: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .foregroundStyle(iconColor)
            Text(title)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Launch at Login

struct LaunchAtLoginToggle: View {
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

// MARK: - Menu bar display picker

/// Native segmented picker for mutually exclusive menu bar display options.
private struct MenuBarDisplaySegmentedPicker: View {
    @Binding var selection: MenuBarDisplayOption
    let enrolledServices: Set<ServiceType>

    var body: some View {
        Picker("Menu bar display", selection: $selection) {
            ForEach(MenuBarDisplayOption.allCases, id: \.self) { option in
                Text(option.displayName)
                    .tag(option)
                    .disabled(!isAvailable(option))
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func isAvailable(_ option: MenuBarDisplayOption) -> Bool {
        switch option {
        case .codex:
            enrolledServices.contains(.codex)
        case .claude:
            enrolledServices.contains(.claude)
        case .both:
            enrolledServices.contains(.codex) && enrolledServices.contains(.claude)
        }
    }
}

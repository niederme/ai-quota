import SwiftUI
import MobileAccessCore

struct MultiAccountSettingsView: View {
    @Environment(\.setDemoEnabled) private var setDemoEnabled
    @AppStorage("refreshIntervalMinutes") private var refreshMinutes = 0
    let accounts: MobileAccountCollection
    let onboarding: OnboardingProgress
    @State private var connectionProfile: AccountProfile?
    @State private var pendingAdd: AccountProfile?
    @State private var accountToRename: AccountProfile?
    @State private var labelDraft = ""
    @State private var accountToRemove: AccountProfile?
    @State private var showOnboarding = false
    @State private var showNotifications = false
    @State private var showWidgets = false
    @State private var confirmReset = false
    @State private var resetting = false
    @State private var resetError: String?
    @State private var serviceOrder = AccountRegistry.serviceOrder()

    var body: some View {
        Form {
            Section("Demo") {
                Button("Try demo") { setDemoEnabled(true) }
            }
            Section {
                Picker("Refresh every", selection: $refreshMinutes) {
                    Text("Auto").tag(0)
                    ForEach([1, 5, 10, 30], id: \.self) { Text("\($0) min").tag($0) }
                }
            } header: { Text("General") } footer: {
                Text("While the app is open, Auto refreshes every 5 minutes, or every minute near a limit. Background timing is not guaranteed.")
            }
            ForEach(serviceOrder, id: \.self) { service in
                Section {
                    ForEach(accounts.all(service), id: \.id) { profile in
                        HStack(spacing: 12) {
                            Button { connectionProfile = profile } label: { accountRow(profile) }
                                .buttonStyle(.plain)
                            Menu {
                                Button("Rename") { rename(profile) }
                                Button("Use as widget default") { accounts.setDefault(profile) }
                                Button("Remove account", role: .destructive) { accountToRemove = profile }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Manage \(service.name) \(profile.label)")
                        }
                            .contextMenu {
                                Button("Rename") { rename(profile) }
                                Button("Use as widget default") { accounts.setDefault(profile) }
                                Button("Remove account", role: .destructive) { accountToRemove = profile }
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Remove", role: .destructive) { accountToRemove = profile }
                            }
                    }
                    Button("Add \(service.name) account", systemImage: "plus") { add(service) }
                    if serviceOrder.count > 1 {
                        HStack {
                            Button("Move earlier", systemImage: "arrow.up") { move(service, -1) }
                                .disabled(serviceOrder.first == service)
                            Spacer()
                            Button("Move later", systemImage: "arrow.down") { move(service, 1) }
                                .disabled(serviceOrder.last == service)
                        }.font(.footnote)
                    }
                } header: { Text(service.name) }
            }
            Section {
                Button("Notifications") { showNotifications = true }
                Button("Widgets") { showWidgets = true }
            }
            Section("Onboarding") {
                Button("Guided Setup…") { onboarding.replay(); showOnboarding = true }
                Button("Reset All Settings…", role: .destructive) { confirmReset = true }
                if resetting { ProgressView("Resetting…") }
                if let resetError { Text(resetError).font(.callout).foregroundStyle(OverviewStyle.critical) }
            }
            Section("Privacy") {
                MobileAnalyticsConsentControls(surface: .settings, isDemo: false)
                Text("Sign-in credentials stay in this device’s Keychain and are shared with its widgets. Usage is requested directly from each service.")
                    .font(.footnote).foregroundStyle(OverviewStyle.secondary)
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
            }
        }
        .disabled(resetting)
        .scrollContentBackground(.hidden)
        .background { BrandSurfaceBackground().ignoresSafeArea() }
        .foregroundStyle(OverviewStyle.primary)
        .tint(OverviewStyle.accent)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Rename account", isPresented: Binding(
            get: { accountToRename != nil },
            set: { if !$0 { accountToRename = nil } }
        )) {
            TextField("Account label", text: $labelDraft)
            Button("Save") {
                if let accountToRename { accounts.rename(accountToRename, to: labelDraft) }
                accountToRename = nil
            }
            Button("Cancel", role: .cancel) { accountToRename = nil }
        } message: {
            Text("This name appears on cards and in widget choices.")
        }
        .confirmationDialog("Remove this account from AIQuota?", isPresented: Binding(
            get: { accountToRemove != nil }, set: { if !$0 { accountToRemove = nil } }
        ), titleVisibility: .visible) {
            Button("Remove account", role: .destructive) {
                guard let profile = accountToRemove else { return }
                accountToRemove = nil
                Task {
                    do { try await accounts.remove(profile) }
                    catch { resetError = "Couldn’t remove this account. Try again." }
                }
            }
        } message: {
            Text("Removes this account’s local connection and saved usage.")
        }
        .confirmationDialog("Clear all Settings and Start Over?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                resetting = true
                resetError = nil
                Task {
                    do {
                        for profile in accounts.profiles { try await accounts.remove(profile) }
                        MobileSettingsReset.clearPreferences()
                        onboarding.reset()
                        onboarding.begin()
                        showOnboarding = true
                    } catch { resetError = "Couldn’t finish resetting. Try again." }
                    resetting = false
                }
            }
        } message: {
            Text("Signs out of all accounts and resets settings to defaults.")
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(codex: accounts.setupCodex, claude: accounts.setupClaude,
                           progress: onboarding, accounts: accounts, onFinish: { accounts.reload() })
        }
        .sheet(item: $connectionProfile, onDismiss: {
            if let pendingAdd { accounts.discardIfUnconnected(pendingAdd) }
            pendingAdd = nil
            accounts.reload()
        }) { profile in
            ServiceAccountSheet {
                if profile.service == .codex, let model = accounts.codex(profile) {
                    ProbeView(model: model)
                } else if let model = accounts.claude(profile) {
                    ClaudeProbeView(model: model)
                }
            }
        }
        .sheet(isPresented: $showNotifications) { ServiceAccountSheet { MobileNotificationsView() } }
        .sheet(isPresented: $showWidgets) { ServiceAccountSheet { LockScreenSetupView() } }
    }

    private func accountRow(_ profile: AccountProfile) -> some View {
        let model = profile.service == .codex ? accounts.codex(profile) : nil
        let claude = profile.service == .claude ? accounts.claude(profile) : nil
        let connected = model?.connected == true || claude?.connected == true
        let reading = model?.reading ?? claude?.reading
        let failure = model?.connectionFailure ?? claude?.connectionFailure
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(profile.label).fontWeight(.semibold)
                Spacer()
                Text(!connected ? "Connect" : failure == nil ? "Connected" : "Needs attention")
                    .font(.subheadline).foregroundStyle(OverviewStyle.secondary)
            }
            if let plan = reading?.metadata?.displayPlan {
                Text("\(plan) plan").font(.footnote).foregroundStyle(OverviewStyle.secondary)
            }
            if let updated = reading?.fetchedAt {
                Text("Updated \(updated.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote).foregroundStyle(OverviewStyle.secondary)
            }
            if AccountRegistry.defaultProfile(for: profile.service)?.id == profile.id {
                Text("Widget default").font(.footnote).foregroundStyle(OverviewStyle.secondary)
            }
        }
        .frame(minHeight: 44, alignment: .leading)
    }

    private func rename(_ profile: AccountProfile) {
        labelDraft = profile.label
        accountToRename = profile
    }

    private func add(_ service: QuotaService) {
        let profile = accounts.add(service)
        pendingAdd = profile
        connectionProfile = profile
    }

    private func move(_ service: QuotaService, _ offset: Int) {
        guard let index = serviceOrder.firstIndex(of: service), serviceOrder.indices.contains(index + offset) else { return }
        serviceOrder.swapAt(index, index + offset)
        AccountRegistry.setServiceOrder(serviceOrder)
    }
}

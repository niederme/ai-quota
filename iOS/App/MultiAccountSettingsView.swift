import SwiftUI
import MobileAccessCore
import WidgetKit

struct MultiAccountSettingsView: View {
    @Environment(\.setDemoEnabled) private var setDemoEnabled
    @AppStorage("refreshIntervalMinutes") private var refreshMinutes = 0
    let accounts: MobileAccountCollection
    let onboarding: OnboardingProgress
    var orderStore: AccountRegistry.Store? = nil
    @State private var connectionProfile: AccountProfile?
    @State private var pendingAdd: AccountProfile?
    @State private var namingAccount: AccountProfile?
    @State private var nameDraft = ""
    @State private var accountToRename: AccountProfile?
    @State private var labelDraft = ""
    @State private var accountToRemove: AccountProfile?
    @State private var showOnboarding = false
    @State private var showNotifications = false
    @State private var showWidgets = false
    @State private var showCodexResets = false
    @State private var confirmReset = false
    @State private var resetting = false
    @State private var resetError: String?

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
            ForEach(QuotaService.allCases, id: \.self) { service in
                Section {
                    ForEach(accounts.all(service), id: \.id) { profile in
                        HStack(spacing: 12) {
                            Button {
                                pendingAdd = profile.suggestedNamePending == true ? profile : nil
                                connectionProfile = profile
                            } label: { accountRow(profile) }
                                .buttonStyle(.plain)
                            Menu {
                                Button("Rename") { rename(profile) }
                                Button("Use as widget fallback") { accounts.setDefault(profile) }
                                    .disabled(AccountRegistry.defaultProfile(for: service)?.id == profile.id)
                                Button("Remove account", role: .destructive) { accountToRemove = profile }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Manage \(service.name) \(profile.label)")
                        }
                            .contextMenu {
                                Button("Rename") { rename(profile) }
                                Button("Use as widget fallback") { accounts.setDefault(profile) }
                                    .disabled(AccountRegistry.defaultProfile(for: service)?.id == profile.id)
                                Button("Remove account", role: .destructive) { accountToRemove = profile }
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Remove", role: .destructive) { accountToRemove = profile }
                            }
                    }
                    Button("Add \(service.name) account", systemImage: "plus") { add(service) }
                } header: { Text(service.name) } footer: {
                    if accounts.all(service).count > 1 {
                        Text("The widget fallback is used when a widget has no account selected. Widgets with a selected account keep their choice.")
                    }
                }
            }
            Section {
                Button("Notifications") { showNotifications = true }
                Button("Widgets") { showWidgets = true }
                NavigationLink("Account order") { AccountOrderSettingsView(profiles: accounts.profiles, orderStore: orderStore) }
                Button("Codex Resets", systemImage: "arrow.up.right") { showCodexResets = true }
                    .accessibilityHint("Opens Codex Resets in the in-app browser")
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
        .onAppear { accounts.reload() }
        .disabled(resetting)
        .scrollContentBackground(.hidden)
        .background { BrandSurfaceBackground().ignoresSafeArea() }
        .foregroundStyle(OverviewStyle.primary)
        .tint(OverviewStyle.accent)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Name your account", isPresented: Binding(
            get: { namingAccount != nil }, set: { if !$0 { namingAccount = nil } }
        )) {
            TextField("Account name", text: $nameDraft)
            Button("Save") {
                if let namingAccount { accounts.rename(namingAccount, to: nameDraft) }
                namingAccount = nil
            }
            .disabled(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Not now", role: .cancel) { namingAccount = nil }
        } message: {
            Text("Your account is connected. Save the suggested name or choose your own. You can change it later in Settings.")
        }
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
            if let pendingAdd {
                if let connected = accounts.finishAdding(pendingAdd) {
                    nameDraft = connected.label
                    namingAccount = connected
                }
            }
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
        .sheet(isPresented: $showCodexResets) { ProbeBrowser(url: CodexResetNotice.website) }
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
            if accounts.all(profile.service).count > 1, AccountRegistry.defaultProfile(for: profile.service)?.id == profile.id {
                Text("Widget fallback").font(.footnote).foregroundStyle(OverviewStyle.secondary)
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

}


@MainActor func reloadAccountOrderWidgets() {
    WidgetCenter.shared.reloadTimelines(ofKind: "AIQuotaHomeBoth")
    WidgetCenter.shared.reloadTimelines(ofKind: "BothLockScreen")
}

struct AccountOrderSettingsView: View {
    let profiles: [AccountProfile]
    private let orderStore: AccountRegistry.Store?
    @State private var order: [String]

    init(profiles: [AccountProfile], orderStore: AccountRegistry.Store? = nil) {
        self.profiles = profiles
        self.orderStore = orderStore
        _order = State(initialValue: orderStore?.accountOrder() ?? AccountRegistry.accountOrder())
    }

    private var ordered: [AccountProfile] { AccountProfile.ordered(profiles, by: order) }
    var body: some View {
        List {
            Section {
                ForEach(ordered, id: \.orderKey) { profile in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.service.name).fontWeight(.semibold)
                        if profile.label.caseInsensitiveCompare(profile.service.name) != .orderedSame {
                            Text(profile.label).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("accountOrder-\(profile.service.rawValue):\(profile.id)")
                    .accessibilityAction(named: "Move earlier") { move(profile.orderKey, offset: -1) }
                    .accessibilityAction(named: "Move later") { move(profile.orderKey, offset: 1) }
                }
                .onMove { source, destination in
                    var keys = ordered.map(\.orderKey)
                    keys.move(fromOffsets: source, toOffset: destination)
                    save(keys)
                }
            } footer: {
                Text("Drag to change the order in the app and widgets using App order. Widgets with a selected subset keep only those accounts. Other sort choices stay unchanged.")
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Account order")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { order = orderStore?.accountOrder() ?? AccountRegistry.accountOrder() }
        .onChange(of: profiles) { _, _ in order = orderStore?.accountOrder() ?? AccountRegistry.accountOrder() }
    }

    private func move(_ key: String, offset: Int) {
        var keys = ordered.map(\.orderKey)
        guard let index = keys.firstIndex(of: key), keys.indices.contains(index + offset) else { return }
        keys.swapAt(index, index + offset)
        save(keys)
    }
    private func save(_ keys: [String]) {
        order = keys
        let changed = orderStore?.setAccountOrder(keys) ?? AccountRegistry.setAccountOrder(keys)
        if changed && orderStore == nil { reloadAccountOrderWidgets() }
    }
}

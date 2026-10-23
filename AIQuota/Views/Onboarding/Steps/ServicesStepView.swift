import SwiftUI
import AIQuotaKit

struct ServicesStepView: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @State private var accounts = AccountRegistry.orderedAccounts()
    @State private var connectedAccount: ConnectedAccount?
    @State private var connecting = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("Connect your accounts").font(.title.bold())
                Text("Add the personal and work accounts you use.")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 40)
            .padding(.bottom, 24)

            ScrollView {
                VStack(spacing: 16) {
                    ForEach(ServiceType.allCases, id: \.self) { provider in
                        providerCard(provider)
                    }
                    if !accounts.isEmpty {
                        RefreshPreferencePicker(
                            selection: viewModel.settings.refreshIntervalMinutes,
                            onSelect: { minutes in
                                viewModel.settings.refreshIntervalMinutes = minutes
                                viewModel.saveSettings()
                            }
                        )
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 20)
            }
            Text("You can add and manage accounts later in Settings.")
                .font(.footnote).foregroundStyle(.secondary)
                .padding(.horizontal, 32).padding(.vertical, 12)
        }
        .tint(Color.brand)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in reload() }
        .onChange(of: viewModel.additionalAccounts.map(\.id)) { reload() }
        .onChange(of: viewModel.enrolledServices) { reload() }
        .sheet(item: $connectedAccount) { account in
            ConnectedAccountNameSheet(account: account, dismiss: { connectedAccount = nil }) { name, showInMenuBar in
                viewModel.saveConnectedAccount(id: account.id, name: name, showInMenuBar: showInMenuBar)
                connectedAccount = nil
                reload()
            }
        }
    }

    private func connect(_ provider: ServiceType) {
        connecting = true
        Task {
            connectedAccount = await viewModel.connectAccount(for: provider)
            connecting = false
            reload()
        }
    }

    private func providerCard(_ provider: ServiceType) -> some View {
        let providerAccounts = accounts.filter { $0.provider == provider }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(provider == .codex ? "logo-openai" : "logo-claude")
                    .resizable().scaledToFit().frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName).font(.headline)
                    Text(provider == .codex ? "ChatGPT / OpenAI" : "Anthropic / claude.ai")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
            }
            ForEach(providerAccounts) { account in
                let status = AccountConnectionStatus(account: account, viewModel: viewModel)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(account.displayLabel).fontWeight(.medium)
                        Spacer()
                        if status.connected {
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green).font(.callout)
                        } else {
                            Button("Sign In") { reconnect(account) }
                                .disabled(connecting || viewModel.isReadOnlyPreview)
                        }
                        if !status.connected && account.connectionKind == .isolated {
                            Button("Remove", role: .destructive) {
                                Task { await viewModel.removeAccount(id: account.id); reload() }
                            }
                            .disabled(connecting || viewModel.isReadOnlyPreview)
                        }
                    }
                    if let issue = status.issue {
                        Text(issue).font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack {
                Button {
                    connect(provider)
                } label: {
                    Label(providerAccounts.isEmpty ? "Add Account…" : "Add Another Account…", systemImage: "plus")
                }
                .disabled(connecting || viewModel.isRestoringSession || viewModel.isReadOnlyPreview)
                if connecting { ProgressView().controlSize(.small) }
            }
            if providerAccounts.isEmpty {
                let issue = provider == .codex ? viewModel.codexError : viewModel.claudeError
                if let issue {
                    Text(issue.localizedDescription).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }

    private func reload() { accounts = AccountRegistry.orderedAccounts() }
    private func reconnect(_ account: ConnectedAccount) {
        connecting = true
        Task {
            if account.connectionKind == .isolated { await viewModel.reconnectAccount(id: account.id) }
            else if account.provider == .codex { await viewModel.signIn() }
            else { await viewModel.signInClaude() }
            connecting = false
            reload()
        }
    }
}

private struct RefreshPreferencePicker: View {
    let selection: Int
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Refresh usage", selection: Binding(get: { selection }, set: onSelect)) {
                Text("Automatically").tag(0)
                Text("Every minute").tag(1)
                ForEach([5, 10, 30], id: \.self) { Text("Every \($0) minutes").tag($0) }
            }
            if selection == AppSettings.autoRefreshIntervalMinutes {
                Text("Checks every 5 minutes, more often near a limit, and less often when your Mac is idle.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 8)
    }
}

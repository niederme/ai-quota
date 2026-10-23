import SwiftUI
import UniformTypeIdentifiers
import AIQuotaKit

private struct AccountCardDropDelegate: DropDelegate {
    let destination: String
    @Binding var dragging: String?
    let move: (String, String) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != destination else { return }
        move(dragging, destination)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// The open panel's order also controls the menu-bar gauges. Account visibility
/// and widget choices remain independent, and the list scrolls only when needed.
struct MacAccountGridView: View {
    @Environment(QuotaViewModel.self) private var viewModel
    let width: CGFloat
    let maxHeight: CGFloat
    let openAccount: (ConnectedAccount) -> Void
    let openSettings: () -> Void
    let onScrollabilityChange: (Bool) -> Void

    @State private var orderIDs: [String] = []
    @State private var dragging: String?
    @State private var contentHeight: CGFloat?

    private var accounts: [ConnectedAccount] {
        let visible = AccountRegistry.orderedAccounts().filter { account in
            switch account.connectionKind {
            case .legacyPrimary: viewModel.enrolledServices.contains(account.provider)
            case .isolated: viewModel.additionalAccounts.contains { $0.id == account.id }
            }
        }
        let byID = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })
        let saved = orderIDs.compactMap { byID[$0] }
        let included = Set(saved.map(\.id))
        return saved + visible.filter { !included.contains($0.id) }
    }

    private var cardContentWidth: CGFloat { max(1, width - 64) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(accounts) { account in
                    MacAccountCard(account: account, session: session(for: account),
                                   tokenHistory: tokenHistory(for: account),
                                   availableWidth: cardContentWidth,
                                   showsAccountLabel: accounts.filter { $0.provider == account.provider }.count > 1,
                                   open: { openAccount(account) }, reconnect: { reconnect(account) })
                        .onDrag {
                            dragging = account.id
                            return NSItemProvider(object: account.id as NSString)
                        }
                        .onDrop(of: [UTType.plainText], delegate: AccountCardDropDelegate(
                            destination: account.id, dragging: $dragging, move: move
                        ))
                        .contextMenu {
                            Button("Refresh usage") { refresh(account) }
                            Button("Manage account in Settings", action: openSettings)
                            Divider()
                            Button("Move earlier") { move(account.id, offset: -1) }
                                .disabled(accounts.first?.id == account.id)
                            Button("Move later") { move(account.id, offset: 1) }
                                .disabled(accounts.last?.id == account.id)
                        }
                        .accessibilityAction(named: "Move earlier") { move(account.id, offset: -1) }
                        .accessibilityAction(named: "Move later") { move(account.id, offset: 1) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if height > 0, contentHeight != height { contentHeight = height }
            }
        }
        .frame(width: width, height: min(maxHeight, contentHeight ?? CGFloat(MacAccountGridLayout.viewportHeight(
            accountCount: accounts.count, width: Double(width), availableHeight: Double(maxHeight)
        ))))
        .scrollIndicators(.automatic)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentSize.height > geometry.containerSize.height + 1
        } action: { _, scrolls in
            onScrollabilityChange(scrolls)
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            orderIDs = AccountRegistry.orderedAccounts().map(\.id)
        }
        .onAppear { orderIDs = AccountRegistry.orderedAccounts().map(\.id) }
        .onChange(of: viewModel.additionalAccounts.map(\.id)) { _, _ in
            orderIDs = AccountRegistry.orderedAccounts().map(\.id)
            contentHeight = nil
        }
        .task(id: accounts.map(\.id)) { refreshTokenHistories() }
    }

    private func session(for account: ConnectedAccount) -> AdditionalAccountSession? {
        guard account.connectionKind == .isolated else { return nil }
        return viewModel.additionalAccounts.first { $0.id == account.id }
    }

    private func tokenHistory(for account: ConnectedAccount) -> CodexTokenHistory? {
        guard account.provider == .codex else { return nil }
        switch account.connectionKind {
        case .legacyPrimary:
            return viewModel.codexTokenHistory
        case .isolated:
            return session(for: account)?.codexTokenHistory
        }
    }

    private func refreshTokenHistories() {
        if viewModel.isCodexAuthenticated { viewModel.refreshTokenHistory() }
        for account in viewModel.additionalAccounts where account.provider == .codex && account.isAuthenticated {
            account.refreshTokenHistory()
        }
    }

    private func refresh(_ account: ConnectedAccount) {
        if let session = session(for: account) {
            session.refreshTokenHistory(force: true)
            Task { await session.refresh() }
        }
        else { viewModel.manualRefresh() }
    }

    private func reconnect(_ account: ConnectedAccount) {
        if let session = session(for: account) {
            Task { await viewModel.reconnectAccount(id: session.id) }
        } else if account.provider == .codex {
            Task { await viewModel.signIn() }
        } else {
            Task { await viewModel.signInClaude() }
        }
    }

    private func move(_ source: String, _ destination: String) {
        var ids = accounts.map(\.id)
        guard let from = ids.firstIndex(of: source), let to = ids.firstIndex(of: destination),
              from != to else { return }
        ids.remove(at: from)
        ids.insert(source, at: to)
        orderIDs = ids
        AccountRegistry.setAccountOrder(ids)
    }

    private func move(_ id: String, offset: Int) {
        let ids = accounts.map(\.id)
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return }
        move(id, ids[index + offset])
    }
}

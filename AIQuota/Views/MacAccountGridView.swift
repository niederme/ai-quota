import SwiftUI
import AIQuotaKit

/// A card reorder in progress. Everything is measured once when the drag
/// begins, so nothing re-lays out under the pointer until the card is dropped.
private struct CardDrag {
    let id: String
    let order: [String]
    let frames: [String: CGRect]
    var translation: CGFloat = 0

    var from: Int { order.firstIndex(of: id) ?? 0 }
    var frame: CGRect { frames[id] ?? .zero }
    var target: Int {
        MacAccountGridLayout.reorderTarget(from: from, draggedMidY: Double(frame.midY + translation),
                                           midYs: order.map { Double(frames[$0]?.midY ?? 0) })
    }
}

/// The open panel's order also controls the menu-bar gauges. Account visibility
/// and widget choices remain independent, and the list scrolls only when needed.
struct MacAccountGridView: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let width: CGFloat
    let maxHeight: CGFloat
    let openAccount: (ConnectedAccount) -> Void
    let openSettings: () -> Void
    let leadingContent: AnyView
    let connect: (ServiceType) -> Void

    @State private var orderIDs: [String] = []
    @State private var drag: CardDrag?
    @State private var cardFrames: [String: CGRect] = [:]
    @State private var dragEndedAt: Date = .distantPast
    @State private var contentHeight: CGFloat?
    @State private var hoveredRowID: String?
    @FocusState private var focusedRowID: String?
    @State private var scrollEdges = ScrollEdges()

    private struct ScrollEdges: Equatable {
        var top = false
        var bottom = false
    }

    private func highlight(_ id: String) -> Bool { (hoveredRowID ?? focusedRowID) == id }
    private func hover(_ id: String, _ inside: Bool) {
        if inside { hoveredRowID = id }
        else if hoveredRowID == id { hoveredRowID = nil }
    }

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
            VStack(alignment: .leading, spacing: 0) {
                leadingContent
                VStack(alignment: .leading, spacing: CGFloat(MacAccountGridLayout.cardSpacing)) {
                    if accounts.isEmpty {
                        ForEach([ServiceType.codex, .claude], id: \.self) { service in
                            MacAccountPlaceholderRow(service: service, availableWidth: cardContentWidth,
                                                     highlighted: highlight(service.rawValue),
                                                     connect: { connect(service) })
                                .focused($focusedRowID, equals: service.rawValue)
                                .onHover { hover(service.rawValue, $0) }
                        }
                    }
                    ForEach(accounts) { account in
                        MacAccountCard(account: account, session: session(for: account),
                                       tokenHistory: tokenHistory(for: account),
                                       availableWidth: cardContentWidth,
                                       showsAccountLabel: accounts.filter { $0.provider == account.provider }.count > 1,
                                       open: { unlessJustDragged { openAccount(account) } },
                                       reconnect: { unlessJustDragged { reconnect(account) } },
                                       highlighted: highlight(account.id) || drag?.id == account.id)
                            .focused($focusedRowID, equals: account.id)
                            .onHover { hover(account.id, $0) }
                            .scaleEffect(drag?.id == account.id ? 1.02 : 1)
                            .shadow(color: .black.opacity(drag?.id == account.id ? 0.18 : 0), radius: 12, y: 4)
                            .offset(y: dragOffset(for: account.id))
                            .zIndex(drag?.id == account.id ? 1 : 0)
                            // The lifted card tracks the pointer exactly; only the others glide.
                            .transaction { if drag?.id == account.id { $0.animation = nil } }
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.cardSpace)) } action: { frame in
                                cardFrames[account.id] = frame
                            }
                            // A plain SwiftUI drag rather than .onDrag/.onDrop. System
                            // drag-and-drop never reordered cards in the menu-bar panel.
                            .simultaneousGesture(reorderGesture(for: account.id),
                                                 including: accounts.count > 1 ? .all : .subviews)
                            .contextMenu {
                                if viewModel.recoveryAction(for: account) == .reconnect {
                                    Button("Reconnect") { reconnect(account) }
                                }
                                Button("Refresh usage") { refresh(account) }
                                    .disabled(viewModel.recoveryAction(for: account) == .reconnect)
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
                .coordinateSpace(.named(Self.cardSpace))
                .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: drag?.target)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if height > 0, contentHeight != height { contentHeight = height }
            }
        }
        .frame(width: width, height: min(maxHeight, contentHeight ?? CGFloat(MacAccountGridLayout.viewportHeight(
            accountCount: accounts.count, width: Double(width), availableHeight: Double(maxHeight)
        ))))
        .scrollIndicators(.automatic)
        .onScrollGeometryChange(for: ScrollEdges.self) { geometry in
            let overflow = geometry.contentSize.height > geometry.containerSize.height + 1
            return ScrollEdges(top: overflow && geometry.contentOffset.y > 1,
                               bottom: overflow && geometry.contentOffset.y + geometry.containerSize.height
                                   < geometry.contentSize.height - 1)
        } action: { _, edges in
            scrollEdges = edges
        }
        .mask {
            GeometryReader { geometry in
                let fade = min(0.5, 24 / max(1, geometry.size.height))
                LinearGradient(stops: [
                    .init(color: scrollEdges.top ? .clear : .black, location: 0),
                    .init(color: .black, location: scrollEdges.top ? fade : 0),
                    .init(color: .black, location: scrollEdges.bottom ? 1 - fade : 1),
                    .init(color: scrollEdges.bottom ? .clear : .black, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).receive(on: RunLoop.main)) { _ in
            // Usage refreshes write defaults too; don't reshuffle under a drag.
            guard drag == nil else { return }
            orderIDs = AccountRegistry.orderedAccounts().map(\.id)
        }
        .onDisappear { hoveredRowID = nil; focusedRowID = nil; drag = nil }
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
            Task { await session.refresh(userInitiated: true) }
        }
        else { viewModel.manualRefresh() }
    }

    private func reconnect(_ account: ConnectedAccount) {
        Task { await viewModel.reconnect(account) }
    }

    private static let cardSpace = "MacAccountCards"

    private func dragOffset(for id: String) -> CGFloat {
        guard let drag else { return 0 }
        if drag.id == id { return drag.translation }
        guard let index = drag.order.firstIndex(of: id) else { return 0 }
        let shift = MacAccountGridLayout.reorderShift(of: index, dragging: drag.from, to: drag.target)
        return CGFloat(shift) * (drag.frame.height + CGFloat(MacAccountGridLayout.cardSpacing))
    }

    private func reorderGesture(for id: String) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.cardSpace))
            .onChanged { value in
                if drag?.id != id {
                    drag = CardDrag(id: id, order: accounts.map(\.id), frames: cardFrames)
                }
                guard var current = drag else { return }
                // Keep the lifted card within the list.
                let ordered = current.order.compactMap { current.frames[$0] }
                let top = (ordered.first?.minY ?? current.frame.minY) - current.frame.minY
                let bottom = (ordered.last?.maxY ?? current.frame.maxY) - current.frame.maxY
                current.translation = min(max(value.translation.height, top), bottom)
                drag = current
            }
            .onEnded { _ in
                guard let finished = drag, finished.id == id else { return }
                dragEndedAt = .now
                let ids = MacAccountGridLayout.reordered(finished.order, from: finished.from, to: finished.target)
                // Layout moves to the new order as the offsets return to zero, so
                // the other cards stay put and the dropped card settles into its slot.
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                    orderIDs = ids
                    drag = nil
                }
                if ids != finished.order { AccountRegistry.setAccountOrder(ids) }
            }
    }

    /// A mouse-up that ends a drag can also land as a tap on the card.
    private func unlessJustDragged(_ action: () -> Void) {
        guard drag == nil, Date.now.timeIntervalSince(dragEndedAt) > 0.3 else { return }
        action()
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

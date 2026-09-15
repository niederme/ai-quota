import SwiftUI
import MobileAccessCore

struct OverviewView: View {
    @AppStorage("refreshIntervalMinutes") private var refreshMinutes = 0
    @State private var onboarding = OnboardingProgress()
    @State private var showOnboarding = false
    @State private var codex = ProbeModel()
    @State private var navigationID = UUID()
    @State private var showCodex = false
    @State private var showClaude = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var claude = ClaudeProbeModel()
    @State private var existingInstallation = UserDefaults.standard.data(forKey: "mobileProbe.codexReading") != nil
        || UserDefaults.standard.data(forKey: "mobileProbe.claudeReading") != nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .firstTextBaseline) {
                            overviewFreshness
                            Spacer(minLength: 16)
                            gaugeKey.font(.subheadline)
                        }
                        .padding(.horizontal, 12)
                        EqualHeightCardStack(spacing: 16) {
                            ProviderDialCard(name: "Codex", icon: "logo-openai", availableWidth: min(geometry.size.width, 780) - 40, reading: codex.reading,
                                             connected: codex.connected, busy: codex.busy, error: codex.error, failure: codex.connectionFailure) {
                                ProbeView(model: codex)
                            }
                            ProviderDialCard(name: "Claude Code", icon: "logo-claude", availableWidth: min(geometry.size.width, 780) - 40, reading: claude.reading,
                                             connected: claude.connected, busy: claude.busy, error: claude.error, failure: claude.connectionFailure) {
                                ClaudeProbeView(model: claude)
                            }
                        }

                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 20)
                    .frame(maxWidth: 780)
                    .frame(maxWidth: .infinity)
                }
                .refreshable {
                    async let first: Void = codex.refreshAndWait()
                    async let second: Void = claude.refreshAndWait()
                    _ = await (first, second)
                }
                .background(Color(uiColor: .systemGroupedBackground))
            }
            .navigationTitle("AI Quota")
            .toolbarTitleDisplayMode(.inlineLarge)
            .navigationDestination(isPresented: $showCodex) { ProbeView(model: codex) }
            .navigationDestination(isPresented: $showClaude) { ClaudeProbeView(model: claude) }
            .onOpenURL { url in
                guard url.scheme == "aiquota-probe" else { return }
                if url.host == "overview" {
                    showCodex = false
                    showClaude = false
                    navigationID = UUID()
                    codex.refreshOnOpen()
                    claude.refreshOnOpen()
                }
                if url.host == "codex" { showCodex = true; codex.refreshOnOpen() }
                if url.host == "claude" { showClaude = true; claude.refreshOnOpen() }
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                codex.refreshOnOpen()
                claude.refreshOnOpen()
                await MobileResetNotifications.reconcile()
            }
            .task(id: "\(scenePhase)-\(refreshMinutes)") {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    let windows = [codex.reading?.shortTerm, codex.reading?.weekly,
                                   claude.reading?.shortTerm, claude.reading?.weekly]
                    let nearLimit = windows.compactMap { $0?.usedPercent }.contains { $0 >= 85 }
                    let minutes = refreshMinutes == 0 ? (nearLimit ? 1 : 5) : max(1, refreshMinutes)
                    do { try await Task.sleep(for: .seconds(minutes * 60)) }
                    catch { return }
                    async let first: Void = codex.refreshAndWait()
                    async let second: Void = claude.refreshAndWait()
                    _ = await (first, second)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        codex.refresh()
                        claude.refresh()
                    } label: {
                        ZStack {
                            Image(systemName: "arrow.clockwise").opacity(codex.busy || claude.busy ? 0 : 1)
                            ProgressView().opacity(codex.busy || claude.busy ? 1 : 0)
                        }.frame(width: 24, height: 24)
                    }
                    .disabled(codex.busy || claude.busy)
                    .accessibilityLabel(codex.busy || claude.busy ? "Refreshing usage" : "Refresh usage")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        MobileSettingsView(codex: codex, claude: claude, onboarding: onboarding)
                    } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
                }
            }
        }.id(navigationID).tint(Color(uiColor: .systemPurple))
        .task {
            showOnboarding = onboarding.shouldPresent(
                hasExistingAccount: codex.connected || claude.connected
                    || codex.reading != nil || claude.reading != nil,
                hasExistingInstallation: existingInstallation)
        }
        .sheet(isPresented: $showOnboarding, onDismiss: { onboarding.dismiss() }) {
            OnboardingView(codex: codex, claude: claude, progress: onboarding)
        }
    }
    private var overviewFreshness: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let readings = [codex.reading, claude.reading].compactMap { $0 }
            let oldest = readings.map(\.fetchedAt).min()
            Text(codex.busy || claude.busy ? "Refreshing…" : oldest.map {
                overviewFreshnessLabel($0, at: context.date,
                    saved: codex.error != nil || claude.error != nil
                        || codex.connectionFailure != nil || claude.connectionFailure != nil)
            } ?? "No reading yet")
            .font(.caption).foregroundStyle(.secondary)
            .accessibilityLabel("Usage freshness")
            .accessibilityValue(oldest.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "No reading yet")
        }
    }

    private var gaugeKey: some View {
        HStack(spacing: 12) {
            Label("5h", systemImage: "circle.fill").foregroundStyle(Color(uiColor: .systemPurple))
                .accessibilityLabel("Outer ring: five-hour allowance")
            Label("7d", systemImage: "circle.fill").foregroundStyle(Color(uiColor: .systemPurple).opacity(0.5))
                .accessibilityLabel("Inner ring: seven-day allowance")
        }.labelStyle(GaugeKeyStyle()).fontWeight(.bold)
    }

}

/// Measure both cards before placement, including at accessibility text sizes.
/// Each card reserves its ordinary metadata/status space, so refreshing does not
/// change this shared height. Longer connection errors can grow both together.
struct EqualHeightCardStack: Layout {
    var spacing: CGFloat = 16

    private func cardSize(_ proposal: ProposedViewSize, _ subviews: Subviews) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)) }
        return CGSize(width: proposal.width ?? sizes.map(\.width).max() ?? 0,
                      height: sizes.map(\.height).max() ?? 0)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = cardSize(proposal, subviews)
        return CGSize(width: size.width, height: size.height * CGFloat(subviews.count) + spacing * CGFloat(max(0, subviews.count - 1)))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let size = cardSize(ProposedViewSize(width: bounds.width, height: nil), subviews)
        for (index, view) in subviews.enumerated() {
            view.place(at: CGPoint(x: bounds.minX, y: bounds.minY + CGFloat(index) * (size.height + spacing)),
                       anchor: .topLeading, proposal: ProposedViewSize(size))
        }
    }
}

struct ProviderDialCard<Destination: View>: View {
    let name: String
    let icon: String
    let availableWidth: CGFloat
    let reading: QuotaReading?
    let connected: Bool
    let busy: Bool
    let error: String?
    var failure: SharedQuotaStore.Failure? = nil
    @ViewBuilder let destination: () -> Destination
    var body: some View {
        ProviderDialCardContent(name: name, icon: icon, availableWidth: availableWidth,
            reading: reading, connected: connected, busy: busy, error: error, failure: failure,
            accountDestination: AnyView(destination()))
    }
}

struct ProviderDialCardContent: View {
    let name: String
    let icon: String
    let availableWidth: CGFloat
    let reading: QuotaReading?
    let connected: Bool
    let busy: Bool
    let error: String?
    var failure: SharedQuotaStore.Failure? = nil
    var accountDestination: AnyView? = nil
    @State var info: MetadataExplanation?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var worst: Double { max(reading?.shortTerm?.usedPercent ?? 0, reading?.weekly?.usedPercent ?? 0) }
    private var tint: Color {
        if failure != nil || error != nil || !connected { return .secondary }
        if worst >= 95 { return Color(uiColor: .systemRed) }
        if worst >= 85 { return Color(uiColor: .systemOrange) }
        return Color(uiColor: .systemPurple)
    }
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var resetLineHeight = 18.0
    @ScaledMetric(relativeTo: .body) private var dialSize = 148.0
    private var usageColumnWidth: CGFloat { max(min(dialSize, 300), (availableWidth - 40 - 33) * 2 / 3) }
    private var usesColumns: Bool { !typeSize.isAccessibilitySize && availableWidth >= min(dialSize, 300) + 40 + 33 + 88 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if usesColumns {
                HStack(alignment: .top, spacing: 33) {
                    linkedIdentity.frame(width: usageColumnWidth)
                    accountMetadata.frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color(uiColor: .separator)).frame(width: 1)
                        .offset(x: usageColumnWidth + 16)
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }
            } else {
                linkedIdentity.frame(maxWidth: .infinity)
                Divider()
                accountMetadata
            }
        }
        .opacity(connected ? 1 : 0)
        .allowsHitTesting(connected)
        .accessibilityHidden(!connected)
        .overlay {
            if !connected { disconnectedContent }
        }
        .padding(20)
        .frame(minHeight: 260)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(colorScheme == .dark ? Color(uiColor: .quaternarySystemFill) : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

    }
    private var disconnectedContent: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().trim(from: 0, to: 0.75)
                    .stroke(Color(uiColor: .tertiarySystemFill), lineWidth: 9)
                Circle().trim(from: 0, to: 0.75)
                    .stroke(Color(uiColor: .tertiarySystemFill), lineWidth: 7)
                    .padding(10)
            }
            .rotationEffect(.degrees(135))
            .overlay {
                Image(icon).resizable().scaledToFit()
                    .frame(width: 28, height: 28).foregroundStyle(.secondary)
            }
            .frame(width: min(dialSize, 220), height: min(dialSize, 220))
            .padding(.bottom, -min(dialSize, 220) * 0.16)
            .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text(name).font(.headline.bold())
                Text("Not connected").font(.subheadline).foregroundStyle(.secondary)
            }
            if let accountDestination {
                NavigationLink { accountDestination } label: {
                    Text("Connect").fontWeight(.semibold)
                        .frame(minHeight: 32).padding(.horizontal, 12)
                }
                .buttonStyle(.bordered)
                .tint(Color(uiColor: .systemPurple))
                .accessibilityLabel("Connect \(name)")
                .accessibilityHint("Opens sign-in for \(name)")
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    @ViewBuilder private var linkedIdentity: some View {
        if let accountDestination {
            NavigationLink { accountDestination } label: { identity }
                .buttonStyle(.plain)
                .accessibilityHint("Opens \(name) account details")
        } else { identity }
    }
    private var identity: some View {
        VStack(spacing: 4) {
            dial
                // Reclaim the empty bottom of the partial-circle bounds.
                .padding(.bottom, -min(dialSize, 300) * 0.08)
            Text(name).font(.headline.bold())
                .multilineTextAlignment(.center)
                .frame(width: min(dialSize, 300))
            VStack(spacing: 1) {
                resetCaption(reading?.shortTerm, label: "5h")
                resetCaption(reading?.weekly, label: "7d")
            }.padding(.top, 2).frame(width: usesColumns ? usageColumnWidth : min(dialSize, 300))
        }
    }
    private var dial: some View {
        ZStack {
            arc(reading?.shortTerm, width: 9, opacity: 1)
            arc(reading?.weekly, width: 7, opacity: contrast == .increased ? 0.85 : (worst >= 85 ? 0.65 : 0.45))
                .padding(10)
            VStack(spacing: 5) {
                Image(icon).resizable().scaledToFit()
                    .frame(width: 22, height: 22)
                dialValue(reading?.shortTerm, label: "5h")
                    .font(.headline.monospacedDigit())
                dialValue(reading?.weekly, label: "7d")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .opacity(contrast == .increased ? 0.9 : 0.7)
            }
            .foregroundStyle(tint)
        }
        .padding(6)
        .frame(width: min(dialSize, 300), height: min(dialSize, 300))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) allowance used")
        .accessibilityValue("5 hours: \(accessibleValue(reading?.shortTerm)). 7 days: \(accessibleValue(reading?.weekly)).")
    }
    private func dialValue(_ window: QuotaWindow?, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            if let window { Text("\(window.usedPercent, specifier: "%.0f")%") }
            else { Text("N/A") }
            Text(label)
        }
        .foregroundStyle(window == nil ? Color.secondary : tint)
    }
    private func accessibleValue(_ window: QuotaWindow?) -> String {
        window.map { "\(Int($0.usedPercent.rounded())) percent" } ?? "not reported"
    }
    private var connectionStatus: some View {
        ZStack(alignment: .topLeading) {
            Text("Reconnect Claude Code · Tap to sign in").hidden()
            Group {
                if failure == .reconnect || failure == .renewal {
                    Text("Reconnect \(name) · Tap to sign in").foregroundStyle(Color(uiColor: .systemOrange))
                } else if !connected { Text("Connect \(name) · Tap to sign in") }
                else if error != nil || failure != nil { Text("Couldn’t update · Tap to retry") }
                else if reading == nil { Text("No reading yet") }
                else if worst >= 100 { Text("Limit reached").fontWeight(.semibold) }
            }
        }.font(.caption).foregroundStyle(.secondary)
    }
    private var accountMetadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    metadataRow("Plan", value: "Not reported", explanation: .plan, interactive: false)
                    metadataRow("Credit balance", value: "$999.99")
                    metadataRow("Credits used", value: "$999.99", spending: true, explanation: .claudeSpend, interactive: false)
                }.hidden().accessibilityHidden(true).allowsHitTesting(false)
                reportedMetadata
            }
            if let accountDestination {
                NavigationLink { accountDestination } label: { connectionStatus }
                    .buttonStyle(.plain)
            } else { connectionStatus }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var reportedMetadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            let data = reading?.metadata
            metadataRow("Plan", value: data?.displayPlan ?? "Not reported",
                explanation: data?.displayPlan == nil ? .plan : nil)
            if let balance = data?.balanceUSD {
                metadataRow("Credit balance", value: balance.formatted(.currency(code: "USD")))
            }
            if let spent = data?.usageSpent {
                let amount = data?.usageCurrency.map { spent.formatted(.currency(code: $0)) }
                    ?? spent.formatted(.number.precision(.fractionLength(0...2))) + " credits"
                metadataRow("Credits used",
                    value: amount, spending: true,
                    explanation: name == "Codex" ? .codexSpend : .claudeSpend)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func metadataRow(_ label: String, value: String, spending: Bool = false,
                             explanation: MetadataExplanation? = nil, interactive: Bool = true) -> some View {
        let fields = Group {
            Group {
                if explanation != nil {
                    Text("\(label) \(Image(systemName: "info.circle"))")
                } else {
                    Text(label)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(spending ? Color(uiColor: .systemOrange) : .secondary)
            Text(value).fontWeight(.medium).monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(spending ? Color(uiColor: .systemOrange) : (value == "Not reported" ? .secondary : .primary))
        }
        let content = ViewThatFits(in: .horizontal) {
            if !spending {
                HStack(alignment: .firstTextBaseline, spacing: 5) { fields }
                    .fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: spending ? -2 : 2) { fields }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, minHeight: explanation != nil ? 44 : 32, alignment: .leading)
        .contentShape(Rectangle())
        return Group {
            if let explanation, interactive {
                Button { info = explanation } label: { content }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("metadata-info-\(explanation.rawValue)")
                    .accessibilityLabel("\(label): \(value). \(explanation.title)")
                    .accessibilityHint("Shows more information")
                    .popover(isPresented: Binding(get: { info == explanation }, set: { if !$0 { info = nil } }),
                             attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(explanation.title).font(.headline)
                            Text(explanation.message).font(.subheadline)
                        }.padding(20).frame(idealWidth: 300, maxWidth: 340)
                            .fixedSize(horizontal: false, vertical: true)
                            .presentationCompactAdaptation(.popover)
                    }
            } else { content }
        }
    }
    private func resetCaption(_ window: QuotaWindow?, label: String) -> some View {
        let text: String = {
            guard let window else { return "\(label) not reported" }
            guard let reset = window.resetsAt else { return "\(label) reset unavailable" }
            if reset <= .now { return "\(label) reset unconfirmed" }
            let format: Date.FormatStyle = Calendar.current.isDateInToday(reset)
                ? .dateTime.hour().minute() : .dateTime.weekday(.abbreviated).hour().minute()
            return "\(label) resets \(reset.formatted(format))"
        }()
        return Text(text).font(.subheadline.weight(.semibold))
            .foregroundStyle(window == nil ? Color.secondary : tint.opacity(label == "5h" ? 1 : (contrast == .increased ? 0.85 : 0.5)))
            .multilineTextAlignment(.center)
            .lineLimit(typeSize.isAccessibilitySize ? 2 : 1).minimumScaleFactor(0.85)
            .frame(height: resetLineHeight * (typeSize.isAccessibilitySize ? 2 : 1))
    }
    private func arc(_ window: QuotaWindow?, width: CGFloat, opacity: Double) -> some View {
        ZStack {
            Circle().trim(from: 0, to: 0.75)
                .stroke(Color(uiColor: .tertiarySystemFill), style: StrokeStyle(lineWidth: width, lineCap: .butt))
            if let window {
                Circle().trim(from: 0, to: 0.75 * min(100, max(0, window.usedPercent)) / 100)
                    .stroke(tint.opacity(opacity), style: StrokeStyle(lineWidth: width, lineCap: .butt))
            }
        }.rotationEffect(.degrees(135))
    }
}

private struct GaugeKeyStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.icon.font(.system(size: 6)); configuration.title }
    }
}

enum MetadataExplanation: String, Identifiable {
    case plan, codexSpend, claudeSpend
    var id: String { rawValue }
    var title: String {
        switch self {
        case .plan: "Plan not reported"
        case .codexSpend: "Estimated Monthly Spend"
        case .claudeSpend: "Fable 5 & Post-Limit Usage"
        }
    }
    private var currentMonthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: .now)
    }
    var message: String {
        switch self {
        case .plan: "The latest account refresh did not report a recognized plan name. Your allowance gauges use the limits the provider reports."
        case .codexSpend: "AIQuota sums \(currentMonthName)’s usage-credit events and converts them at 25 credits = $1."
        case .claudeSpend: "Claude reports both as one monthly total and doesn’t provide a reliable breakdown."
        }
    }
}

private func overviewFreshnessLabel(_ fetchedAt: Date, at now: Date, saved: Bool) -> String {
    let elapsed = max(0, Int(now.timeIntervalSince(fetchedAt)))
    let relative = elapsed < 60 ? "Just now" : elapsed < 3600 ? "\(elapsed / 60)m ago" : "\(elapsed / 3600)h ago"
    if saved { return "Saved · \(relative)" }
    if elapsed >= 1800 { return "Older reading · \(relative)" }
    return relative
}

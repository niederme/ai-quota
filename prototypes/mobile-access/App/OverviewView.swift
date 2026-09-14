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
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("AI Quota").font(.largeTitle.bold())
                                Spacer(minLength: 16)
                                gaugeKey.font(.title3)
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                Text("AI Quota").font(.largeTitle.bold())
                                gaugeKey.font(.title3)
                            }
                        }
                        EqualHeightCardStack(spacing: 16) {
                            ProviderDialCard(name: "Codex", icon: "logo-openai", availableWidth: min(geometry.size.width, 780) - 40, reading: codex.reading,
                                             connected: codex.connected, busy: codex.busy, error: codex.error) {
                                ProbeView(model: codex)
                            }
                            ProviderDialCard(name: "Claude", icon: "logo-claude", availableWidth: min(geometry.size.width, 780) - 40, reading: claude.reading,
                                             connected: claude.connected, busy: claude.busy, error: claude.error, failure: claude.connectionFailure) {
                                ClaudeProbeView(model: claude)
                            }
                        }

                    }
                    .padding(20)
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
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
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
        NavigationLink(destination: destination) {
            ProviderDialCardContent(name: name, icon: icon, availableWidth: availableWidth,
                reading: reading, connected: connected, busy: busy, error: error, failure: failure)
        }
        .buttonStyle(.plain)
        .accessibilityHint(connected ? "Opens \(name) account details" : "Connect \(name)")
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
    @ScaledMetric(relativeTo: .body) private var dialSize = 136.0

    var body: some View {
        Group {
            // Choose columns from the available space, not the text's unwrapped ideal width.
            if !typeSize.isAccessibilitySize && availableWidth >= min(dialSize, 300) + 16 + 120 + 40 {
                HStack(alignment: .top, spacing: 16) {
                    identity
                    details.frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    identity.frame(maxWidth: .infinity, alignment: .leading)
                    details
                }
            }
        }
        .padding(20)
        .frame(minHeight: 218)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(colorScheme == .dark ? Color(uiColor: .quaternarySystemFill) : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
    private var identity: some View {
        VStack(spacing: 4) {
            dial
                // Reclaim the empty bottom of the partial-circle bounds.
                .padding(.bottom, -min(dialSize, 300) * 0.08)
            Text(name).font(.title3.bold())
                .multilineTextAlignment(.center)
                .frame(width: min(dialSize, 300))
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
            else { Text("—") }
            Text(label)
        }
    }
    private func accessibleValue(_ window: QuotaWindow?) -> String {
        window.map { "\(Int($0.usedPercent.rounded())) percent" } ?? "not reported"
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            if failure == .reconnect || failure == .renewal {
                Label(failure == .reconnect ? "Reconnect \(name)" : "Sign-in renewal failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline).foregroundStyle(Color(uiColor: .systemOrange))
                Text(failure == .renewal ? "Tap to retry or reconnect" : "Tap to sign in again")
                    .font(.caption).foregroundStyle(.secondary)
            } else if !connected {
                Label("Connect \(name)", systemImage: "person.crop.circle.badge.exclamationmark").font(.headline)
            } else if error != nil {
                Label("Couldn’t update usage", systemImage: "exclamationmark.triangle").font(.headline)
            }
            if error != nil || failure != nil { Text("Last saved usage").font(.caption).foregroundStyle(.secondary) }
            VStack(alignment: .leading, spacing: 10) {
                resetCaption(reading?.shortTerm, label: "5h")
                resetCaption(reading?.weekly, label: "7d")
            }
            accountMetadata
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(alignment: .leading, spacing: 4) {
                    if error != nil || failure != nil { Text("Limit reached").fontWeight(.semibold).hidden() }
                    else if !connected { Text("Not connected") }
                    else if reading == nil { Text("No reading yet") }
                    else if worst >= 100 { Text("Limit reached").fontWeight(.semibold) }
                    else { Text("Limit reached").fontWeight(.semibold).hidden() }
                    ZStack(alignment: .topLeading) {
                        Text("Older reading · 59m ago").hidden()
                        if busy { Text("Refreshing…") }
                        else if let reading {
                            Text(freshnessLabel(reading.fetchedAt, at: context.date))
                                .accessibilityLabel("Last updated: \(freshnessLabel(reading.fetchedAt, at: context.date))")
                        }
                    }
                }.font(.caption).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    private func freshnessLabel(_ fetchedAt: Date, at now: Date) -> String {
        let elapsed = max(0, Int(now.timeIntervalSince(fetchedAt)))
        let relative = elapsed < 10 ? "Just now" : elapsed < 60 ? "\(elapsed)s ago"
            : elapsed < 3600 ? "\(elapsed / 60)m ago" : "\(elapsed / 3600)h ago"
        if error != nil || failure != nil { return "Saved · \(relative)" }
        if elapsed >= 1800 { return "Older reading · \(relative)" }
        return relative
    }
    private var accountMetadata: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().padding(.vertical, 2).opacity(reading?.metadata == nil ? 0 : 1)
            ZStack(alignment: .topLeading) {
                // Reserve all three rows, even when a provider omits billing
                // fields on a refresh. Hidden placeholders are not accessible.
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                    metadataRow("Plan", value: "Plus")
                    metadataRow("Balance", value: "$0.00")
                    metadataRow("This month", value: "$0.00")
                }.hidden()
                reportedMetadata
            }.padding(.vertical, 4)
        }
    }
    @ViewBuilder private var reportedMetadata: some View {
        if let data = reading?.metadata {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                if let plan = data.plan { metadataRow("Plan", value: plan.capitalized) }
                if let balance = data.balanceUSD { metadataRow("Balance", value: balance.formatted(.currency(code: "USD"))) }
                if let spent = data.usageSpent {
                    metadataRow(name == "Codex" ? "This month" : "Credits used", value: data.usageCurrency.map { spent.formatted(.currency(code: $0)) }
                        ?? spent.formatted(.number.precision(.fractionLength(0...2))) + " credits", spending: true)
                }
            }
        }
    }
    private func metadataRow(_ label: String, value: String, spending: Bool = false) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Text(value).fontWeight(.semibold)
                .foregroundStyle(spending ? Color(uiColor: .systemOrange) : .primary)
        }.font(.caption).fixedSize(horizontal: false, vertical: true)
    }
    private func resetCaption(_ window: QuotaWindow?, label: String) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(label) last reported reset")
                Text("Wed 12:00 AM")
            }.hidden()
            VStack(alignment: .leading, spacing: 2) {
                if let reset = window?.resetsAt {
                    Text(reset <= Date.now ? "\(label) last reported reset" : "\(label) resets")
                    Text(reset.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                } else {
                    Text(window == nil ? "\(label) not reported" : "\(label) reset unavailable")
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(tint.opacity(contrast == .increased ? 1 : (label == "5h" ? (worst >= 85 ? 1 : 0.85) : (worst >= 85 ? 0.75 : 0.65))))
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

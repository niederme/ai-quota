import SwiftUI
import Charts
import MobileAccessCore

struct OverviewView: View {
    @AppStorage("refreshIntervalMinutes") private var refreshMinutes = 0
    @State private var onboarding = OnboardingProgress()
    @State private var showOnboarding = false
    @State private var codex = ProbeModel()
    @State private var navigationID = UUID()
    @State private var selectedService: OverviewService?
    @Environment(\.scenePhase) private var scenePhase
    @State private var claude = ClaudeProbeModel()
    @State private var existingInstallation = UserDefaults.standard.data(forKey: "mobileProbe.codexReading") != nil
        || UserDefaults.standard.data(forKey: "mobileProbe.claudeReading") != nil

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ProviderDialCard(name: "Codex", icon: "logo-openai", availableWidth: min(geometry.size.width, 780) - 32, reading: codex.reading,
                                         connected: codex.connected, busy: codex.busy, error: codex.error, failure: codex.connectionFailure,
                                         history: codex.history, historyUnavailable: codex.historyUnavailable) {
                            selectedService = .codex
                        }
                        ProviderDialCard(name: "Claude", icon: "logo-claude", availableWidth: min(geometry.size.width, 780) - 32, reading: claude.reading,
                                         connected: claude.connected, busy: claude.busy, error: claude.error, failure: claude.connectionFailure) {
                            selectedService = .claude
                        }
                        overviewFreshness.frame(maxWidth: .infinity)

                    }
                    .padding(.horizontal, 16)
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
                .background { OverviewBackground().ignoresSafeArea() }
            }
            .navigationTitle("AI Quota")
            .toolbarTitleDisplayMode(.inlineLarge)
            .onOpenURL { url in
                guard url.scheme == "aiquota-probe" else { return }
                if url.host == "overview" {
                    selectedService = nil
                    navigationID = UUID()
                    codex.refreshOnOpen()
                    claude.refreshOnOpen()
                }
                if url.host == "codex" { selectedService = .codex; codex.refreshOnOpen() }
                if url.host == "claude" { selectedService = .claude; claude.refreshOnOpen() }
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
                    .tint(OverviewStyle.primary)
                    .disabled(codex.busy || claude.busy)
                    .accessibilityLabel(codex.busy || claude.busy ? "Refreshing usage" : "Refresh usage")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { selectedService = .settings } label: { Image(systemName: "gearshape") }
                    .tint(OverviewStyle.primary)
                    .accessibilityLabel("Settings")
                }
            }
        }.id(navigationID).tint(OverviewStyle.accent)
        .task {
            showOnboarding = onboarding.shouldPresent(
                hasExistingAccount: codex.connected || claude.connected
                    || codex.reading != nil || claude.reading != nil,
                hasExistingInstallation: existingInstallation)
        }
        .sheet(item: $selectedService) { service in
            ServiceAccountSheet(showsClose: service == .settings) {
                switch service {
                case .settings:
                    MobileSettingsView(codex: codex, claude: claude, onboarding: onboarding)
                case .codex:
                    ServiceDetailContent(name: "Codex", icon: "logo-openai", reading: codex.reading,
                        connected: codex.connected, busy: codex.busy, error: codex.error,
                        failure: codex.connectionFailure, history: codex.history, refresh: { codex.refresh() }) { ProbeView(model: codex) }
                case .claude:
                    ServiceDetailContent(name: "Claude", icon: "logo-claude", reading: claude.reading,
                        connected: claude.connected, busy: claude.busy, error: claude.error,
                        failure: claude.connectionFailure, refresh: { claude.refresh() }) { ClaudeProbeView(model: claude) }
                }
            }
        }
        .sheet(isPresented: $showOnboarding, onDismiss: { onboarding.dismiss() }) {
            OnboardingView(codex: codex, claude: claude, progress: onboarding)
        }
    }
    private var overviewFreshness: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let failed = codex.error != nil || codex.connectionFailure != nil
                || claude.error != nil || claude.connectionFailure != nil
            VStack(spacing: 4) {
                if failed {
                    freshness("Codex", reading: codex.reading, connected: codex.connected, busy: codex.busy,
                              failed: codex.error != nil || codex.connectionFailure != nil, at: context.date)
                    freshness("Claude", reading: claude.reading, connected: claude.connected, busy: claude.busy,
                              failed: claude.error != nil || claude.connectionFailure != nil, at: context.date)
                } else if codex.busy || claude.busy {
                    Text("Refreshing…")
                } else if let oldest = [codex.reading, claude.reading].compactMap({ $0?.fetchedAt }).min() {
                    Text(overviewFreshnessLabel(oldest, at: context.date, saved: false)
                        .replacingOccurrences(of: "Updated", with: "Refreshed")
                        .replacingOccurrences(of: "Older reading ·", with: "Refreshed"))
                } else {
                    Text("No usage received yet")
                }
            }
            .font(.footnote).foregroundStyle(OverviewStyle.secondary)
            .multilineTextAlignment(.center)
        }
    }
    @ViewBuilder private func freshness(_ name: String, reading: QuotaReading?, connected: Bool,
                                        busy: Bool, failed: Bool, at now: Date) -> some View {
        if connected || reading != nil {
            if busy {
                Text("\(name) refreshing…")
            } else if let reading {
                let updated = overviewFreshnessLabel(reading.fetchedAt, at: now, saved: failed)
                Text(failed ? "\(name) couldn’t update · \(updated)" : "\(name) \(updated.lowercased())")
            } else {
                Text("\(name) · No usage received yet")
            }
        }
    }



}

private enum OverviewService: String, Identifiable {
    case codex, claude, settings
    var id: String { rawValue }
}

struct AccountConnectionForm: View {
    let plan: String?
    let updated: Date?
    let busy: Bool
    let needsReconnect: Bool
    let error: String?
    var updatesPaused = false
    let retry: () -> Void
    let reconnect: () -> Void
    let disconnect: () -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent("Status", value: needsReconnect ? "Sign-in required" : "Connected")
                if let plan { LabeledContent("Plan", value: plan).fixedSize(horizontal: false, vertical: true) }
            } footer: {
                if !needsReconnect, error != nil {
                    Text(updatesPaused ? "Updates temporarily paused. Your account is still connected."
                         : "Usage couldn’t update. Your account is still connected.")
                }
            }.listRowBackground(OverviewStyle.track)
            if needsReconnect {
                Section {
                    Button("Reconnect", action: reconnect)
                } footer: {
                    if let error { Text(error) }
                }.listRowBackground(OverviewStyle.track)
            }
            Section {
                Button("Disconnect", role: .destructive, action: disconnect)
                    .foregroundStyle(OverviewStyle.critical)
            }.listRowBackground(OverviewStyle.track)
        }
        .disabled(busy)
        .scrollContentBackground(.hidden)
        .background { BrandSurfaceBackground().ignoresSafeArea() }
        .toolbarBackground(.hidden, for: .navigationBar)
        .tint(OverviewStyle.accent)
    }
}

struct ServiceAccountSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    var showsClose = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack {
            content()
                .toolbar {
                    if showsClose {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close", systemImage: "xmark") { dismiss() }
                            .labelStyle(.iconOnly)
                            .tint(OverviewStyle.primary)
                            .accessibilityLabel("Close")
                    }
                    }
                }
        }
        .tint(OverviewStyle.accent)
        .presentationBackground(OverviewStyle.base)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

struct ServiceDetailContent<Account: View>: View {
    let name: String
    let icon: String
    let reading: QuotaReading?
    let connected: Bool
    let busy: Bool
    let error: String?
    let failure: SharedQuotaStore.Failure?
    var history: CodexUsageHistory? = nil
    let refresh: () -> Void
    @ViewBuilder var account: () -> Account
    @State private var showAccount = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Group {
                if name == "Codex" {
                    CodexDetailInformation(reading: reading, history: history)
                } else {
                    ClaudeDetailInformation(reading: reading)
                }
                }.modifier(UsageLoadingState(loading: busy))
                Divider()
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(OverviewStyle.warning)
                }
                Button { showAccount = true } label: {
                    Label(connected ? "Account and connection" : "Connect \(name)", systemImage: "person.crop.circle")
                }
            }.padding(.horizontal, 16).padding(.vertical, 24)
        }
        .background { BrandSurfaceBackground().ignoresSafeArea() }
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle(name)
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh", systemImage: "arrow.clockwise", action: refresh)
                    .disabled(busy || !connected)
                    .tint(OverviewStyle.primary)
            }
            if #available(iOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .tint(OverviewStyle.primary)
                    .accessibilityLabel("Close")
            }
        }
        .sheet(isPresented: $showAccount) {
            ServiceAccountSheet { account() }
        }
    }
}

private struct UsageLoadingState: ViewModifier {
    let loading: Bool
    func body(content: Content) -> some View {
        if loading {
            content.redacted(reason: .placeholder)
                .disabled(true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Updating usage")
        } else {
            content
        }
    }
}

private struct ChartLoadingState: ViewModifier {
    let loading: Bool
    var history = false
    func body(content: Content) -> some View {
        content.opacity(loading ? 0 : 1)
            .overlay {
                if loading {
                    if history {
                        VStack(spacing: 8) {
                            HStack(alignment: .bottom, spacing: 4) {
                                ForEach(0..<30, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 2).fill(OverviewStyle.track)
                                        .frame(height: 20)
                                }
                            }.frame(maxHeight: .infinity, alignment: .bottom)
                            HStack {
                                RoundedRectangle(cornerRadius: 3).fill(OverviewStyle.track).frame(width: 38, height: 10)
                                Spacer()
                                RoundedRectangle(cornerRadius: 3).fill(OverviewStyle.track).frame(width: 30, height: 10)
                            }
                        }.accessibilityHidden(true)
                    } else {
                        RoundedRectangle(cornerRadius: 4).fill(OverviewStyle.track)
                            .accessibilityHidden(true)
                    }
                }
            }
            .accessibilityHidden(loading)
    }
}

private struct ClaudeDetailInformation: View {
    let reading: QuotaReading?
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize = 44.0

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let spent = reading?.metadata?.usageSpent, spent > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Credits used").font(.headline)
                    Text(reading?.metadata?.usageCurrency.map { spent.formatted(.currency(code: $0)) }
                         ?? spent.formatted(.number.precision(.fractionLength(0...2))) + " credits")
                        .font(.system(size: amountSize, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text("Beyond your subscription · \(reading?.fetchedAt.formatted(.dateTime.month(.wide)) ?? Date.now.formatted(.dateTime.month(.wide)))")
                        .font(.footnote).foregroundStyle(OverviewStyle.secondary)
                    Text("Fable 5 and post-limit usage. Claude reports both as one monthly total and doesn’t provide a reliable breakdown. Your subscription price is separate.")
                        .font(.footnote).foregroundStyle(OverviewStyle.secondary).padding(.top, 4)
                }
                Divider()
            } else if reading?.metadata?.usageSpent == nil {
                Text("Spending not reported").font(.footnote).foregroundStyle(OverviewStyle.secondary)
            }
            VStack(alignment: .leading, spacing: 16) {
                Text("Resets").font(.headline)
                reset("5-hour", window: reading?.shortTerm)
                reset("7-day", window: reading?.weekly)
            }
            if let reading {
                Text("Updated \(reading.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote).foregroundStyle(OverviewStyle.secondary)
            }
        }
        .foregroundStyle(OverviewStyle.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reset(_ title: String, window: QuotaWindow?) -> some View {
        LabeledContent(title) {
            Text(window?.resetsAt?.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                 ?? "Not reported")
                .foregroundStyle(OverviewStyle.secondary).multilineTextAlignment(.trailing)
        }.font(.subheadline)
    }
}

private struct CodexDetailInformation: View {
    let reading: QuotaReading?
    let history: CodexUsageHistory?
    @Environment(\.redactionReasons) private var redactionReasons
    @State private var period = 30
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize = 44.0

    @ScaledMetric(relativeTo: .subheadline) private var legendCapMidpoint = 5.5

    private var days: [CodexUsageHistory.Day] { Array((history?.days ?? []).suffix(period)) }
    private func totals(_ key: KeyPath<CodexUsageHistory.Day, [String: Double]?>) -> [(String, Double)] {
        var result: [String: Double] = [:]
        for day in days {
            for (name, value) in day[keyPath: key] ?? [:] { result[name, default: 0] += value }
        }
        return result.filter { $0.value > 0 }.sorted {
            $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
        }.map { ($0.key, $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let spent = reading?.metadata?.usageSpent, spent > 0 {
            VStack(alignment: .leading, spacing: 8) {
                Text("Credits used").font(.headline)
                Text(spending).font(.system(size: amountSize, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text("Beyond your subscription · \(reading?.fetchedAt.formatted(.dateTime.month(.wide)) ?? Date.now.formatted(.dateTime.month(.wide)))")
                    .font(.footnote).foregroundStyle(OverviewStyle.secondary)
                Text("Credit usage reported for this month, converted at 25 credits = $1. This excludes your subscription price and is not a record of credit purchases.")
                    .font(.footnote).foregroundStyle(OverviewStyle.secondary).padding(.top, 4)
            }
            Divider()
            } else if reading?.metadata?.usageSpent == nil {
                Text("Spending not reported").font(.footnote).foregroundStyle(OverviewStyle.secondary)
            }
            VStack(alignment: .leading, spacing: 16) {
                let headingLayout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                    : AnyLayout(HStackLayout())
                headingLayout {
                    Text("Usage").font(.headline)
                    if !typeSize.isAccessibilitySize { Spacer() }
                    Picker("Period", selection: $period) {
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                    }.pickerStyle(.menu)
                }
                Text("Share of usage credits, including your plan. Not a breakdown of extra charges.")
                    .font(.footnote).foregroundStyle(OverviewStyle.secondary)
                VStack(alignment: .leading, spacing: 16) {
                    Text("Models").font(.headline)
                    breakdown(totals(\.models))
                }.padding(.top, 12)
                VStack(alignment: .leading, spacing: 16) {
                    Text("Apps and tools").font(.headline)
                    breakdown(totals(\.surfaces))
                }.padding(.top, 16)
                if days.contains(where: { $0.credits != nil && $0.models == nil }) {
                    Text("Model breakdown is missing for some reported days.")
                        .font(.footnote).foregroundStyle(OverviewStyle.secondary)
                }
                if let history {
                    Text("Updated \(history.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote).foregroundStyle(OverviewStyle.secondary)
                        .padding(.top, 8)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                Text("Resets").font(.headline)
                reset("5-hour", window: reading?.shortTerm)
                reset("7-day", window: reading?.weekly)
            }
        }
        .foregroundStyle(OverviewStyle.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var spending: String {
        guard let amount = reading?.metadata?.usageSpent else { return "Not reported" }
        return amount.formatted(.currency(code: reading?.metadata?.usageCurrency ?? "USD"))
    }

    private func displayName(_ name: String) -> String {
        let names = ["cli": "CLI", "vscode": "VS Code", "desktop_app": "Desktop",
                     "web": "Web", "mobile": "Mobile", "sdk": "SDK",
                     "github_code_review": "GitHub review", "codex-auto-review": "Auto review"]
        return names[name] ?? name.replacingOccurrences(of: "gpt-", with: "GPT-")
            .replacingOccurrences(of: "_", with: " ")
    }
    private func shareLabel(_ share: Double) -> String {
        share > 0 && share < 0.01 ? "<1%" : share.formatted(.percent.precision(.fractionLength(0)))
    }
    @ViewBuilder private func breakdown(_ values: [(String, Double)]) -> some View {
        let total = values.reduce(0) { $0 + $1.1 }
        if total > 0 {
            let leading = Array(values.filter { $0.1 / total >= 0.01 }.prefix(3))
            let remaining = values.filter { item in !leading.contains(where: { $0.0 == item.0 }) }
            let rows = leading + (remaining.isEmpty ? [] : [("Other", remaining.reduce(0) { $0 + $1.1 })])
            let colors: [Color] = [OverviewStyle.accent, Color(red: 0.48, green: 0.27, blue: 0.70),
                                   Color(red: 0.79, green: 0.66, blue: 0.91), Color(red: 0.43, green: 0.38, blue: 0.51)]
            VStack(alignment: .leading, spacing: 12) {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            Rectangle().fill(colors[index])
                                .frame(width: geometry.size.width * row.1 / total)
                                .overlay(alignment: .leading) {
                                    if index > 0 { Rectangle().fill(OverviewStyle.base).frame(width: 1) }
                                }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }.frame(height: 20)
                    .modifier(ChartLoadingState(loading: redactionReasons.contains(.placeholder)))
                    .accessibilityHidden(true)
                LazyVGrid(columns: typeSize.isAccessibilitySize
                          ? [GridItem(.flexible(), alignment: .leading)]
                          : [GridItem(.flexible(), spacing: 16, alignment: .leading),
                             GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 12) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Circle().fill(colors[index]).frame(width: 8, height: 8)
                                .alignmentGuide(.firstTextBaseline) { dimensions in
                                    dimensions[VerticalAlignment.center] + legendCapMidpoint
                                }
                            (Text(displayName(row.0)) + Text(" " + shareLabel(row.1 / total))
                                .foregroundColor(OverviewStyle.secondary))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.subheadline)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(displayName(row.0))
                        .accessibilityValue(shareLabel(row.1 / total))
                    }
                }
                if !remaining.isEmpty {
                    Text("Other: " + remaining.map { displayName($0.0) }.joined(separator: ", "))
                        .font(.footnote).foregroundStyle(OverviewStyle.secondary)
                }
            }
        } else {
            Text("No breakdown reported for this period.")
                .font(.subheadline).foregroundStyle(OverviewStyle.secondary)
        }
    }

    private func reset(_ title: String, window: QuotaWindow?) -> some View {
        LabeledContent(title) {
            Text(window?.resetsAt?.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                 ?? "Not reported")
                .foregroundStyle(OverviewStyle.secondary).multilineTextAlignment(.trailing)
        }.font(.subheadline)
    }
}

struct BrandSurfaceBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack(alignment: .top) {
            OverviewStyle.base
            if !reduceTransparency {
                RadialGradient(
                    colors: [OverviewStyle.accent.opacity(scheme == .dark ? 0.14 : 0.08), .clear],
                    center: UnitPoint(x: 0.5, y: 0.38), startRadius: 0, endRadius: 210
                )
                .frame(height: 320)
            }
        }
        .accessibilityHidden(true)
    }
}

struct ProviderDialCard: View {
    let name: String
    let icon: String
    let availableWidth: CGFloat
    let reading: QuotaReading?
    let connected: Bool
    let busy: Bool
    let error: String?
    var failure: SharedQuotaStore.Failure? = nil
    var history: CodexUsageHistory? = nil
    var historyUnavailable = false
    let onOpen: () -> Void
    var body: some View {
        ProviderDialCardContent(name: name, icon: icon, availableWidth: availableWidth,
            reading: reading, connected: connected, busy: busy, error: error, failure: failure,
            onOpen: onOpen, history: history, historyUnavailable: historyUnavailable)
    }
}

/// Native materials and system typography deliberately replace the Figma blur/border layers.
/// Shared by the overview and service sheets; settings retain their existing UI.
enum OverviewStyle {
    static let accent = Color("OverviewAccent")
    static let warning = Color("OverviewWarning")
    static let critical = Color("OverviewCritical")
    static let primary = Color("OverviewPrimary")
    static let secondary = Color("OverviewSecondary")
    static let tertiary = Color("OverviewTertiary")
    static let track = Color(uiColor: .quaternarySystemFill)
    static let base = Color("OverviewBase")
    static let radius: CGFloat = 28
    static let ringWidth: CGFloat = 8
}

struct OverviewBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                OverviewStyle.base
                if !reduceTransparency {
                    LinearGradient(stops: [
                        .init(color: Color(red: 102/255, green: 31/255, blue: 143/255).opacity(scheme == .dark ? 0.72 : 0.18), location: 0),
                        .init(color: OverviewStyle.accent.opacity(scheme == .dark ? 0.12 : 0.05), location: 0.4),
                        .init(color: .clear, location: 0.7)
                    ], startPoint: .top, endPoint: .bottom)
                    RadialGradient(colors: [OverviewStyle.accent.opacity(scheme == .dark ? 0.35 : 0.12), .clear],
                                   center: .topTrailing, startRadius: 0, endRadius: geometry.size.width * 0.85)
                }
            }
        }.accessibilityHidden(true)
    }
}

private struct OverviewCardMaterial: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // Regular glass lets the OS apply the user's Liquid Glass appearance and accessibility settings.
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: OverviewStyle.radius))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: OverviewStyle.radius))
        }
    }
}

/// Figma's compact SF line boxes, scaled with Dynamic Type. Accessibility sizes
/// retain native leading so wrapped labels have room to breathe.
private struct OverviewDetailType: ViewModifier {
    var title = false
    var weight: Font.Weight = .semibold
    @ScaledMetric(relativeTo: .title3) private var titleSize = 20.0
    @ScaledMetric(relativeTo: .footnote) private var bodySize = 13.0
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        let size = title ? titleSize : bodySize
        let scale = size / (title ? 20 : 13)
        let lineHeight = (title ? 22.0 : 15.0) * scale
        let nativeHeight = UIFont.systemFont(ofSize: size, weight: weight == .regular ? .regular : .semibold).lineHeight
        content
            .font(.system(size: size, weight: weight))
            .tracking((title ? -0.25 : -0.1) * scale)
            .padding(.vertical, typeSize.isAccessibilitySize ? 0 : (lineHeight - nativeHeight) / 2)
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
    var onOpen: (() -> Void)? = nil
    var history: CodexUsageHistory? = nil
    var historyUnavailable = false
    var largeDial = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var dialSize = 124.0
    private var worst: Double { max(reading?.shortTerm?.usedPercent ?? 0, reading?.weekly?.usedPercent ?? 0) }
    private var tint: Color {
        if !connected || failure != nil || error != nil { return OverviewStyle.secondary }
        if worst >= 95 { return OverviewStyle.critical }
        if worst >= 85 { return OverviewStyle.warning }
        return OverviewStyle.accent
    }
    private var secondaryOpacity: Double { contrast == .increased ? 0.9 : 0.7 }
    private var usesColumns: Bool { !typeSize.isAccessibilitySize && availableWidth >= min(dialSize, 200) + 180 }

    var body: some View {
        if let onOpen {
            Button(action: onOpen) { cardContent }
                .buttonStyle(.plain)
                .accessibilityHint("Opens \(name) service sheet")
        } else {
            cardContent
        }
    }
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            summary
            if name == "Codex", connected {
                Divider()
                if let history {
                    OverviewHistoryStrip(history: history, unavailable: historyUnavailable)
                        .modifier(ChartLoadingState(loading: busy, history: true))
                } else {
                    Text(busy && !historyUnavailable ? "Loading daily history…" : "Daily history unavailable")
                        .font(.caption).foregroundStyle(OverviewStyle.secondary)
                        .frame(maxWidth: .infinity, minHeight: 64)
                }
            }
        }
        .modifier(UsageLoadingState(loading: busy))
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: OverviewStyle.radius))
        .modifier(OverviewCardMaterial())

    }
    private var summary: some View {
        Group {
            if usesColumns {
                HStack(alignment: .top, spacing: 24) { dial; details }
            } else {
                VStack(alignment: .leading, spacing: 16) { dial; details }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            accountSummary
            if connected, let spent = reading?.metadata?.usageSpent { spending(spent) }
        }.padding(.top, 4).frame(maxWidth: .infinity, alignment: .leading)
    }
    private var accountSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: name == "Codex" ? 2 : 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(name).unredacted().modifier(OverviewDetailType(title: true)).foregroundStyle(OverviewStyle.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title3).foregroundStyle(OverviewStyle.tertiary).accessibilityHidden(true)
            }
            Text(connected ? (reading?.metadata?.displayPlan.map { "\($0) plan" } ?? "Plan not reported") : "Not connected")
                .modifier(OverviewDetailType(weight: .regular)).foregroundStyle(OverviewStyle.secondary)
            }
            if connected {
                VStack(alignment: .leading, spacing: 4) {
                    resetCaption(reading?.shortTerm, label: "5h")
                    resetCaption(reading?.weekly, label: "7d").opacity(secondaryOpacity)
                }
                if failure != nil || error != nil || reading == nil || worst >= 100 {
                    Text(statusText).font(.footnote).foregroundStyle(OverviewStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Label("Connect", systemImage: "plus.circle")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(OverviewStyle.accent)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var statusText: String {
        if failure == .reconnect || failure == .renewal { return "Reconnect to update" }
        if failure != nil || error != nil { return "Couldn’t update · Saved reading" }
        if reading == nil { return busy ? "Loading allowance…" : "No reading yet" }
        return "Limit reached"
    }
    private func spending(_ amount: Double) -> some View {
        let value = reading?.metadata?.usageCurrency.map { amount.formatted(.currency(code: $0)) }
            ?? amount.formatted(.number.precision(.fractionLength(0...2))) + " credits"
        return Text("Credits used  \(value)")
            .modifier(OverviewDetailType()).foregroundStyle(OverviewStyle.warning)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Credits used: \(value)")
    }

    var dial: some View {
        ZStack {
            arc(reading?.shortTerm, opacity: 1)
            arc(reading?.weekly, opacity: secondaryOpacity).padding(largeDial ? 20 : 10)
            VStack(spacing: largeDial ? 16 : 6) {
                Image(icon).resizable().scaledToFit().frame(width: largeDial ? 36 : 18, height: largeDial ? 36 : 18)
                VStack(spacing: 2) {
                    dialValue(reading?.shortTerm, label: "5h")
                    dialValue(reading?.weekly, label: "7d").opacity(secondaryOpacity)
                }
            }.foregroundStyle(tint)
        }
        .padding(largeDial ? 8 : OverviewStyle.ringWidth / 2)
        .frame(width: largeDial ? 248 : min(dialSize, 200), height: largeDial ? 248 : min(dialSize, 200))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) allowance used")
        .accessibilityValue("5 hours: \(accessibleValue(reading?.shortTerm)). 7 days: \(accessibleValue(reading?.weekly)).")
    }
    private func dialValue(_ window: QuotaWindow?, label: String) -> some View {
        Text(window.map { "\(Int($0.usedPercent.rounded()))% \(label)" } ?? "— \(label)")
            .font(largeDial ? .system(size: 32, weight: .medium).monospacedDigit() : .system(.subheadline, design: .default, weight: .medium).monospacedDigit())
            .foregroundStyle(window == nil ? OverviewStyle.secondary : tint)
    }
    private func accessibleValue(_ window: QuotaWindow?) -> String {
        window.map { "\(Int($0.usedPercent.rounded())) percent" } ?? "not reported"
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
        return Text(text).modifier(OverviewDetailType())
            .foregroundStyle(window == nil ? OverviewStyle.secondary : tint)
            .fixedSize(horizontal: false, vertical: true)
    }
    private func arc(_ window: QuotaWindow?, opacity: Double) -> some View {
        let width = largeDial ? 16.0 : OverviewStyle.ringWidth
        let tickScale = largeDial ? 2.0 : min(dialSize, 200) / 124
        return ZStack {
            Circle().trim(from: 0, to: 0.75)
                .stroke(OverviewStyle.track, style: StrokeStyle(
                    lineWidth: width, lineCap: .butt,
                    dash: window == nil && !busy ? [4 * tickScale, 5 * tickScale] : []))
            if connected, !busy, let window {
                Circle().trim(from: 0, to: 0.75 * min(100, max(0, window.usedPercent)) / 100)
                    .stroke(tint.opacity(opacity), style: StrokeStyle(lineWidth: largeDial ? 16 : OverviewStyle.ringWidth, lineCap: .butt))
            }
        }.rotationEffect(.degrees(135))
    }
}

struct OverviewHistoryStrip: View {
    let history: CodexUsageHistory
    var unavailable = false
    private var maximum: Double { max(1, history.days.compactMap(\.credits).max() ?? 0) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if history.days.contains(where: { $0.credits != nil }) {
                Chart(history.days) { day in
                    if let credits = day.credits {
                        BarMark(x: .value("Date", day.date), y: .value("Usage credits", credits))
                            .foregroundStyle(OverviewStyle.accent)
                            .cornerRadius(2)
                            .accessibilityLabel(day.date)
                            .accessibilityValue("\(credits.formatted(.number.precision(.fractionLength(0...2)))) usage credits")
                    }
                }
                .chartXScale(domain: history.days.map(\.date))
                .chartYScale(domain: 0...maximum)
                .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
                .frame(height: 44)
            } else {
                Text("No daily history reported").font(.caption).foregroundStyle(OverviewStyle.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            HStack {
                Text(history.startLabel)
                Spacer()
                Text(history.endLabel)
            }.font(.caption2).foregroundStyle(OverviewStyle.secondary)
            if unavailable || Date.now.timeIntervalSince(history.fetchedAt) > 1800 {
                Text("Saved history · \(history.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2).foregroundStyle(OverviewStyle.secondary)
            }
        }.accessibilityElement(children: .contain)
            .accessibilityLabel("Daily Codex usage credits. Gaps are unreported days.")
    }
}

private func overviewFreshnessLabel(_ fetchedAt: Date, at now: Date, saved: Bool) -> String {
    let elapsed = max(0, Int(now.timeIntervalSince(fetchedAt)))
    let relative = elapsed < 60 ? "just now" : elapsed < 3600 ? "\(elapsed / 60) minute\(elapsed / 60 == 1 ? "" : "s") ago" : "\(elapsed / 3600) hour\(elapsed / 3600 == 1 ? "" : "s") ago"
    if saved { return "Last updated \(relative)" }
    if elapsed >= 1800 { return "Older reading · \(relative)" }
    return "Updated \(relative)"
}

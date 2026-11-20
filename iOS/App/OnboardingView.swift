import SwiftUI
import Observation

/// Only presentation progress is persisted here. Accounts remain owned by their existing models.
@MainActor @Observable
final class OnboardingProgress {
    enum Step: Int, CaseIterable { case welcome = 0, services = 1, widgets = 2, notifications = 3, complete = 4 }
    static let order: [Step] = [.welcome, .services, .notifications, .widgets, .complete]
    private let isDemo: Bool
    private let defaults: UserDefaults
    private let prefix = "onboarding.v1."
    private(set) var step: Step
    private(set) var completed: Bool

    init(defaults: UserDefaults = .standard, isDemo: Bool = false) {
        self.isDemo = isDemo
        self.defaults = defaults
        step = isDemo ? .welcome : (Step(rawValue: defaults.integer(forKey: "onboarding.v1.step")) ?? .welcome)
        completed = !isDemo && defaults.bool(forKey: "onboarding.v1.completed")
    }
    func shouldPresent(hasExistingAccount: Bool, hasExistingInstallation: Bool = false) -> Bool {
        guard !isDemo, !completed, !defaults.bool(forKey: prefix + "dismissed") else { return false }
        // Preserve pre-onboarding upgrades using local app history. Keychain credentials
        // alone can survive deletion, so a reinstall still gets the welcome flow.
        if !defaults.bool(forKey: prefix + "started"), hasExistingAccount, hasExistingInstallation {
            dismiss()
            return false
        }
        defaults.set(true, forKey: prefix + "started")
        return true
    }
    func begin() {
        if completed { setStep(.welcome) }
        guard !isDemo else { return }
        defaults.set(true, forKey: prefix + "started")
        defaults.set(false, forKey: prefix + "dismissed")
    }
    func resumeRequiredSetup(hasConnectedService: Bool) {
        begin()
        // No-account launches use this flow even after a prior dismissal or completion.
        if !hasConnectedService, step != .welcome { setStep(.services) }
    }
    func canAdvance(hasConnectedService: Bool) -> Bool {
        step != .services || hasConnectedService
    }
    func replay() {
        setStep(.welcome)
        begin()
    }
    func reset() {
        if isDemo { step = .welcome; completed = false; return }
        for key in ["step", "completed", "dismissed", "started"] {
            defaults.removeObject(forKey: prefix + key)
        }
        step = .welcome
        completed = false
    }
    func setStep(_ next: Step) {
        step = next
        if !isDemo { defaults.set(next.rawValue, forKey: prefix + "step") }
    }
    func dismiss() { if !isDemo { defaults.set(true, forKey: prefix + "dismissed") } }
    func finish() {
        completed = true
        if !isDemo { defaults.set(true, forKey: prefix + "completed") }
        dismiss()
    }
}

struct OnboardingView: View {
    @Environment(\.setDemoEnabled) private var setDemoEnabled
    let codex: ProbeModel
    let claude: ClaudeProbeModel
    let progress: OnboardingProgress
    var accounts: MobileAccountCollection? = nil
    @State private var accountDestination: AccountDestination?
    @State private var selectedAccount: AccountProfile?
    @State private var addedAccount: AccountProfile?
    @State private var namingAccount: AccountProfile?
    @State private var nameDraft = ""
    private enum AccountDestination: String, Identifiable {
        case codex, claude
        var id: String { rawValue }
    }
    var allowsDeferral = true
    var onFinish: (() -> Void)? = nil
    @AppStorage("refreshIntervalMinutes") private var refreshMinutes = 0
    @Environment(\.dismiss) private var dismiss
    @State private var demoRefreshMinutes = 0
    private var refreshSelection: Binding<Int> { codex.isDemo ? $demoRefreshMinutes : $refreshMinutes }

    var body: some View {
        NavigationStack {
            Group {
                if progress.step == .notifications {
                    if codex.isDemo { DemoNotificationsView() } else { MobileNotificationsView() }
                } else if progress.step == .widgets {
                    // Sized to the screen: the steps must never sit under the Back/Continue bar.
                    LockScreenSetupContent(fitsToScreen: true)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            switch progress.step {
                            case .welcome:
                                OnboardingWelcome()
                            case .services:
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Connect your services").font(.title.bold())
                                    Text("Sign in to the services you use.").foregroundStyle(OverviewStyle.secondary)
                                }
                                service("Codex", subtitle: accountSubtitle(.codex, fallback: "ChatGPT / OpenAI"), logo: "logo-openai", connected: accounts?.connected(.codex).isEmpty == false || codex.connected, error: codex.error) {
                                    openAccount(.codex)
                                }
                                service("Claude Code", subtitle: accountSubtitle(.claude, fallback: "Anthropic / claude.ai"), logo: "logo-claude", connected: accounts?.connected(.claude).isEmpty == false || claude.connected, error: claude.error ?? (claude.connectionFailure != nil ? String(localized: "Needs attention") : nil)) {
                                    openAccount(.claude)
                                }
                                if accounts?.hasConnection == true || codex.connected || claude.connected {
                                    if let accounts {
                                        Menu("Add another account", systemImage: "plus") {
                                            Button("Codex") { addAccount(.codex, to: accounts) }
                                            Button("Claude") { addAccount(.claude, to: accounts) }
                                        }
                                    }
                                    Divider()
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("How often should AIQuota refresh?").font(.subheadline.weight(.medium))
                                        Picker("Refresh every", selection: refreshSelection) {
                                            Text("Auto").tag(0)
                                            ForEach([1, 5, 10, 30], id: \.self) { Text("\($0) min").tag($0) }
                                        }.pickerStyle(.menu)
                                        Text("Auto checks every 5 minutes while the app is open, or every minute near a limit.")
                                            .font(.footnote).foregroundStyle(OverviewStyle.secondary)
                                    }
                                }
                                Text("You can add accounts or services later in Settings.").font(.footnote).foregroundStyle(OverviewStyle.secondary)
                            case .notifications, .widgets:
                                EmptyView()
                            case .complete:
                                VStack(spacing: 24) {
                                    Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(OverviewStyle.accent)
                                    Text("You’re all set!").font(.title.bold())
                                    VStack(alignment: .leading, spacing: 12) {
                                        MobileAnalyticsConsentControls(surface: .onboarding, isDemo: codex.isDemo)
                                    }
                                        .padding(18)
                                        .background(OverviewStyle.track, in: RoundedRectangle(cornerRadius: OverviewStyle.radius))
                                    VStack(spacing: 6) {
                                        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
                                        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
                                        Text("AIQuota \(version) (\(build))").fontWeight(.medium)
                                        Text("Made by John Niedermeyer, with a little help from Claude, Codex, and friends.")
                                        Text("Need help?").padding(.top, 8)
                                        ViewThatFits(in: .horizontal) {
                                            HStack(spacing: 12) { supportLinks }
                                            VStack(spacing: 8) { supportLinks }
                                        }
                                    }.font(.footnote).foregroundStyle(OverviewStyle.secondary)
                                        .multilineTextAlignment(.center).padding(.top, 24)

                                }.frame(maxWidth: .infinity).padding(.vertical, 16)
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: 600, alignment: .leading)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .onboardingBottomBar {
                // Buttons keep their natural width (no wrapping). Dots stay centred while
                // both sides fit; long labels (German "Demo ausprobieren") drop the dots,
                // then stack.
                ViewThatFits(in: .horizontal) {
                    OnboardingBalancedBar(spacing: 12) { leadingBarButton; pageDots; trailingBarButton }
                    HStack(spacing: 12) { leadingBarButton; Spacer(minLength: 0); trailingBarButton }
                    VStack(spacing: 10) { trailingBarButton; leadingBarButton }
                }
                .padding(20)
            }
            .background { BrandSurfaceBackground().ignoresSafeArea() }
        .toolbarBackground(.hidden, for: .navigationBar)
            .navigationTitle(codex.isDemo ? "Demo setup" : "Set up AIQuota")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if allowsDeferral, progress.step != .complete {
                    if #available(iOS 26.0, *) {
                        ToolbarItem(placement: .cancellationAction) { skipButton }
                            .sharedBackgroundVisibility(.hidden)
                    } else {
                        ToolbarItem(placement: .cancellationAction) { skipButton }
                    }
                }
            }
        }.tint(OverviewStyle.accent)
            .foregroundStyle(OverviewStyle.primary)
            .presentationBackground(OverviewStyle.base)
            .alert("Name your account", isPresented: Binding(
                get: { namingAccount != nil }, set: { if !$0 { namingAccount = nil } }
            )) {
                TextField("Account name", text: $nameDraft)
                Button("Save") {
                    if let namingAccount { accounts?.rename(namingAccount, to: nameDraft) }
                    namingAccount = nil
                }
                .disabled(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Not now", role: .cancel) { namingAccount = nil }
            } message: {
                Text("Your account is connected. Save the suggested name or choose your own. You can change it later in Settings.")
            }
            .sheet(item: $accountDestination, onDismiss: { accounts?.reload() }) { destination in
                ServiceAccountSheet {
                    switch destination {
                    case .codex: ProbeView(model: codex)
                    case .claude: ClaudeProbeView(model: claude)
                    }
                }
            }
            .sheet(item: $selectedAccount, onDismiss: {
                if let addedAccount {
                    if let connected = accounts?.finishAdding(addedAccount) {
                        nameDraft = connected.label
                        namingAccount = connected
                    }
                }
                addedAccount = nil
                accounts?.reload()
            }) { profile in
                ServiceAccountSheet {
                    if profile.service == .codex, let model = accounts?.codex(profile) {
                        ProbeView(model: model)
                    } else if let model = accounts?.claude(profile) {
                        ClaudeProbeView(model: model)
                    }
                }
            }
    }

    private func accountSubtitle(_ service: QuotaService, fallback: String) -> String {
        guard let accounts else { return fallback }
        let count = accounts.connected(service).count
        return count == 0 ? fallback : String(localized: "\(count) accounts connected")
    }

    private func openAccount(_ service: QuotaService) {
        guard let accounts else {
            accountDestination = service == .codex ? .codex : .claude
            return
        }
        if let profile = accounts.connected(service).first ?? accounts.all(service).first {
            addedAccount = profile.suggestedNamePending == true ? profile : nil
            selectedAccount = profile
        } else {
            addAccount(service, to: accounts)
        }
    }

    private func addAccount(_ service: QuotaService, to accounts: MobileAccountCollection) {
        let profile = accounts.add(service)
        addedAccount = profile
        selectedAccount = profile
    }

    private var skipButton: some View {
        Button {
            progress.dismiss()
            dismiss()
        } label: {
            Text("Not now")
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .modifier(OnboardingSecondaryButtonStyle())
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder private var leadingBarButton: some View {
        if progress.step != .welcome {
            Button("Back", systemImage: "chevron.left") {
                let index = OnboardingProgress.order.firstIndex(of: progress.step) ?? 0
                progress.setStep(OnboardingProgress.order[max(0, index - 1)])
            }.modifier(OnboardingSecondaryButtonStyle()).fixedSize()
        } else if !codex.isDemo {
            Button("Try Demo") {
                progress.dismiss()
                dismiss()
                setDemoEnabled(true)
            }.modifier(OnboardingSecondaryButtonStyle()).fixedSize()
        } else {
            Color.clear.frame(width: 0, height: 0)
        }
    }

    @ViewBuilder private var trailingBarButton: some View {
        if progress.step == .complete {
            // In the bar, not the page, so it is never under Back on short screens.
            Button(codex.isDemo ? "Return to demo" : "Start using AIQuota") {
                progress.finish()
                if !codex.isDemo { MobileAnalytics.shared.completeOnboarding() }
                if let onFinish { onFinish() } else { dismiss() }
            }.modifier(OnboardingPrimaryButtonStyle()).fixedSize()
        } else {
            Button("Continue") {
                let index = OnboardingProgress.order.firstIndex(of: progress.step) ?? 0
                progress.setStep(OnboardingProgress.order[index + 1])
            }.modifier(OnboardingPrimaryButtonStyle()).fixedSize()
                .disabled(!progress.canAdvance(hasConnectedService: accounts?.hasConnection == true || codex.connected || claude.connected))
        }
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingProgress.order, id: \.rawValue) { step in
                Circle().fill(step == progress.step ? OverviewStyle.accent : OverviewStyle.track).frame(width: 6, height: 6)
            }
        }
        .fixedSize()
        .accessibilityLabel("Step \((OnboardingProgress.order.firstIndex(of: progress.step) ?? 0) + 1) of 5")
    }

    @ViewBuilder private var supportLinks: some View {
        Link("GitHub Issues", destination: URL(string: "https://github.com/niederme/ai-quota/issues")!)
        Link("@niederme on X", destination: URL(string: "https://x.com/niederme")!)
    }

    private func service(_ name: String, subtitle: String, logo: String,
        connected: Bool, error: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(logo).resizable().scaledToFit().frame(width: 28, height: 28)
                    .foregroundStyle(OverviewStyle.primary).padding(10)
                    .background(OverviewStyle.accent.opacity(0.12), in: Circle())
                    .overlay(Circle().strokeBorder(OverviewStyle.accent.opacity(0.4)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.headline)
                    Text(subtitle)
                        .font(.caption).foregroundStyle(OverviewStyle.secondary)
                }
                Spacer(minLength: 0)
                if connected {
                    Label(codex.isDemo ? "Sample" : "Connected",
                          systemImage: error == nil ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(error == nil ? OverviewStyle.accent : OverviewStyle.warning)
                } else {
                    Text("Sign In").font(.callout.weight(.semibold)).lineLimit(1).fixedSize()
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .foregroundStyle(.white).background(OverviewStyle.accent, in: Capsule())
                }
            }
            .padding(16)
            .background(OverviewStyle.track,
                        in: RoundedRectangle(cornerRadius: OverviewStyle.radius))
        }.buttonStyle(.plain)
    }
}

struct OnboardingWelcome: View {
    var body: some View {
        VStack(spacing: 20) {
            Image("onboarding-icon").resizable().scaledToFit().frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 20)).accessibilityHidden(true)
            Text("AIQuota").font(.largeTitle.bold())
            Text("Know your limits.\nKeep your flow.")
                .font(.title3).foregroundStyle(OverviewStyle.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 64)
    }
}

struct LockScreenSetupContent: View {
    @State var lockScreen = false
    /// Onboarding passes true: the page fills the space above the bottom bar and,
    /// before it would scroll, shrinks the illustration so all three steps stay visible.
    var fitsToScreen = false

    var body: some View {
        if fitsToScreen {
            ViewThatFits(in: .vertical) {
                page(compact: false)
                page(compact: true)
                ScrollView { page(compact: true) }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            layout(compact: false)
        }
    }

    private func page(compact: Bool) -> some View {
        layout(compact: compact).padding(24).frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity)
    }

    private func layout(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 16 : 24) {
            Picker("Widget location", selection: $lockScreen) {
                Text("Home Screen").tag(false)
                Text("Lock Screen").tag(true)
            }.pickerStyle(.segmented)
            illustration
                .scaleEffect(compact ? Self.compactScale : 1)
                .frame(width: 240 * (compact ? Self.compactScale : 1), height: 280 * (compact ? Self.compactScale : 1))
                .frame(maxWidth: .infinity).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: compact ? 14 : 20) {
                if lockScreen {
                    instruction(1, "Touch and hold your Lock Screen.")
                    instruction(2, "Tap Customize, then Lock Screen.")
                    instruction(3, "Tap Add Widgets, choose AIQuota, then tap Done.")
                } else {
                    instruction(1, "Touch and hold your Home Screen.")
                    instruction(2, "Tap Edit, then Add Widget.")
                    instruction(3, "Search for AIQuota, choose a widget, then tap Add Widget.")
                }
            }
        }
    }

    private static let compactScale: CGFloat = 0.7

    private var illustration: some View {
        VStack(spacing: 18) {
            Capsule().fill(OverviewStyle.secondary.opacity(0.3)).frame(width: 54, height: 6)
            if lockScreen {
                Text("9:41").font(.system(size: 52, weight: .medium))
                Label("Add Widgets", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(OverviewStyle.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(OverviewStyle.accent, style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
                    .foregroundStyle(OverviewStyle.accent)
                Image(systemName: "hand.tap.fill").font(.title).foregroundStyle(OverviewStyle.accent)
                Spacer(minLength: 0)
            } else {
                HStack {
                    Text("Edit").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(OverviewStyle.accent.opacity(0.15), in: Capsule())
                        .foregroundStyle(OverviewStyle.accent)
                    Spacer()
                }
                Label("Add Widget", systemImage: "plus")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(OverviewStyle.accent)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    .background(OverviewStyle.track, in: RoundedRectangle(cornerRadius: 12))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
                    ForEach(0..<8, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 10).fill(OverviewStyle.track).frame(height: 34)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(20).frame(width: 240, height: 280)
        .background(OverviewStyle.track.opacity(0.5), in: RoundedRectangle(cornerRadius: 32))
        .overlay(RoundedRectangle(cornerRadius: 32).strokeBorder(OverviewStyle.secondary.opacity(0.25), lineWidth: 1))
    }

    private func instruction(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)").font(.headline).foregroundStyle(OverviewStyle.accent)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct LockScreenSetupView: View {
    var body: some View {
        ScrollView {
            LockScreenSetupContent().padding(24).frame(maxWidth: 600, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .background { BrandSurfaceBackground().ignoresSafeArea() }
        .toolbarBackground(.hidden, for: .navigationBar)
        .foregroundStyle(OverviewStyle.primary)
        .tint(OverviewStyle.accent)
        .navigationTitle("Widgets").navigationBarTitleDisplayMode(.inline)
    }
}

/// Leading button, centred page dots, trailing button. Its ideal width counts both sides
/// at the wider one's width, so ViewThatFits only picks it when the dots can sit in the
/// true centre without anything wrapping.
private struct OnboardingBalancedBar: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let side = sizes.indices.filter { $0 != 1 }.map { sizes[$0].width }.max() ?? 0
        let middle = sizes.count > 1 ? sizes[1].width : 0
        let ideal = side * 2 + middle + spacing * 2
        return CGSize(width: proposal.width ?? ideal, height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let x: CGFloat
            switch index {
            case 0: x = bounds.minX
            case 1: x = bounds.midX - size.width / 2
            default: x = bounds.maxX - size.width
            }
            subview.place(at: CGPoint(x: x, y: bounds.midY - size.height / 2), proposal: ProposedViewSize(size))
        }
    }
}

private extension View {
    /// On iOS 26+ a safe-area bar, so content scrolled beneath Back/Continue gets the
    /// system scroll edge effect instead of showing through the glass buttons.
    @ViewBuilder
    func onboardingBottomBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .bottom, content: bar)
        } else {
            // No system edge effect before iOS 26: fade a material in behind the bar so
            // scrolled text doesn't show through the buttons.
            safeAreaInset(edge: .bottom) {
                bar().background {
                    Rectangle().fill(.ultraThinMaterial)
                        .mask(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.35)))
                        .ignoresSafeArea()
                }
            }
        }
    }
}

// Native controls inherit the brand tint and system Liquid Glass appearance.
struct OnboardingPrimaryButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glassProminent).controlSize(.large)
        } else {
            content.buttonStyle(.borderedProminent).controlSize(.large)
        }
    }
}

struct OnboardingSecondaryButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glass).controlSize(.large)
        } else {
            content.buttonStyle(.bordered).controlSize(.large)
        }
    }
}

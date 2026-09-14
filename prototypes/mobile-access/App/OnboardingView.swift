import SwiftUI
import Observation

/// Only presentation progress is persisted here. Accounts remain owned by their existing models.
@MainActor @Observable
final class OnboardingProgress {
    enum Step: Int, CaseIterable { case welcome = 0, services = 1, widgets = 2, notifications = 3, complete = 4 }
    static let order: [Step] = [.welcome, .services, .notifications, .widgets, .complete]
    private let defaults: UserDefaults
    private let prefix = "onboarding.v1."
    private(set) var step: Step
    private(set) var completed: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        step = Step(rawValue: defaults.integer(forKey: "onboarding.v1.step")) ?? .welcome
        completed = defaults.bool(forKey: "onboarding.v1.completed")
    }
    func shouldPresent(hasExistingAccount: Bool, hasExistingInstallation: Bool = false) -> Bool {
        guard !completed, !defaults.bool(forKey: prefix + "dismissed") else { return false }
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
        defaults.set(true, forKey: prefix + "started")
        defaults.set(false, forKey: prefix + "dismissed")
    }
    func replay() {
        setStep(.welcome)
        begin()
    }
    func reset() {
        for key in ["step", "completed", "dismissed", "started"] {
            defaults.removeObject(forKey: prefix + key)
        }
        step = .welcome
        completed = false
    }
    func setStep(_ next: Step) {
        step = next
        defaults.set(next.rawValue, forKey: prefix + "step")
    }
    func dismiss() { defaults.set(true, forKey: prefix + "dismissed") }
    func finish() {
        completed = true
        defaults.set(true, forKey: prefix + "completed")
        dismiss()
    }
}

struct OnboardingView: View {
    let codex: ProbeModel
    let claude: ClaudeProbeModel
    let progress: OnboardingProgress
    @AppStorage("refreshIntervalMinutes") private var refreshMinutes = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch progress.step {
                    case .welcome:
                        OnboardingWelcome()
                    case .services:
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Connect your services").font(.title.bold())
                            Text("Sign in to the services you use.").foregroundStyle(.secondary)
                        }
                        service("Codex", subtitle: "ChatGPT / OpenAI", logo: "logo-openai", connected: codex.connected, error: codex.error) {
                            ProbeView(model: codex)
                        }
                        service("Claude Code", subtitle: "Anthropic / claude.ai", logo: "logo-claude", connected: claude.connected, error: claude.error ?? (claude.connectionFailure != nil ? "Needs attention" : nil)) {
                            ClaudeProbeView(model: claude)
                        }
                        if codex.connected || claude.connected {
                            Divider()
                            VStack(alignment: .leading, spacing: 10) {
                                Text("How often should AIQuota refresh?").font(.subheadline.weight(.medium))
                                Picker("Refresh every", selection: $refreshMinutes) {
                                    Text("Auto").tag(0)
                                    ForEach([1, 5, 10, 30], id: \.self) { Text("\($0) min").tag($0) }
                                }.pickerStyle(.menu)
                                Text("Auto checks every 5 minutes while the app is open, or every minute near a limit.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        Text("You can connect more services later in Settings.").font(.footnote).foregroundStyle(.secondary)
                    case .notifications:
                        MobileNotificationControls()
                    case .widgets:
                        LockScreenSetupContent()
                    case .complete:
                        VStack(spacing: 24) {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(.green)
                            Text("You’re all set!").font(.title.bold())
                            Button("Start using AIQuota") { progress.finish(); dismiss() }
                                .buttonStyle(.borderedProminent).controlSize(.large)
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
                            }.font(.footnote).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center).padding(.top, 24)

                        }.frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                }
                .padding(24)
                .frame(maxWidth: 600, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    if progress.step != .welcome {
                        Button("Back", systemImage: "chevron.left") {
                            let index = OnboardingProgress.order.firstIndex(of: progress.step) ?? 0
                            progress.setStep(OnboardingProgress.order[max(0, index - 1)])
                        }
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(OnboardingProgress.order, id: \.rawValue) { step in
                            Circle().fill(step == progress.step ? Color(uiColor: .systemPurple) : Color.secondary.opacity(0.3)).frame(width: 6, height: 6)
                        }
                    }.accessibilityLabel("Step \((OnboardingProgress.order.firstIndex(of: progress.step) ?? 0) + 1) of 5")
                    Spacer()
                    if progress.step != .complete {
                    Button("Continue") {
                        let index = OnboardingProgress.order.firstIndex(of: progress.step) ?? 0
                        progress.setStep(OnboardingProgress.order[index + 1])
                    }.buttonStyle(.borderedProminent)
                    }
                }.padding(20).background(.bar)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Set up AIQuota")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { progress.dismiss(); dismiss() }
                }
            }
        }.tint(Color(uiColor: .systemPurple))
    }

    @ViewBuilder private var supportLinks: some View {
        Link("GitHub Issues", destination: URL(string: "https://github.com/niederme/ai-quota/issues")!)
        Link("@niederme on X", destination: URL(string: "https://x.com/niederme")!)
    }

    private func service<Destination: View>(_ name: String, subtitle: String, logo: String,
        connected: Bool, error: String?, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                Image(logo).resizable().scaledToFit().frame(width: 28, height: 28)
                    .foregroundStyle(.primary).padding(10)
                    .background(Color(uiColor: .systemPurple).opacity(0.12), in: Circle())
                    .overlay(Circle().strokeBorder(Color(uiColor: .systemPurple).opacity(0.4)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.headline)
                    Text(subtitle)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if connected && error == nil {
                    Label("Connected", systemImage: "checkmark.circle.fill").font(.caption.weight(.medium)).foregroundStyle(.green)
                } else {
                    Text(error == nil ? "Sign In" : "Reconnect").font(.callout.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .foregroundStyle(.white).background(Color(uiColor: .systemPurple), in: Capsule())
                }
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16))
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
                .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 64)
    }
}

struct LockScreenSetupContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add AIQuota widgets").font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
            Text("See your quota at a glance on your Home Screen and Lock Screen.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Home Screen").font(.headline)
            instruction(1, "Touch and hold your Home Screen, then open the widget gallery.")
            instruction(2, "Search for AI Quota. Choose a small or medium widget for one service, or a medium or large widget for both.")
            instruction(3, "For a single-service widget, edit the placed widget to choose Codex or Claude Code.")
            Divider()
            Text("Lock Screen").font(.headline)
            instruction(1, "Touch and hold your Lock Screen, then tap Customize and choose the Lock Screen.")
            instruction(2, "Tap the widget area and choose AI Quota. Add rings, percentages, or Service details.")
            instruction(3, "For a single-service widget, tap the placed widget to choose Codex or Claude. Finish customizing to save.")
            Text("Connect a service in AI Quota before expecting its usage in a widget. iOS decides when widgets update; opening the app checks for a fresh reading.")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func instruction(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)").font(.headline).foregroundStyle(Color(uiColor: .systemPurple))
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
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Lock Screen widgets").navigationBarTitleDisplayMode(.inline)
    }
}

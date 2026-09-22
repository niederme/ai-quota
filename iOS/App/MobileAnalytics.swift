import SwiftUI
import Observation

@MainActor
protocol MobileAnalyticsTransport {
    func setCollectionEnabled(_ enabled: Bool)
    func send(_ event: String, params: [String: String])
}

@MainActor
private struct FirebaseMobileAnalyticsTransport: MobileAnalyticsTransport {
    func setCollectionEnabled(_ enabled: Bool) {
        AnalyticsClient.shared.setCollectionEnabled(enabled)
    }

    func send(_ event: String, params: [String: String]) {
        Task { await AnalyticsClient.shared.send(event, params: params, enabled: true) }
    }
}

final class MobileAnalyticsAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Restore consent before SwiftUI can produce events.
        _ = MobileAnalytics.shared
        return true
    }
}

/// App-only analytics. The payload is limited to product state, never account or quota data.
@MainActor @Observable
final class MobileAnalytics {
    enum ConsentSurface: String { case settings, onboarding }
    static let enabledKey = "analytics.enabled"
    static let lastActiveDateKey = "analytics.lastActiveDate"
    static let shared = MobileAnalytics(
        defaults: .standard, transport: FirebaseMobileAnalyticsTransport(), isDemo: DemoQuotaData.isEnabled)

    private let defaults: UserDefaults
    private let transport: any MobileAnalyticsTransport
    private let now: () -> Date
    private let appVersion: String
    private(set) var isEnabled: Bool
    private var isDemo: Bool
    private var services: Set<String> = []
    private var hasObservedServices = false
    private var recordedLaunch = false

    init(defaults: UserDefaults, transport: any MobileAnalyticsTransport, isDemo: Bool = false,
         appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
         now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.transport = transport
        self.isDemo = isDemo
        self.appVersion = appVersion
        self.now = now
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        transport.setCollectionEnabled(isEnabled && !isDemo)
    }

    func setEnabled(_ enabled: Bool, surface: ConsentSurface) {
        guard !isDemo, enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        transport.setCollectionEnabled(enabled)
        if enabled {
            track("analytics_enabled", extra: ["consent_surface": surface.rawValue,
                                               "has_connected_service": services.isEmpty ? "false" : "true"])
            recordDailyActiveIfNeeded()
        }
    }

    func setDemoEnabled(_ enabled: Bool) {
        guard isDemo != enabled else { return }
        isDemo = enabled
        // Recreated real models restore saved connections without emitting connection events.
        hasObservedServices = false
        services = []
        transport.setCollectionEnabled(isEnabled && !isDemo)
    }

    func observeServices(codex: Bool, claude: Bool, isDemo: Bool) {
        setDemoEnabled(isDemo)
        guard !isDemo else { return }
        let previous = services
        services = Set([(codex ? "codex" : nil), (claude ? "claude" : nil)].compactMap { $0 })
        defer { hasObservedServices = true }
        guard hasObservedServices else { return }
        for service in services.subtracting(previous).sorted() {
            track("service_connected", extra: ["service": service, "services_after_connect": servicesParam])
        }
        for service in previous.subtracting(services).sorted() {
            track("service_disconnected", extra: ["service": service, "services_after_disconnect": servicesParam])
        }
    }

    func recordLaunchIfNeeded() {
        guard !recordedLaunch else { return }
        recordedLaunch = true
        track("app_launched")
        recordDailyActiveIfNeeded()
    }

    func recordDailyActiveIfNeeded() {
        guard isEnabled, !isDemo else { return }
        let today = String(ISO8601DateFormatter().string(from: now()).prefix(10))
        guard defaults.string(forKey: Self.lastActiveDateKey) != today else { return }
        defaults.set(today, forKey: Self.lastActiveDateKey)
        track("app_active", extra: ["surface": "app"])
    }

    func completeOnboarding() {
        track("onboarding_completed", extra: ["completed_from": "guided_setup",
                                              "has_connected_service": services.isEmpty ? "false" : "true"])
    }

    func manualRefresh() { track("manual_refresh") }

    func reset() {
        isEnabled = false
        transport.setCollectionEnabled(false)
        defaults.removeObject(forKey: Self.enabledKey)
        defaults.removeObject(forKey: Self.lastActiveDateKey)
    }

    private var servicesParam: String {
        services.count > 1 ? "both" : services.first ?? "none"
    }

    private func track(_ event: String, extra: [String: String] = [:]) {
        guard isEnabled, !isDemo else { return }
        let context = [
            "platform": "ios",
            "app_version": appVersion,
            "services": servicesParam,
            "service_count": String(services.count),
            "onboarding_completed": defaults.bool(forKey: "onboarding.v1.completed") ? "true" : "false"
        ]
        transport.send(event, params: context.merging(extra) { _, new in new })
    }
}

struct MobileAnalyticsConsentControls: View {
    let surface: MobileAnalytics.ConsentSurface
    var isDemo = false
    @State private var demoEnabled = false
    private var consent: Binding<Bool> {
        isDemo ? $demoEnabled : Binding(
            get: { MobileAnalytics.shared.isEnabled },
            set: { MobileAnalytics.shared.setEnabled($0, surface: surface) })
    }

    var body: some View {
        Toggle("Share anonymous usage data", isOn: consent)
            .accessibilityIdentifier("analyticsConsent")
        Text("Share app launches, active use, setup completion, and app version. No prompts, tokens, cookies, or personal info.")
            .font(.footnote)
            .foregroundStyle(OverviewStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
        if surface == .onboarding {
            Text("Off by default. Change anytime in Settings.")
                .font(.caption).foregroundStyle(OverviewStyle.secondary)
        }
        if isDemo {
            Text("Demo settings are temporary. No usage data will be sent.")
                .font(.footnote).foregroundStyle(OverviewStyle.secondary)
        }
        Link("Privacy Policy", destination: URL(string: "https://aiquota.app/privacy/")!)
            .foregroundStyle(OverviewStyle.accent)
    }
}

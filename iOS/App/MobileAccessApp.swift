import SwiftUI
import SafariServices
import WebKit
import MobileAccessCore

@main
struct MobileAccessApp: App {
    @UIApplicationDelegateAdaptor(MobileAnalyticsAppDelegate.self) private var analyticsDelegate
    @State private var demoEnabled = DemoQuotaData.isEnabled
    init() {
        // The default WebKit store can outlive an app uninstall. A new install
        // must not silently inherit a former user's Claude web session.
        let marker = "claudeDetails.installPrepared"
        if !UserDefaults.standard.bool(forKey: marker) {
            UserDefaults.standard.set(true, forKey: marker)
            Task { await ClaudeWebDetailsSession.clearSession() }
        }
    }
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-claudeSSOUITest") {
                ClaudeDetailSSOUITestHarness()
            } else if ProcessInfo.processInfo.arguments.contains("-claudeOAuthUITest") {
                NavigationStack { ClaudeProbeView(model: ClaudeProbeModel(restore: false)) }
            } else if ProcessInfo.processInfo.arguments.contains("-claudeDetailUITest") {
                ClaudeDetailUITestHarness()
            } else if ProcessInfo.processInfo.arguments.contains("-serviceDetailLoadingUITest") {
                ServiceDetailLoadingUITestHarness(
                    service: ProcessInfo.processInfo.arguments.contains("-claudeService") ? "Claude" : "Codex"
                )
            } else if ProcessInfo.processInfo.arguments.contains("-claudeEnterpriseLoadingUITest") {
                ClaudeEnterpriseLoadingUITestHarness()
            } else if ProcessInfo.processInfo.arguments.contains("-codexHistoryVisualUITest") {
                CodexHistoryVisualUITestHarness()
            } else if ProcessInfo.processInfo.arguments.contains("-multiAccountUITest") {
                MultiAccountOverviewView(fixtureProfiles: [
                    AccountProfile(id: "fixture-codex-personal", service: .codex, label: "Personal", isLegacy: false),
                    AccountProfile(id: "fixture-codex-work", service: .codex, label: "Work", isLegacy: false),
                    AccountProfile(id: "fixture-claude-work", service: .claude, label: "Work", isLegacy: false)
                ])
            } else if ProcessInfo.processInfo.arguments.contains("-genericAccountLabelsUITest") {
                MultiAccountOverviewView(fixtureProfiles: [
                    AccountProfile(id: "fixture-codex-1", service: .codex, label: "Account 1", isLegacy: false),
                    AccountProfile(id: "fixture-codex-2", service: .codex, label: "Account 2", isLegacy: false),
                    AccountProfile(id: "fixture-claude-1", service: .claude, label: "Service 1", isLegacy: false),
                    AccountProfile(id: "fixture-claude-2", service: .claude, label: "Service 2", isLegacy: false)
                ])
            } else if ProcessInfo.processInfo.arguments.contains("-businessMonthlyOverviewUITest") {
                BusinessMonthlyOverviewFixtureView()
            } else if ProcessInfo.processInfo.arguments.contains("-multiAccountReorderUITest") {
                MultiAccountReorderFixtureView(
                    reset: ProcessInfo.processInfo.arguments.contains("-resetMultiAccountReorderFixture")
                )
            } else {
                Group {
                    if demoEnabled { OverviewView(isDemo: true).id(demoEnabled) }
                    else { MultiAccountOverviewView().id(demoEnabled) }
                }
                    .environment(\.setDemoEnabled) { enabled in
                        MobileAnalytics.shared.setDemoEnabled(enabled)
                        demoEnabled = enabled
                        DemoQuotaData.setEnabled(enabled)
                    }
            }
            #else
            Group {
                if demoEnabled { OverviewView(isDemo: true).id(demoEnabled) }
                else { MultiAccountOverviewView().id(demoEnabled) }
            }
                .environment(\.setDemoEnabled) { enabled in
                    // Update presentation directly; app-group defaults are for persistence and widgets.
                    MobileAnalytics.shared.setDemoEnabled(enabled)
                    demoEnabled = enabled
                    DemoQuotaData.setEnabled(enabled)
                }
            #endif
        }
    }
}

#if DEBUG
private struct BusinessMonthlyOverviewFixtureView: View {
    private let reading = QuotaReading(
        fetchedAt: .now,
        shortTerm: nil,
        weekly: nil,
        metadata: AccountMetadata(plan: "business", balanceUSD: nil, usageSpent: nil, usageCurrency: nil),
        monthlyBudget: MonthlyBudget(used: 7.82, limit: 7_000, unit: "credits", resetsAt: .now.addingTimeInterval(7 * 86400))
    )

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    ProviderDialCard(name: "Codex", icon: "logo-openai",
                                     availableWidth: geometry.size.width - 32,
                                     reading: reading, connected: true, busy: false, error: nil) {}
                        .padding(16)
                }
                .background { OverviewBackground().ignoresSafeArea() }
            }
            .navigationTitle("AIQuota")
        }
    }
}

private struct MultiAccountReorderFixtureView: View {
    private let store: AccountRegistry.Store

    init(reset: Bool) {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("multi-account-reorder-ui-fixture", isDirectory: true)
        if reset { try? FileManager.default.removeItem(at: root) }
        let store = AccountRegistry.Store(root: root, legacyServices: [])
        if store.all().isEmpty {
            let personal = store.add(service: .codex)
            store.rename(service: .codex, id: personal.id, label: "Personal")
            let other = store.add(service: .codex)
            store.rename(service: .codex, id: other.id, label: "Other")
            let enterprise = store.add(service: .claude)
            store.rename(service: .claude, id: enterprise.id, label: "Enterprise")
        }
        self.store = store
    }

    var body: some View {
        MultiAccountOverviewView(fixtureProfiles: store.all(), orderStore: store)
    }
}
#endif

struct CodexSignInContent: View {
    let code: String?
    let busy: Bool
    let error: String?
    let openSecurity: () -> Void
    let signInWithChatGPT: () -> Void
    let useDeviceCode: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Sign in to Codex").font(.title2.bold())
                    Text("Use ChatGPT sign-in for personal accounts or your organization’s SSO.")
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 16) {
                    Button("Sign in with ChatGPT", action: signInWithChatGPT)
                        .modifier(OnboardingPrimaryButtonStyle())
                        .disabled(busy)
                    if let code {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Device-code fallback").font(.headline)
                            Text("Your sign-in code").foregroundStyle(.secondary)
                            Text(code).font(.title.monospaced().weight(.semibold))
                                .textSelection(.enabled)
                        }
                        Button("Copy code and continue", action: useDeviceCode)
                            .buttonStyle(.bordered)
                    } else {
                        Button("Use device code instead", action: useDeviceCode)
                            .buttonStyle(.plain)
                            .foregroundStyle(OverviewStyle.accent)
                        Button(action: openSecurity) {
                            HStack(spacing: 6) {
                                Text("Device-code security setting")
                                Image(systemName: "arrow.up.right").accessibilityHidden(true)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(OverviewStyle.accent)
                    }
                    if let error {
                        Text(error).foregroundStyle(OverviewStyle.critical)
                    }
                }
            }
            .font(.body)
            .frame(maxWidth: 700, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }
}

struct ProbeView: View {
    let model: ProbeModel
    @Environment(\.openURL) private var openURL
    @State private var requestedSignIn = false
    @State private var confirmDisconnect = false
    @State private var signInPresentation: CodexSignInPresentation?
    @State private var signInBrowser: CodexBrowserSession?
    @State private var showWebSignIn = false
    var body: some View {
        Group {
            if model.isDemo {
                DemoAccountView()
            } else if model.connected && model.challenge == nil {
                AccountConnectionForm(plan: model.reading?.metadata?.displayPlan,
                    updated: model.reading?.fetchedAt, busy: model.busy,
                    needsReconnect: model.connectionFailure == .reconnect || model.connectionFailure == .renewal,
                    error: model.error, retry: { model.refresh() }, reconnect: { beginSignIn() },
                    disconnect: { confirmDisconnect = true })
            } else {
                CodexSignInContent(code: model.challenge?.userCode, busy: model.busy, error: model.error,
                    openSecurity: { openURL(URL(string: "https://chatgpt.com/#settings/Security")!) },
                    signInWithChatGPT: { showWebSignIn = true },
                    useDeviceCode: { beginDeviceSignIn() })
            }
        }
            .foregroundStyle(OverviewStyle.primary)
            .background(OverviewStyle.base)
            .navigationTitle("Codex account")
            .modifier(DismissAfterAccountConnection(completionID: model.signInCompletionID))
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Remove this device’s connection?", isPresented: $confirmDisconnect) {
                Button("Disconnect", role: .destructive) { model.disconnect() }
            } message: {
                Text("Removes the local token and saved reading. It does not revoke the connection at OpenAI.")
            }
        .onChange(of: model.challenge?.deviceAuthID) { _, _ in
            signInBrowser = nil
            signInPresentation = nil
            if model.challenge != nil && requestedSignIn { presentSignIn() }
            if model.challenge == nil { requestedSignIn = false }
        }.onDisappear { requestedSignIn = false }
        .sheet(item: $signInPresentation) { presentation in
            CodexSignInSheet(session: presentation.session, code: presentation.code)
        }
        .sheet(isPresented: $showWebSignIn) {
            CodexWebSignInSheet { result in
                showWebSignIn = false
                switch result {
                case .success(let tokens): model.completeWebSignIn(tokens)
                case .failure: model.failWebSignIn()
                }
            }
        }.tint(OverviewStyle.accent)
    }
    private func beginSignIn() {
        showWebSignIn = true
    }

    private func beginDeviceSignIn() {
        requestedSignIn = true
        if model.challenge != nil { presentSignIn() }
        else if !model.busy { model.connect() }
    }

    private func presentSignIn() {
        guard requestedSignIn, let challenge = model.challenge else { return }
        requestedSignIn = false
        UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: challenge.userCode]],
            options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(15 * 60)])
        if signInBrowser == nil {
            signInBrowser = CodexBrowserSession(url: challenge.verificationURL, code: challenge.userCode)
        }
        if let signInBrowser {
            signInPresentation = CodexSignInPresentation(
                id: challenge.deviceAuthID, session: signInBrowser, code: challenge.userCode)
        }
    }

    @ViewBuilder private func windows(_ reading: QuotaReading) -> some View {
        ForEach(reading.windows) { quota in
            window(quota, unavailableLabel: quota.label)
        }
    }
    private func window(_ window: QuotaWindow?, unavailableLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(window?.label ?? unavailableLabel).font(.headline)
            if let window {
                Text("\(window.usedPercent, specifier: "%.0f")% used").font(.title2.bold()).monospacedDigit()
                ProgressView(value: window.usedPercent, total: 100)
                    .accessibilityLabel("\(window.label) usage")
                if let reset = window.resetsAt {
                    Text("Reported reset \(reset.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(OverviewStyle.secondary)
                } else {
                    Text("Reset time unavailable").font(.caption).foregroundStyle(OverviewStyle.secondary)
                }
            } else {
                Text("Not reported").foregroundStyle(OverviewStyle.secondary)
            }
        }.frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
            .padding(16).background(OverviewStyle.track, in: RoundedRectangle(cornerRadius: OverviewStyle.radius))
    }
}

struct CodexWebSignInSheet: View {
    @Environment(\.dismiss) private var dismiss
    let completion: @MainActor (Result<CodexTokens, Error>) -> Void

    var body: some View {
        NavigationStack {
            CodexWebSignInBrowser(completion: completion)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Sign in to ChatGPT")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
    }
}

/// Runs ChatGPT sign-in inside an isolated WebKit store so page-context session
/// data can be converted into the same bearer-token credentials used by Codex.
private struct CodexWebSignInBrowser: UIViewRepresentable {
    let completion: @MainActor (Result<CodexTokens, Error>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.attach(to: webView)
        webView.load(URLRequest(url: URL(string: "https://chatgpt.com/auth/login")!))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.websiteDataStore.httpCookieStore.remove(coordinator)
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
        private let completion: @MainActor (Result<CodexTokens, Error>) -> Void
        private weak var webView: WKWebView?
        private var isFetching = false
        private var isComplete = false

        init(completion: @escaping @MainActor (Result<CodexTokens, Error>) -> Void) {
            self.completion = completion
        }

        func attach(to webView: WKWebView) {
            self.webView = webView
            webView.configuration.websiteDataStore.httpCookieStore.add(self)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            fetchSessionIfPossible()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            finish(.failure(error))
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.targetFrame == nil, let requestURL = navigationAction.request.url {
                webView.load(URLRequest(url: requestURL))
                return .cancel
            }
            return .allow
        }

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url { webView.load(URLRequest(url: url)) }
            return nil
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            fetchSessionIfPossible()
        }

        private func fetchSessionIfPossible() {
            guard !isComplete, !isFetching, let webView,
                  webView.url?.host?.contains("chatgpt.com") == true else { return }
            isFetching = true
            webView.callAsyncJavaScript("""
                try {
                    const response = await fetch('/api/auth/session', {
                        credentials: 'include',
                        headers: { 'Accept': 'application/json' }
                    });
                    if (!response.ok) return null;
                    return await response.json();
                } catch (_) { return null; }
                """, arguments: [:], in: nil, in: .page) { [weak self, weak webView] result in
                    Task { @MainActor in
                        guard let self, !self.isComplete, let webView else { return }
                        self.isFetching = false
                        guard case .success(let value) = result,
                              let session = value as? [String: Any],
                              let accessToken = session["accessToken"] as? String,
                              !accessToken.isEmpty else { return }
                        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
                        do {
                            let tokens = try CodexAPI.webSessionTokens(
                                accessToken: accessToken,
                                sessionToken: Self.sessionToken(in: cookies),
                                expiresAt: Self.parseExpiry(session["expires"] as? String))
                            self.finish(.success(tokens))
                        } catch {
                            self.finish(.failure(error))
                        }
                    }
                }
        }

        private func finish(_ result: Result<CodexTokens, Error>) {
            guard !isComplete else { return }
            isComplete = true
            completion(result)
        }

        private static func sessionToken(in cookies: [HTTPCookie]) -> String? {
            let bases = ["__Secure-next-auth.session-token", "next-auth.session-token",
                         "__Secure-authjs.session-token", "authjs.session-token"]
            for base in bases {
                if let exact = cookies.first(where: { $0.name == base })?.value, !exact.isEmpty {
                    return exact
                }
                let chunks = cookies.filter { $0.name.hasPrefix(base + ".") }
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                if !chunks.isEmpty { return chunks.map(\.value).joined() }
            }
            return nil
        }

        private static func parseExpiry(_ value: String?) -> Date? {
            guard let value else { return nil }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }
            return ISO8601DateFormatter().date(from: value)
        }
    }
}

/// Present sign-in and settings pages in the app.
/// Safari owns the page and credentials; the probe does not inspect its contents.
struct ProbeBrowser: UIViewControllerRepresentable {
    let url: URL
    var retainedController: SFSafariViewController? = nil
    var copySignInCode: (@MainActor @Sendable () -> Bool)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(copySignInCode: copySignInCode) }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = retainedController ?? SFSafariViewController(url: url)
        controller.delegate = context.coordinator
        controller.dismissButtonStyle = .done
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        context.coordinator.copySignInCode = copySignInCode
        uiViewController.delegate = context.coordinator
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency SFSafariViewControllerDelegate {
        var copySignInCode: (@MainActor @Sendable () -> Bool)?
        init(copySignInCode: (@MainActor @Sendable () -> Bool)?) { self.copySignInCode = copySignInCode }

        func safariViewController(_ controller: SFSafariViewController,
                                  activityItemsFor URL: URL, title: String?) -> [UIActivity] {
            guard let copySignInCode else { return [] }
            return [CopyCodexSignInCodeActivity(copy: copySignInCode)]
        }
    }
}

/// Copies locally without adding the device code to the web page's shared items.
@MainActor
final class CopyCodexSignInCodeActivity: UIActivity {
    nonisolated private let copy: @MainActor @Sendable () -> Bool
    init(copy: @escaping @MainActor @Sendable () -> Bool) {
        self.copy = copy
        super.init()
    }
    override class var activityCategory: UIActivity.Category { .action }
    override var activityType: UIActivity.ActivityType? {
        UIActivity.ActivityType("com.niederme.AIQuota.copyCodexSignInCode")
    }
    override var activityTitle: String? { "Copy Codex sign-in code" }
    override var activityImage: UIImage? { UIImage(systemName: "doc.on.doc") }
    override func canPerform(withActivityItems activityItems: [Any]) -> Bool { true }
    override func perform() {
        let action = copy
        let completed = MainActor.assumeIsolated { action() }
        activityDidFinish(completed)
    }
}


/// Use Safari for third-party passkeys and federated sign-in. A custom WKWebView
/// requires a relying-party domain association that AIQuota cannot provide.
@MainActor
final class CodexBrowserSession: ObservableObject {
    let controller: SFSafariViewController
    let initialURL: URL

    // Safari supplies the button chrome and interaction. A text template keeps
    // this action recognizable without relying on an unfamiliar clipboard icon.
    private static func copyCodeToolbarImage(code: String) -> UIImage {
        let size = CGSize(width: 44, height: 44)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byTruncatingTail
            let split = code.index(code.startIndex, offsetBy: min(5, code.count))
            let label = String(code[..<split]) + "\n" + String(code[split...])
            (label as NSString).draw(in: CGRect(x: 0, y: 7, width: 44, height: 30), withAttributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraph
            ])
        }.withRenderingMode(.alwaysTemplate)
    }

    init(url: URL, code: String) {
        initialURL = url
        let configuration = SFSafariViewController.Configuration()
        configuration.barCollapsingEnabled = false
        configuration.activityButton = SFSafariViewController.ActivityButton(
            templateImage: Self.copyCodeToolbarImage(code: code),
            extensionIdentifier: "com.niederme.AIQuota.copySignInCode")
        controller = SFSafariViewController(url: url, configuration: configuration)
    }
}

/// One value carries both presentation and its required content. A separate Boolean
/// can present a sheet before SwiftUI observes the newly created browser session.
struct CodexSignInPresentation: Identifiable {
    let id: String
    let session: CodexBrowserSession
    let code: String
}

struct CodexSignInSheet: View {
    @ObservedObject var session: CodexBrowserSession
    let code: String

    var body: some View {
        ProbeBrowser(url: session.initialURL, retainedController: session.controller,
                     copySignInCode: {
            UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: code]],
                options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(15 * 60)])
            return true
        })
    }
}

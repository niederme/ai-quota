import SwiftUI
import SafariServices
import MobileAccessCore
#if DEBUG
import WebKit
#endif

@main
struct MobileAccessApp: App {
    @UIApplicationDelegateAdaptor(MobileAnalyticsAppDelegate.self) private var analyticsDelegate
    @State private var demoEnabled = DemoQuotaData.isEnabled
    var body: some Scene {
        WindowGroup {
            OverviewView(isDemo: demoEnabled).id(demoEnabled)
                .environment(\.setDemoEnabled) { enabled in
                    // Update presentation directly; app-group defaults are for persistence and widgets.
                    MobileAnalytics.shared.setDemoEnabled(enabled)
                    demoEnabled = enabled
                    DemoQuotaData.setEnabled(enabled)
                }
        }
    }
}

struct CodexSignInContent: View {
    let code: String?
    let busy: Bool
    let error: String?
    let openSecurity: () -> Void
    let continueSignIn: () -> Void
    let openInSafari: () -> Void
    let restartSignIn: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Sign in to Codex").font(.title2.bold())
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Personal accounts need Device Code Authorization enabled in ChatGPT Security Settings. Work accounts also need their workspace admin to allow device-code sign-in.")
                            .foregroundStyle(.secondary)
                        Button(action: openSecurity) {
                            HStack(spacing: 6) {
                                Text("Open personal security settings")
                                Image(systemName: "arrow.up.right").accessibilityHidden(true)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(OverviewStyle.accent)
                    }
                }
                VStack(alignment: .leading, spacing: 16) {
                    if let code {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your sign-in code").foregroundStyle(.secondary)
                            Text(code).font(.title.monospaced().weight(.semibold))
                                .textSelection(.enabled)
                        }
                    }
                    Button("Copy code and continue", action: continueSignIn)
                        .modifier(OnboardingPrimaryButtonStyle())
                        .disabled(busy && code == nil)
                    if code != nil {
                        Button("Open in browser", systemImage: "safari", action: openInSafari)
                            .frame(minHeight: 44)
                        Button("Start a new sign-in", systemImage: "arrow.clockwise", action: restartSignIn)
                            .frame(minHeight: 44)
                        Text("If your work sign-in loses its session, start a new sign-in and try your browser with the new code.")
                            .font(.footnote).foregroundStyle(.secondary)
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
    @State private var preparedSignIn = false
    @State private var requestedSignIn = false
    @State private var confirmDisconnect = false
    @State private var signInPresentation: CodexSignInPresentation?
    @State private var signInBrowser: CodexBrowserSession?
#if DEBUG
    @State private var showBrowserResearch = false
#endif
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
                    continueSignIn: { beginSignIn() },
                    openInSafari: { openSignInInSafari() }, restartSignIn: { restartSignIn() })
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
        .task {
            guard !preparedSignIn, !model.connected else { return }
            preparedSignIn = true
            // Prepare the displayed code, but leave browser presentation to the button.
            if model.challenge == nil && !model.busy { model.connect() }
        }
        .onChange(of: model.challenge?.deviceAuthID) { _, _ in
            signInBrowser = nil
            signInPresentation = nil
            if model.challenge != nil && requestedSignIn { presentSignIn() }
            if model.challenge == nil { requestedSignIn = false }
        }.onDisappear { requestedSignIn = false }
        .sheet(item: $signInPresentation) { presentation in
            CodexSignInSheet(session: presentation.session, code: presentation.code)
        }.tint(OverviewStyle.accent)
#if DEBUG
        .sheet(isPresented: $showBrowserResearch) {
            BrowserSignInResearchView()
        }
        .safeAreaInset(edge: .bottom) {
            if !model.isDemo {
                Button("Research: test browser sign-in") {
                    if model.challenge != nil { model.cancel() }
                    showBrowserResearch = true
                }
                .font(.footnote)
                .frame(minHeight: 44)
                .frame(maxWidth: .infinity)
                .background(OverviewStyle.base)
            }
        }
#endif
    }
    private func beginSignIn() {
        requestedSignIn = true
        if model.challenge != nil { presentSignIn() }
        else if !model.busy { model.connect() }
    }

    private func openSignInInSafari() {
        guard let challenge = model.challenge else { return }
        UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: challenge.userCode]],
            options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(15 * 60)])
        openURL(challenge.verificationURL)
    }

    private func restartSignIn() {
        signInPresentation = nil
        signInBrowser = nil
        requestedSignIn = false
        model.cancel()
        model.connect()
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

#if DEBUG
/// An opt-in diagnostic. It never stores a credential or connects an account.
/// The web view uses a new in-memory cookie store that is discarded with this sheet.
private struct BrowserSignInResearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var host = "chatgpt.com"
    @State private var result = "Sign in to ChatGPT here. This test will check your own monthly meter."

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Website: \(host)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text(result)
                        .font(.footnote)
                        .accessibilityIdentifier("browserResearchResult")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                BrowserSignInResearchWebView(
                    onHost: { host = $0 },
                    onResult: { result = $0 }
                )
            }
            .navigationTitle("Browser sign-in test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

private struct BrowserSignInResearchWebView: UIViewRepresentable {
    let onHost: @MainActor (String) -> Void
    let onResult: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onHost: onHost, onResult: onResult) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.webView = webView
        configuration.websiteDataStore.httpCookieStore.add(context.coordinator)
        webView.load(URLRequest(url: URL(string: "https://chatgpt.com/auth/login")!))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.invalidate()
        webView.configuration.websiteDataStore.httpCookieStore.remove(coordinator)
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.stopLoading()
        coordinator.popup?.navigationDelegate = nil
        coordinator.popup?.uiDelegate = nil
        coordinator.popup?.stopLoading()
        coordinator.popup?.removeFromSuperview()
        coordinator.webView = nil
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
        weak var webView: WKWebView?
        weak var popup: WKWebView?
        var pendingCheck: Task<Void, Never>?
        private let onHost: @MainActor (String) -> Void
        private let onResult: @MainActor (String) -> Void
        private var needsCheck = false
        private var foundMonthlyMeter = false
        private var lastAttempt = Date.distantPast
        private var invalidated = false

        init(onHost: @escaping @MainActor (String) -> Void,
             onResult: @escaping @MainActor (String) -> Void) {
            self.onHost = onHost
            self.onResult = onResult
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !invalidated else { return }
            onHost(webView.url?.host ?? "Unknown")
            requestMemberMeterCheck()
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            requestMemberMeterCheck()
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard let parent = self.webView else { return nil }
            popup?.removeFromSuperview()
            let child = WKWebView(frame: parent.bounds, configuration: configuration)
            child.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            child.navigationDelegate = self
            child.uiDelegate = self
            parent.addSubview(child)
            popup = child
            return child
        }

        func webViewDidClose(_ webView: WKWebView) {
            guard !invalidated else { return }
            guard webView === popup else { return }
            webView.removeFromSuperview()
            popup = nil
            requestMemberMeterCheck()
        }

        private func requestMemberMeterCheck() {
            guard !invalidated, !foundMonthlyMeter else { return }
            needsCheck = true
            guard pendingCheck == nil else { return }
            pendingCheck = Task { @MainActor [weak self] in
                guard let self else { return }
                while self.needsCheck && !self.invalidated && !self.foundMonthlyMeter && !Task.isCancelled {
                    self.needsCheck = false
                    let wait = max(0, 2 - Date.now.timeIntervalSince(self.lastAttempt))
                    if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                    guard !Task.isCancelled, !self.invalidated, let webView = self.webView else { break }
                    guard webView.url?.scheme == "https", webView.url?.host == "chatgpt.com" else { continue }
                    self.lastAttempt = .now
                    await self.checkMemberMeter(in: webView)
                }
                self.pendingCheck = nil
            }
        }

        private func checkMemberMeter(in webView: WKWebView) async {
                do {
                    // Only a status and numeric meter values cross from WebKit into native code.
                    let raw = try await webView.callAsyncJavaScript(Self.memberMeterScript,
                        arguments: [:], in: nil, contentWorld: .page)
                    guard !invalidated, !Task.isCancelled else { return }
                    guard let response = raw as? [String: Any],
                          let status = response["status"] as? String else { return }
                    switch status {
                    case "monthly":
                        guard let used = response["used"] as? Double,
                              let limit = response["limit"] as? Double,
                              used.isFinite, limit.isFinite, used >= 0, limit > 0 else { return }
                        foundMonthlyMeter = true
                        onResult("Monthly meter found: \(used.formatted()) of \(limit.formatted()) credits used. This test has not connected the account.")
                    case "signedIn":
                        onResult("ChatGPT sign-in found. A monthly member meter was not returned.")
                    case "meterUnavailable":
                        onResult("ChatGPT sign-in found, but the monthly meter request was unavailable.")
                    default: break
                    }
                } catch {
                    // Provider errors and response bodies may contain sensitive data.
                    if !invalidated && !Task.isCancelled {
                        onResult("The browser test could not check the monthly meter.")
                    }
                }
        }

        func invalidate() {
            invalidated = true
            needsCheck = false
            pendingCheck?.cancel()
        }

        private static let memberMeterScript = """
        if (location.origin !== 'https://chatgpt.com') return { status: 'wrongOrigin' };
        async function fetchJSON(url, options) {
            const controller = new AbortController();
            const timeout = setTimeout(() => controller.abort(), 12000);
            try {
                const response = await fetch(url, { ...options, signal: controller.signal });
                return { ok: response.ok, body: response.ok ? await response.json() : null };
            } finally {
                clearTimeout(timeout);
            }
        }
        const sessionResponse = await fetchJSON('/api/auth/session', { credentials: 'include' });
        if (!sessionResponse.ok) return { status: 'sessionUnavailable' };
        const session = sessionResponse.body;
        const token = session?.accessToken;
        if (typeof token !== 'string' || !token) return { status: 'signInRequired' };
        try {
            const segment = token.split('.')[1];
            if (!segment) return { status: 'signedIn' };
            const padded = segment.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(segment.length / 4) * 4, '=');
            const claims = JSON.parse(atob(padded));
            const accountID = claims?.['https://api.openai.com/auth']?.chatgpt_account_id;
            if (typeof accountID !== 'string' || !accountID) return { status: 'signedIn' };
            const url = '/backend-api/accounts/' + encodeURIComponent(accountID) + '/spend-controls/current-user/monthly-usage';
            const response = await fetchJSON(url, {
                credentials: 'include',
                headers: { Authorization: 'Bearer ' + token, 'ChatGPT-Account-Id': accountID }
            });
            if (!response.ok) return { status: 'meterUnavailable' };
            const body = response.body;
            const number = value => value == null ? NaN : Number(value);
            const used = number(body?.current_month_usage);
            const limit = number(body?.effective_monthly_limit?.limit);
            if (!Number.isFinite(used) || !Number.isFinite(limit)) return { status: 'signedIn' };
            return { status: 'monthly', used, limit };
        } catch (_) {
            return { status: 'meterUnavailable' };
        }
        """
    }
}
#endif

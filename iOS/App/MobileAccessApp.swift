import SwiftUI
import SafariServices
import WebKit
import MobileAccessCore

@main
struct MobileAccessApp: App {
    var body: some Scene {
        WindowGroup { OverviewView() }
    }
}

struct ProbeView: View {
    let model: ProbeModel
    @State private var confirmDisconnect = false
    @State private var showSecuritySettings = false
    @State private var signInPresentation: CodexSignInPresentation?
    @State private var didCopyCode = false
    @State private var signInBrowser: CodexBrowserSession?
    var body: some View {
        Group {
            if model.connected && model.challenge == nil {
                AccountConnectionForm(plan: model.reading?.metadata?.displayPlan,
                    updated: model.reading?.fetchedAt, busy: model.busy,
                    needsReconnect: model.connectionFailure == .reconnect || model.connectionFailure == .renewal,
                    error: model.error, retry: { model.refresh() }, reconnect: { model.connect() },
                    disconnect: { confirmDisconnect = true })
            } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.message).font(.callout).accessibilityIdentifier("probe.status")
                    }
                    if !model.connected {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Enable device-code sign-in").font(.headline)
                            Text("Turn on device-code authorization in ChatGPT’s Security settings, then return here to sign in.")
                                .font(.callout)
                            Button("Open ChatGPT security settings") {
                                showSecuritySettings = true
                            }

                        }
                    }
                    if let challenge = model.challenge {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(challenge.userCode).font(.title.monospaced().bold()).textSelection(.enabled)
                            Button {
                                UIPasteboard.general.setItems(
                                    [[UIPasteboard.typeAutomatic: challenge.userCode]],
                                    options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(15 * 60)]
                                )
                                didCopyCode = true
                            } label: {
                                Label(didCopyCode ? "Copied" : "Copy code",
                                      systemImage: didCopyCode ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel(didCopyCode ? "Code copied. Copy again" : "Copy sign-in code")
                            Button("Open OpenAI sign-in") {
                                if signInBrowser == nil {
                                    signInBrowser = CodexBrowserSession(url: challenge.verificationURL)
                                }
                                if let signInBrowser {
                                    signInPresentation = CodexSignInPresentation(
                                        id: challenge.deviceAuthID, session: signInBrowser, code: challenge.userCode)
                                }
                            }
                                .buttonStyle(.borderedProminent)
                            Text("The sign-in page keeps your code and a Copy code button at the top. You can close and reopen it to resume this attempt.")
                                .font(.footnote).foregroundStyle(OverviewStyle.secondary)
                        }
                    }

                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(OverviewStyle.critical).font(.callout)
                    }
                    if model.busy {
                        HStack { ProgressView(); Button("Cancel") { model.cancel() } }
                    } else if model.connected {
                        VStack(alignment: .leading, spacing: 12) {
                            if model.connectionFailure == .reconnect {
                                Button("Reconnect Codex") { model.connect() }.buttonStyle(.borderedProminent)
                                Button("Retry refresh") { model.refresh() }
                            } else {
                                Button("Refresh quota") { model.refresh() }.buttonStyle(.borderedProminent)
                                Button("Reconnect Codex") { model.connect() }
                            }
                            if let date = model.renewedAt {
                                Text("Renewed \(date.formatted(date: .omitted, time: .standard))")
                                    .font(.caption).foregroundStyle(OverviewStyle.secondary)
                            }
                        }
                    } else {
                        Button("Connect Codex") { model.connect() }.buttonStyle(.borderedProminent)
                    }
                    if model.connected {
                        Divider().padding(.top, 12)
                        Button("Disconnect", role: .destructive) { confirmDisconnect = true }
                            .tint(OverviewStyle.critical).foregroundStyle(OverviewStyle.critical)
                            .frame(minHeight: 44).disabled(model.busy)
                    }
                }
                .frame(maxWidth: 700, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            }
            }
            .foregroundStyle(OverviewStyle.primary)
            .background(OverviewStyle.base)
            .navigationTitle("Codex account")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Remove this device’s connection?", isPresented: $confirmDisconnect) {
                Button("Disconnect", role: .destructive) { model.disconnect() }
            } message: {
                Text("Removes the local token and saved reading. It does not revoke the connection at OpenAI.")
            }
        .onChange(of: model.challenge?.deviceAuthID) { _, _ in
            didCopyCode = false
            signInBrowser = nil
            signInPresentation = nil
        }.sheet(item: $signInPresentation) { presentation in
            CodexSignInSheet(session: presentation.session, code: presentation.code)
        }.sheet(isPresented: $showSecuritySettings) {
            ProbeBrowser(url: URL(string: "https://chatgpt.com/#settings/Security")!)
        }.tint(OverviewStyle.accent)
    }
    @ViewBuilder private func windows(_ reading: QuotaReading) -> some View {
        window(reading.shortTerm, unavailableLabel: "Short-term")
        window(reading.weekly, unavailableLabel: "Weekly")
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

/// Present sign-in and settings pages in the app instead of dispatching external links.
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


/// Retained across sheet dismissal: reopening does not reload the login page.
@MainActor
final class CodexBrowserSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    let initialURL: URL
    @Published var host = "auth.openai.com"
    @Published var error: String?
    @Published var requiresSystemBrowser = false

    init(url: URL) {
        initialURL = url
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.load(URLRequest(url: url))
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url, url.scheme == "https" else {
            decisionHandler(.cancel)
            return
        }
        if url.host == "accounts.google.com" {
            requiresSystemBrowser = true
            decisionHandler(.cancel)
            return
        }
        if action.targetFrame?.isMainFrame != false { host = url.host ?? "Sign in" }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        host = webView.url?.host ?? "Sign in"
        error = nil
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled {
            self.error = "Couldn’t load the sign-in page. Try reloading or use the system browser."
        }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if action.targetFrame == nil, action.request.url?.scheme == "https",
           action.request.url?.host != "accounts.google.com" {
            webView.load(action.request)
        }
        return nil
    }
}

private struct CodexWebPage: UIViewRepresentable {
    let session: CodexBrowserSession
    func makeUIView(context: Context) -> WKWebView { session.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
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
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var showSystemBrowser = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ViewThatFits(in: .horizontal) {
                    HStack { codeLabel; Spacer(); copyButton }
                    VStack(alignment: .leading, spacing: 8) { codeLabel; copyButton }
                }
                .padding().background(.bar)
                if let error = session.error {
                    Text(error).font(.callout).padding()
                }
                CodexWebPage(session: session)
            }
            .navigationTitle(session.host)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Reload page", systemImage: "arrow.clockwise") { session.webView.reload() }
                        Button("Use system browser", systemImage: "safari") { showSystemBrowser = true }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Sign-in options")
                }
            }
            .alert("Use the system browser for Google sign-in", isPresented: $session.requiresSystemBrowser) {
                Button("Open system browser") { showSystemBrowser = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Google requires a system browser. Start sign-in there; its copy-code toolbar button remains available.")
            }
            .sheet(isPresented: $showSystemBrowser) {
                ProbeBrowser(url: session.initialURL, retainedController: systemBrowser())
            }
        }
    }
    private var codeLabel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Codex sign-in code").font(.caption).foregroundStyle(.secondary)
            Text(code).font(.headline.monospaced()).textSelection(.enabled)
        }
    }
    private var copyButton: some View {
        Button {
            UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: code]],
                options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(15 * 60)])
            copied = true
        } label: {
            Label(copied ? "Copied · Copy again" : "Copy code", systemImage: "doc.on.clipboard")
        }.buttonStyle(.borderedProminent)
    }
    private func systemBrowser() -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.barCollapsingEnabled = false
        configuration.activityButton = SFSafariViewController.ActivityButton(
            templateImage: UIImage(systemName: "doc.on.clipboard")!,
            extensionIdentifier: "com.niederme.AIQuota.copySignInCode")
        return SFSafariViewController(url: session.initialURL, configuration: configuration)
    }
}

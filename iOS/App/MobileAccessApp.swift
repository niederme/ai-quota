import SwiftUI
import SafariServices
import MobileAccessCore

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Sign in to Codex").font(.title2.bold())
                    VStack(alignment: .leading, spacing: 8) {
                        Text("First, check that Device Code Authorization is enabled in ChatGPT’s Security Settings, then continue.")
                            .foregroundStyle(.secondary)
                        Button(action: openSecurity) {
                            HStack(spacing: 6) {
                                Text("Open security settings")
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
                    continueSignIn: { beginSignIn() })
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
    }
    private func beginSignIn() {
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

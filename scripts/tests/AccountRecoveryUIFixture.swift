// Actual cards and additional-account detail; synthetic memory identities.
// Unrelated insight/history subviews are empty. No app model or sign-in is run.
import AppKit
import SwiftUI
import MobileAccessCore
@testable import AIQuotaKit

extension ConnectedAccount {
    func fixturePresentation(plan: String? = nil) -> AccountPresentation {
        .resolve(.init(key: id, service: provider == .codex ? "Codex" : "Claude", label: displayLabel,
                       plan: plan, origin: .user), among: [])
    }
}
struct MacQuotaInsightRow: View { let accountID: String; var body: some View { EmptyView() } }
struct CodexAnalyticsView: View {
    let reading: QuotaReading?
    let history: CodexUsageHistory?
    let historyUnavailable: Bool
    let busy: Bool
    let refresh: () -> Void
    var body: some View { EmptyView() }
}
@MainActor enum Calls { static var reconnected: [String] = []; static var opened: [String] = [] }
@MainActor final class RecoveryUI {
    let model = QuotaViewModel()
    let output: URL
    var window: NSWindow!
    init(_ output: URL) { self.output = output }
    func nodes(_ object: Any) -> [NSObject] {
        guard let item = object as? NSObject else { return [] }
        let sel = NSSelectorFromString("accessibilityChildren")
        let children = item.responds(to: sel) ? item.perform(sel)?.takeUnretainedValue() as? [Any] ?? [] : []
        return [item] + children.flatMap(nodes)
    }
    func label(_ item: NSObject) -> String {
        let sel = NSSelectorFromString("accessibilityLabel")
        return item.responds(to: sel) ? item.perform(sel)?.takeUnretainedValue() as? String ?? "" : ""
    }
    func render<V: View>(_ view: V, name: String, expectedButtons: Int) async throws {
        let host = NSHostingView(rootView: view.environment(model).environment(\.colorScheme, name.contains("light") ? .light : .dark).frame(width: 480, height: 820, alignment: .top))
        window.contentView = host
        window.setContentSize(.init(width: 480, height: 820))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        _ = nodes(host)
        try await Task.sleep(for: .milliseconds(500))
        host.layoutSubtreeIfNeeded()
        var all = nodes(host)
        for _ in 0..<6 where all.filter({ label($0).hasPrefix("Reconnect ") }).count < expectedButtons {
            try await Task.sleep(for: .milliseconds(150)); all = nodes(host)
        }
        let buttons = all.filter { label($0).hasPrefix("Reconnect ") }
        let nativeAccessibilityAvailable = all.contains { !label($0).isEmpty }
        let beforeReconnect = Calls.reconnected.count
        if nativeAccessibilityAvailable {
            guard buttons.count == expectedButtons else { throw NSError(domain: "\(name) reconnect count \(buttons.count), expected \(expectedButtons). Labels: \(all.map(label))", code: 1) }
            let beforeOpen = Calls.opened.count
            for button in buttons {
                let sel = NSSelectorFromString("accessibilityPerformPress")
                guard button.responds(to: sel) else { throw NSError(domain: "missing native button action", code: 1) }
                _ = button.perform(sel)
            }
            try await Task.sleep(for: .milliseconds(100))
            guard Calls.opened.count == beforeOpen, Calls.reconnected.count == beforeReconnect + expectedButtons else {
                throw NSError(domain: "Reconnect must invoke only its own callback", code: 1)
            }
        }
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("bitmap") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
        let evidence: [String: Any] = ["labels": all.map(label).filter { !$0.isEmpty }, "nativeAccessibilityAvailable": nativeAccessibilityAvailable, "expectedReconnectButtons": expectedButtons, "reconnectButtons": buttons.map(label),
                                     "callbackTargets": Array(Calls.reconnected.dropFirst(beforeReconnect))]
        try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent(name + ".json"))
        print("RENDERED: \(name); native accessibility \(nativeAccessibilityAvailable ? "verified" : "unavailable in this host")")
    }
    func run() async throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        window = NSWindow(contentRect: .init(x: 100, y: 100, width: 480, height: 820), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        for failure in [NetworkError.tokenExpired, .networkUnavailable] {
            let auth = failure.needsReconnect
            model.codexError = failure; model.claudeError = failure
            for session in model.additionalAccounts { session.issue = failure.localizedDescription; session.issueError = failure }
            for appearance in ["dark", "light"] {
                window.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
                let cards = VStack(spacing: 8) {
                    Text("Saved readings · \(auth ? "Session expired" : "Network unavailable")").font(.headline).padding()
                    ForEach(AccountRegistry.fixtures) { account in
                        let session = self.model.additionalAccounts.first { $0.id == account.id }
                        MacAccountCard(account: account, session: session, tokenHistory: nil, availableWidth: 416,
                                       showsAccountLabel: true, open: { Calls.opened.append(account.id) },
                                       reconnect: { Calls.reconnected.append(account.id) }, highlighted: false)
                    }
                }.padding(16).background(Color.sheetTint)
                try await render(cards, name: "cards-\(auth ? "expired" : "network")-\(appearance)", expectedButtons: auth ? 4 : 0)
                for session in model.additionalAccounts {
                    let detail = MacAdditionalAccountDetailView(session: session, height: 820, close: {}, openSettings: {},
                                                               reconnect: { Calls.reconnected.append(session.id) }).background(Color.sheetTint)
                    try await render(detail, name: "detail-\(session.provider)-\(auth ? "expired" : "network")-\(appearance)", expectedButtons: auth ? 1 : 0)
                }
            }
        }
        // Same temporary restoration failure, with and without a last-good
        // reading. Both Codex accounts must offer retry without a login prompt.
        model.codexState = .unauthenticated; model.isCodexAuthenticated = false
        model.isCodexRestorationRetryable = true; model.codexError = .httpError(statusCode: 503)
        model.claudeError = nil
        for session in model.additionalAccounts {
            session.issue = nil; session.issueError = nil
            if session.provider == .codex {
                session.state = .unauthenticated; session.isAuthenticated = false
                session.isCodexRestorationRetryable = true
                session.issueError = .httpError(statusCode: 503)
                session.issue = session.issueError?.localizedDescription
            }
        }
        let savedPrimary = model.codexUsage
        let isolated = model.additionalAccounts.first { $0.provider == .codex }
        let savedAdditional = isolated?.codexUsage
        for variant in ["cached", "missing-primary", "missing-additional", "missing-both"] {
            model.codexUsage = variant == "missing-primary" || variant == "missing-both" ? nil : savedPrimary
            isolated?.codexUsage = variant == "missing-additional" || variant == "missing-both" ? nil : savedAdditional
            for appearance in ["dark", "light"] {
                window.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
                let cards = VStack(spacing: 8) {
                    Text("Temporary Codex restore · Saved readings stay dated").font(.headline).padding()
                    ForEach(AccountRegistry.fixtures.filter { $0.provider == .codex }) { account in
                        MacAccountCard(account: account, session: self.model.additionalAccounts.first { $0.id == account.id },
                            tokenHistory: nil, availableWidth: 416, showsAccountLabel: true,
                            open: { Calls.opened.append(account.id) }, reconnect: { Calls.reconnected.append(account.id) }, highlighted: false)
                    }
                }.padding(16).background(Color.sheetTint)
                try await render(cards, name: "codex-temporary-\(variant)-\(appearance)", expectedButtons: 0)
                if let session = model.additionalAccounts.first(where: { $0.provider == .codex }) {
                    let detail = MacAdditionalAccountDetailView(session: session, height: 820, close: {}, openSettings: {},
                        reconnect: { Calls.reconnected.append(session.id) }).background(Color.sheetTint)
                    try await render(detail, name: "codex-temporary-detail-\(variant)-\(appearance)", expectedButtons: 0)
                }
            }
        }
    }
}
@main enum App {
    static func main() {
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Account recovery UI checks")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            do { try await RecoveryUI(URL(fileURLWithPath: CommandLine.arguments[1])).run(); exit(0) }
            catch { print(error); exit(1) }
        }
        app.run()
    }
}

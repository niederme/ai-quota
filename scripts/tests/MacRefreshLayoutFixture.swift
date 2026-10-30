// Native regression fixture: production cards with
// synthetic in-memory accounts. No credentials, real registry writes or networking.
import AppKit
import SwiftUI
import QuartzCore
@testable import AIQuotaKit

@MainActor @Observable final class AdditionalAccountSession: Identifiable {
    let account: ConnectedAccount
    nonisolated let id: String
    var provider: ServiceType { account.provider }
    var state: AuthState = .authenticated
    var isLoading = false
    var isAuthenticated = true
    var issue: String?
    var codexUsage: CodexUsage?
    var claudeUsage: ClaudeUsage?
    var codexTokenHistory: CodexTokenHistory?
    init(_ account: ConnectedAccount) { self.account = account; self.id = account.id }
    func refreshTokenHistory(force: Bool = false) {}
    func refresh() async {}
}
@MainActor enum AccountRegistry {
    static var fixtures: [ConnectedAccount] = []
    static func orderedAccounts() -> [ConnectedAccount] { fixtures }
    static func setAccountOrder(_ ids: [String]) {}
}
@MainActor @Observable final class QuotaViewModel {
    var enrolledServices: Set<ServiceType> = [.codex, .claude]
    var additionalAccounts: [AdditionalAccountSession] = []
    var codexUsage: CodexUsage?
    var claudeUsage: ClaudeUsage?
    var codexTokenHistory: CodexTokenHistory?
    var codexState: AuthState = .authenticated
    var claudeState: AuthState = .authenticated
    var isCodexRecovering = false
    var isClaudeRecovering = false
    var isCodexLoading = false
    var isClaudeLoading = false
    var isCodexAuthenticated = true
    var isClaudeAuthenticated = true
    var codexError: NSError?
    var claudeError: NSError?
    var lastRefreshedAt: Date? = .now
    func manualRefresh() {}
    func refreshTokenHistory() {}
    func reconnectAccount(id: String) async {}
    func signIn() async {}
    func signInClaude() async {}
    init() {
        let now = Date.now
        let first = ConnectedAccount(provider: .codex, displayLabel: "Personal", workspaceID: "sample-personal", authSource: .oauth, connectionKind: .legacyPrimary)
        let second = ConnectedAccount(provider: .claude, displayLabel: "Personal", authSource: .webSession, connectionKind: .legacyPrimary)
        let third = ConnectedAccount(provider: .claude, displayLabel: "Claude Enterprise", authSource: .webSession)
        let fourth = ConnectedAccount(provider: .codex, displayLabel: "Codex Enterprise", workspaceID: "sample-business", authSource: .oauth)
        AccountRegistry.fixtures = [first, second, third, fourth]
        func codex(monthly: Bool) -> CodexUsage {
            CodexUsage(weeklyUsedPercent: 24, weeklyResetAt: now.addingTimeInterval(86400), weeklyResetAfterSeconds: 86400,
                       hourlyUsedPercent: 0, hourlyResetAt: now.addingTimeInterval(3600), hourlyResetAfterSeconds: 3600,
                       hourlyWindowSeconds: 18000, limitReached: false, allowed: true, planType: monthly ? "business" : "pro",
                       creditBalance: nil, approxLocalMessages: nil, approxCloudMessages: nil, fetchedAt: now,
                       monthlyBudget: monthly ? .init(unit: "credit", used: 26.96, limit: 7000, resetAt: now.addingTimeInterval(5 * 86400)) : nil,
                       reportedWindowShape: monthly ? nil : .weeklyOnly)
        }
        codexUsage = codex(monthly: false)
        claudeUsage = ClaudeUsage(fiveHourUtilization: 25, fiveHourResetsAt: now.addingTimeInterval(3 * 3600),
                                  sevenDayUtilization: 4, sevenDayResetsAt: now.addingTimeInterval(2 * 86400),
                                  extraUsage: nil, planLabel: .pro, fetchedAt: now)
        let enterprise = AdditionalAccountSession(third)
        enterprise.claudeUsage = ClaudeUsage(fiveHourUtilization: nil, fiveHourResetsAt: nil, sevenDayUtilization: nil, sevenDayResetsAt: nil,
                                             extraUsage: nil, spendLimit: .init(used: 115.39, limit: 200, utilization: 58, currencyCode: "USD"),
                                             planLabel: .enterprise, fetchedAt: now)
        let business = AdditionalAccountSession(fourth)
        business.codexUsage = codex(monthly: true)
        let formatter = CodexTokenHistory.dateFormatter()
        let tokens = Dictionary(uniqueKeysWithValues: (0..<294).map { day in
            (formatter.string(from: now.addingTimeInterval(Double(-day) * 86400)), Double((day * 37) % 13) * 1000)
        })
        codexTokenHistory = CodexTokenHistory(tokensByDate: tokens, fetchedAt: now, scopeID: nil, attribution: .verifiedWorkspace("sample-personal"))
        business.codexTokenHistory = CodexTokenHistory(tokensByDate: tokens.filter { $0.key >= formatter.string(from: now.addingTimeInterval(-5 * 86400)) },
                                                       fetchedAt: now, scopeID: nil, attribution: .verifiedWorkspace("sample-business"))
        additionalAccounts = [enterprise, business]
    }
}

@MainActor enum FixtureMeasurements {
    static var rows: [String: CGRect] = [:]
    static var graphs: [String: CGRect] = [:]
}

struct StatusFixture: View {
    let model: QuotaViewModel
    let width: CGFloat
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("AIQuota").font(.system(size: 28, weight: .semibold)).padding(16)
            ForEach(AccountRegistry.fixtures) { account in
                let session = model.additionalAccounts.first { $0.id == account.id }
                MacAccountCard(account: account, session: session,
                               tokenHistory: account.connectionKind == .isolated ? session?.codexTokenHistory : model.codexTokenHistory,
                               availableWidth: width - 64, showsAccountLabel: true,
                               open: {}, reconnect: {}, highlighted: false)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("fixture")) }
                    action: { FixtureMeasurements.rows[account.id] = $0 }
            }
            HStack {
                Text("Settings")
                Spacer()
                Text("Saved reading fixture").foregroundStyle(.secondary)
                Spacer()
                Text("Quit")
            }.font(.system(size: 13, weight: .semibold)).padding(16)
        }
        .padding(.horizontal, 16)
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
        .coordinateSpace(name: "fixture")
        .environment(model)
        .environment(\.colorScheme, CommandLine.arguments.contains("--light") ? .light : .dark)
        .foregroundStyle(Color.overviewPrimary)
        .background {
            Color.sheetTint
            RadialGradient(colors: [.sheetGlow, .clear], center: .topLeading, startRadius: 0, endRadius: 520)
        }
    }
}

@MainActor final class StatusFixtureDelegate: NSObject {
    let model = QuotaViewModel()
    var window: NSWindow!
    let output = URL(fileURLWithPath: CommandLine.arguments[1])
    var reports: [String: Any] = [:]
    var failures: [String] = []

    func start() {
        NSApp.setActivationPolicy(.accessory)
        window = NSWindow(contentRect: .init(x: 120, y: 100, width: 480, height: 900),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: CommandLine.arguments.contains("--light") ? .aqua : .darkAqua)
        window.isReleasedWhenClosed = false
        Task { await run() }
    }

    func setState(_ name: String) {
        model.isCodexLoading = name == "refreshing"
        model.isClaudeLoading = name == "refreshing"
        let error = name == "saved-reading" || name == "error"
            ? NSError(domain: "Fixture", code: 1, userInfo: [NSLocalizedDescriptionKey:
                name == "error" ? "The request timed out. Try refreshing again." : "The service is temporarily unavailable."])
            : nil
        model.codexError = error
        model.claudeError = error
        for session in model.additionalAccounts {
            session.isLoading = name == "refreshing"
            session.issue = error?.localizedDescription
        }
    }

    func settle() async { try? await Task.sleep(for: .milliseconds(350)) }

    func serialized(_ frames: [String: CGRect]) -> [String: [Double]] {
        Dictionary(uniqueKeysWithValues: frames.map { key, f in (key, [f.minX, f.minY, f.width, f.height]) })
    }

    func accessibilityLabels(_ object: Any) -> [String] {
        guard let item = object as? NSObject else { return [] }
        func value(_ name: String) -> Any? {
            let selector = NSSelectorFromString(name)
            return item.responds(to: selector) ? item.perform(selector)?.takeUnretainedValue() : nil
        }
        var labels = [value("accessibilityLabel") as? String, value("accessibilityHelp") as? String].compactMap { $0 }
        for child in value("accessibilityChildren") as? [Any] ?? [] { labels += accessibilityLabels(child) }
        return labels
    }

    func run() async {
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            // Warm up SwiftUI's lazy native accessibility bridge before measuring.
            let warmup = NSHostingView(rootView: StatusFixture(model: model, width: 480))
            window.contentView = warmup
            await settle()
            _ = accessibilityLabels(warmup)
            for width: CGFloat in [480, 420, 360] {
                setState("normal")
                var hosting = NSHostingView(rootView: StatusFixture(model: model, width: width))
                window.contentView = hosting
                window.setContentSize(.init(width: width, height: 1000))
                await settle()
                window.setContentSize(hosting.fittingSize)
                await settle()
                _ = accessibilityLabels(hosting)
                await settle()
                let baseSize = hosting.fittingSize
                let baseRows = FixtureMeasurements.rows
                let baseGraphs = FixtureMeasurements.graphs
                // Recreate the hosting hierarchy with the same cached model, as
                // MenuBarExtra does on reopen. Include a pre-existing failure,
                // fast completion, a slow request, failure and recovery.
                for cycle in 0..<3 {
                    for state in ["saved-reading", "refreshing", "normal", "refreshing", "slow-refresh", "error", "normal"] {
                        setState(state == "slow-refresh" ? "refreshing" : state)
                        if state == "refreshing" {
                            window.contentView = nil
                            FixtureMeasurements.rows = [:]
                            FixtureMeasurements.graphs = [:]
                            hosting = NSHostingView(rootView: StatusFixture(model: model, width: width))
                            window.contentView = hosting
                        }
                        if state == "slow-refresh" { try await Task.sleep(for: .seconds(1)) }
                        await settle()
                        hosting.layoutSubtreeIfNeeded()
                        let name = "\(Int(width))-\(cycle)-\(state)-\(reports.count)"
                        let rows = FixtureMeasurements.rows, graphs = FixtureMeasurements.graphs
                        if hosting.fittingSize != baseSize { failures.append("\(name): sheet fitting size changed") }
                        if rows.count != 4 || graphs.count != 2 { failures.append("\(name): missing row or graph geometry") }
                        if rows != baseRows { failures.append("\(name): row geometry changed") }
                        if graphs != baseGraphs { failures.append("\(name): heatmap geometry changed") }
                        // SwiftUI installs its native accessibility children
                        // lazily after a new host is attached.
                        var labels = accessibilityLabels(hosting)
                        let expected = state == "saved-reading" || state == "error"
                            ? "Couldn’t update · Saved reading"
                            : (state.contains("refresh") ? "Refreshing saved reading" : "Open account details")
                        for _ in 0..<5 where labels.filter({ $0.contains(expected) }).count < 4 {
                            await settle()
                            labels = accessibilityLabels(hosting)
                        }
                        if state == "saved-reading" || state == "error" {
                            if labels.filter({ $0.contains("Couldn’t update · Saved reading") }).count < 4 {
                                failures.append("\(name): missing accessible saved-reading status")
                            }
                            if labels.filter({ $0.contains(state == "error" ? "The request timed out" : "temporarily unavailable") }).count < 4 {
                                failures.append("\(name): missing accessible error explanation")
                            }
                        } else if state.contains("refresh") {
                            if labels.filter({ $0.contains("Refreshing saved reading") }).count < 4 {
                                failures.append("\(name): missing accessible refresh progress")
                            }
                        } else if labels.contains(where: { $0.contains("Couldn’t update") || $0.contains("Refreshing saved reading") }) {
                            failures.append("\(name): stale status after success")
                        }
                        reports[name] = ["rows": serialized(rows), "heatmaps": serialized(graphs), "accessibility": labels]
                        print("Checked \(name): \(rows.count) cards, \(graphs.count) heatmaps, \(labels.count) accessibility entries")
                        fflush(stdout)
                    }
                }
            }
            reports["failures"] = failures
            try JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("geometry-and-accessibility.json"))
            print("\(failures.isEmpty ? "PASS" : "FAIL"): 4 account types × 7 transitions × 3 cycles × 3 widths; rows, heatmaps and accessibility")
            for failure in failures { print(failure) }
            exit(failures.isEmpty ? 0 : 1)
        } catch { print(error); exit(2) }
    }
}

@main struct StatusFixtureApp {
    static func main() {
        // Offscreen test hosts otherwise qualify for App Nap, which can defer
        // layout/accessibility updates well beyond the bounded test timeout.
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical],
                                                            reason: "Mac card layout regression test")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        let application = NSApplication.shared
        let delegate = StatusFixtureDelegate()
        // A command-line test has no app bundle/LaunchServices launch event.
        // Schedule directly instead of depending on didFinishLaunching.
        delegate.start()
        application.run()
    }
}

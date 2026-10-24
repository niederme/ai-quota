// These adapters execute the exact refreshClaude body extracted from the app
// source by the runner. They replace app/UI persistence and notifications with
// memory only. The macOS app itself is neither linked nor launched.
import Foundation
@testable import AIQuotaKit

// Local names intentionally shadow production persistence/notification types in
// this executable. AIQuotaKit's separately compiled widget uses its injected Store.
enum SharedDefaults {
    static let usage = Memory<ClaudeUsage?>(nil)
    static func saveClaudeUsage(_ value: ClaudeUsage) { usage.edit { $0 = value } }
    static func saveClaudeUsage(_ value: ClaudeUsage, forAccountID: String) { usage.edit { $0 = value } }
    static func clearClaudeUsage() { usage.edit { $0 = nil } }
}
actor NotificationManager {
    static let shared = NotificationManager()
    func evaluate(claude: ClaudeUsage, prefs: DummyPrefs) {}
    func notifyPlanChange(service: String, previous: String?, current: String?, enabled: Bool) {}
}
struct DummyPrefs { var enabled = false; var claudeEnabled = false }
struct DummySettings { var notifications = DummyPrefs() }
struct LogMessage: ExpressibleByStringInterpolation {
    enum Privacy { case `public` }
    init(stringLiteral: String) {}
    init(stringInterpolation: StringInterpolation) {}
    struct StringInterpolation: StringInterpolationProtocol {
        init(literalCapacity: Int, interpolationCount: Int) {}
        mutating func appendLiteral(_ text: String) {}
        mutating func appendInterpolation<T>(_ value: T) {}
        mutating func appendInterpolation<T>(_ value: T, privacy: Privacy) {}
    }
}
struct DummyLogger {
    func info(_ message: LogMessage) {}
    func warning(_ message: LogMessage) {}
}
struct DummyPathMonitor { enum Status { case satisfied }; struct Path { var status: Status = .satisfied }; var currentPath = Path() }
actor DummyUsageClient {
    var actions: [@Sendable () async throws -> ClaudeUsage]
    init(_ actions: [@Sendable () async throws -> ClaudeUsage]) { self.actions = actions }
    func fetchUsage() async throws -> ClaudeUsage {
        guard !actions.isEmpty else { throw NetworkError.notAuthenticated }
        return try await actions.removeFirst()()
    }
}
actor DummyRecovery {
    private(set) var calls = 0
    func revalidateSessionAfterAuthFailure() -> Bool { calls += 1; return true }
}

@MainActor final class PrimaryClaudeAdapter {
    static let isDemoBuild = false
    var isClaudeAuthenticated = true
    var isClaudeLoading = false
    var claudeRefreshGeneration = 0
    var claudeUsage: ClaudeUsage?
    var claudeError: NetworkError?
    var lastRefreshedAt: Date?
    let claudeClient: DummyUsageClient
    let claudeCoordinator = DummyRecovery()
    let logger = DummyLogger()
    let pathMonitor = DummyPathMonitor()
    let pathMonitorReady = true
    let settings = DummySettings()
    init(_ client: DummyUsageClient) { claudeClient = client }
    enum Service { case claude }
    struct Account { var id = "dummy-primary" }
    func primaryAccount(for service: Service) -> Account? { Account() }
    func shouldPreserveClaudeLastGood(_ result: ClaudeUsage) -> Bool { false }
    func recordServiceActivityIfNeeded(from: ClaudeUsage?, to: ClaudeUsage) {}
    func isConnectivityError(_ error: Error) -> Bool { false }
    // SOURCE_REFRESH_CLAUDE
}

func dummyReading(_ org: String) -> ClaudeUsage {
    ClaudeUsage(fiveHourUtilization: 12, fiveHourResetsAt: nil,
                sevenDayUtilization: 24, sevenDayResetsAt: nil, extraUsage: nil,
                planLabel: .pro, source: .web, fetchedAt: .now, quotaScopeID: org)
}
@MainActor func runPrimaryRefreshChecks() async throws {
    var failures: [String] = []
    for scenario in ["late success", "after removal", "late auth error", "retry success", "unchanged control"] {
        let gate = Gate<ClaudeUsage>()
        let client = DummyUsageClient(scenario == "retry success"
            ? [{ throw NetworkError.notAuthenticated }, { try await gate.wait() }]
            : [{ try await gate.wait() }])
        let sut = PrimaryClaudeAdapter(client)
        SharedDefaults.clearClaudeUsage()
        let task = Task { await sut.refreshClaude() }
        for _ in 0..<2_000 {
            if await gate.waiting { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        try require(await gate.waiting, "primary dummy request did not suspend")
        let unchanged = scenario == "unchanged control"
        if !unchanged {
            sut.claudeRefreshGeneration += 1
            sut.isClaudeAuthenticated = scenario != "after removal"
            sut.claudeUsage = scenario == "after removal" ? nil : dummyReading("dummy-B")
            SharedDefaults.usage.edit { $0 = sut.claudeUsage }
        }
        if scenario == "late auth error" { await gate.finish(.failure(NetworkError.notAuthenticated)) }
        else { await gate.finish(.success(dummyReading("dummy-A"))) }
        await task.value
        let expected: String? = unchanged ? "dummy-A" : scenario == "after removal" ? nil : "dummy-B"
        if sut.claudeUsage?.quotaScopeID != expected || SharedDefaults.usage.read()?.quotaScopeID != expected {
            failures.append(scenario)
            print("FAIL: primary Claude \(scenario)")
        } else { print("PASS: primary Claude \(scenario)") }
    }
    try require(failures.isEmpty, "primary source regression failures: \(failures.joined(separator: ", "))")
    print("PASS: 5 primary Claude source-body checks with memory adapters")
}

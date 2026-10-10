import Foundation
import Observation
import WidgetKit
import UIKit
import WebKit
import MobileAccessCore

@MainActor @Observable
final class ProbeModel {
    private let shared: SharedQuotaStore
    private var foregroundRefresh = ForegroundRefreshPolicy()
    private(set) var quietlyRefreshing = false
    var loading: Bool { busy && !quietlyRefreshing }
    private let api: CodexAPI
    private let tokenHistoryCache: CodexTokenHistoryCache
    private let fetchUsage: (@Sendable (Bool, TimeInterval) async throws -> QuotaReading)?
    private let defaults: UserDefaults
    private var work: Task<Void, Never>?
    private var generation = UUID()
    private var tokens: CodexTokens?
    private(set) var challenge: DeviceChallenge? {
        didSet { if challenge == nil { try? SignInCodeStore.clear() } }
    }
    private(set) var tokenHistory: CodexTokenHistory?
    private(set) var tokenHistoryUnavailable = false
    private(set) var tokenHistoryLoading = false
    private var tokenHistoryScope = CodexTokenHistoryScope()
    private var tokenHistoryAttempt: Date?
    private(set) var history: CodexUsageHistory?
    private(set) var historyUnavailable = false
    private let historyCacheKey = "mobileProbe.codexHistory"
    private(set) var reading: QuotaReading?
    private(set) var signInCompletionID: UUID?
    private(set) var busy = false
    private(set) var message = "Connect Codex to see your usage."
    private(set) var error: String?
    private(set) var renewedAt: Date?
    private(set) var connectionFailure: SharedQuotaStore.Failure?
    let isDemo: Bool
    var connected: Bool { isDemo || tokens != nil }
    private let cacheKey = "mobileProbe.codexReading"

    init(isDemo: Bool = false, api: CodexAPI = CodexAPI(), shared: SharedQuotaStore = SharedQuotaStore(.codex),
         defaults: UserDefaults = .standard,
         fetchUsage: (@Sendable (Bool, TimeInterval) async throws -> QuotaReading)? = nil) {
        self.isDemo = isDemo
        self.api = api
        self.shared = shared
        self.defaults = defaults
        self.fetchUsage = fetchUsage
        self.tokenHistoryCache = CodexTokenHistoryCache(defaults: defaults)
        if isDemo {
            reading = DemoQuotaData.reading(.codex)
            history = DemoQuotaData.history()
            tokenHistory = DemoQuotaData.tokenHistory()
            message = "Sample usage. No account connected."
            return
        }
        do {
            tokens = try shared.load(CodexTokens.self) ?? TokenStore.load()
            if tokens != nil {
                alignTokenHistory(to: tokens)
                connectionFailure = shared.failure()
                message = "Connected. Your usage updates automatically."
                reading = shared.reading()
                if let data = defaults.data(forKey: historyCacheKey) {
                    history = try? JSONDecoder().decode(CodexUsageHistory.self, from: data)
                }
                if reading == nil, let data = defaults.data(forKey: cacheKey) {
                    reading = try? JSONDecoder().decode(QuotaReading.self, from: data)
                }
            }
        } catch { self.error = "Could not read this device’s saved connection." }
    }
    func connect() {
        guard !isDemo else { return }
        guard !busy else { return }
        run { [self] in
            let newChallenge = try await api.requestChallenge()
            try Task.checkCancellation()
            try SignInCodeStore.save(code: newChallenge.userCode, expiresAt: .now.addingTimeInterval(15 * 60))
            challenge = newChallenge
            message = "Open the sign-in page, enter this code, then return here."
            let deadline = Date.now.addingTimeInterval(15 * 60)
            while Date.now < deadline {
                try await Task.sleep(for: .seconds(newChallenge.interval))
                try Task.checkCancellation()
                if let code = try await api.poll(newChallenge) {
                    let newTokens = try await api.exchange(code)
                    try Task.checkCancellation()
                    try await shared.withLease { [shared] in
                        try shared.saveCredentials(newTokens)
                        try TokenStore.clear()
                    }
                    clearTokenHistory()
                    tokenHistoryCache.clear()
                    history = nil
                    historyUnavailable = false
                    defaults.removeObject(forKey: historyCacheKey)
                    foregroundRefresh.reset()
                    tokens = newTokens
                    challenge = nil
                    message = "Signed in on this device. Checking quota…"
                    try await fetch(forceRenewal: false)
                    signInCompletionID = UUID()
                    return
                }
            }
            throw AccessError.expired
        }
    }
    func refresh(forceRenewal: Bool = false) {
        if isDemo {
            reading = DemoQuotaData.reading(.codex)
            return
        }
        guard !busy, connected else { return }
        run { [self] in try await fetch(forceRenewal: forceRenewal) }
    }
    func refreshAndWait() async {
        refresh()
        await work?.value
    }
    func refreshOnOpen() {
        guard !isDemo else { refresh(); return }
        guard !busy, connected else { return }
        // Invalidate token history before the foreground quota throttle on account changes.
        let current = try? shared.load(CodexTokens.self) ?? TokenStore.load()
        alignTokenHistory(to: current)
        // A widget may have published a newer successful reading while the app was inactive.
        if let cached = shared.reading(), cached.fetchedAt > (reading?.fetchedAt ?? .distantPast) {
            reading = cached
            error = nil
            connectionFailure = shared.failure()
        }
        guard foregroundRefresh.beginAutomatic(at: .now, reading: reading) else {
            if tokenHistory == nil, tokenHistoryAttempt == nil, let current {
                quietlyRefreshing = reading != nil
                run { [self] in await refreshTokenHistory(current) }
            }
            return
        }
        quietlyRefreshing = reading != nil
        run { [self] in try await fetch(forceRenewal: false, minimumAge: 30) }
    }
    func retryTokenHistory() {
        guard !busy else { return }
        tokenHistoryAttempt = nil
        refresh()
    }
    private func fetch(forceRenewal: Bool, minimumAge: TimeInterval = 0) async throws {
        let current = try? shared.load(CodexTokens.self) ?? TokenStore.load()
        alignTokenHistory(to: current)
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Refresh allowance") { [weak self] in
            Task { @MainActor in self?.work?.cancel() }
        }
        defer { if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) } }

        // Migrate once under the same lease used by widget renewal. Never overwrite newer shared credentials.
        try await shared.withLease { [shared] in
            if try shared.load(CodexTokens.self) == nil, let old = try TokenStore.load() {
                try shared.saveCredentials(old)
            }
            try TokenStore.clear()
            try WidgetStore.clearAccess()
        }
        message = "Refreshing…"
        let value: QuotaReading
        if let fetchUsage { value = try await fetchUsage(forceRenewal, minimumAge) }
        else { value = try await shared.fetch(source: "app", forceRenewal: forceRenewal, minimumAge: minimumAge) }
        try Task.checkCancellation()
        tokens = try shared.load(CodexTokens.self)
        alignTokenHistory(to: tokens)
        reading = value
        connectionFailure = nil
        defaults.set(try JSONEncoder().encode(value), forKey: cacheKey)
        if forceRenewal { renewedAt = .now }
        WidgetCenter.shared.reloadAllTimelines()
        message = "Usage updated."
        // History is optional: an unavailable analytics endpoint must not mark quota stale.
        if let tokens {
            await refreshTokenHistory(tokens)
            try Task.checkCancellation()
            do {
                let updated = try await api.usageHistory(tokens)
                try Task.checkCancellation()
                history = updated
                historyUnavailable = false
                defaults.set(try JSONEncoder().encode(updated), forKey: historyCacheKey)
            } catch is CancellationError { throw CancellationError() }
            catch { historyUnavailable = true }
        }
    }
    private func clearTokenHistory() {
        tokenHistory = nil
        tokenHistoryUnavailable = false
        tokenHistoryLoading = false
        tokenHistoryAttempt = nil
    }
    private func alignTokenHistory(to credential: CodexTokens?) {
        let scopeID = credential.map(CodexAPI.tokenHistoryScope)
        guard tokenHistoryScope.update(scopeID: scopeID) else { return }
        clearTokenHistory()
        tokenHistory = tokenHistoryCache.load(scopeID: scopeID)
    }
    private func refreshTokenHistory(_ credential: CodexTokens) async {
        let scope = CodexAPI.tokenHistoryScope(credential)
        alignTokenHistory(to: credential)
        if let tokenHistoryAttempt, Date.now.timeIntervalSince(tokenHistoryAttempt) < 900 { return }
        tokenHistoryAttempt = .now
        let requestGeneration = generation
        tokenHistoryLoading = true
        defer { if generation == requestGeneration { tokenHistoryLoading = false } }
        do {
            let updated = try await api.tokenHistory(credential)
            try Task.checkCancellation()
            guard generation == requestGeneration,
                  let current = try shared.load(CodexTokens.self), CodexAPI.tokenHistoryScope(current) == scope else {
                clearTokenHistory(); return
            }
            // An absent/unsupported graph is a failed refresh, not an empty history.
            // Keep the current account's valid snapshot; a decoded empty array is authoritative.
            if let updated {
                tokenHistory = updated
                tokenHistoryCache.save(updated)
            }
            tokenHistoryUnavailable = updated == nil
        } catch {
            guard generation == requestGeneration, !Task.isCancelled else { return }
            guard let current = try? shared.load(CodexTokens.self), CodexAPI.tokenHistoryScope(current) == scope else {
                clearTokenHistory(); return
            }
            tokenHistoryUnavailable = true
        }
    }
    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        error = nil
        busy = true
        let id = UUID()
        generation = id
        work = Task { [weak self] in
            do { try await action() }
            catch is CancellationError { }
            catch {
                guard let self, self.generation == id else { return }
                // Never surface raw response bodies, tokens, or provider error URLs.
                self.error = (error as? AccessError)?.errorDescription
                    ?? "The request did not complete. Check your connection and try again."
                self.connectionFailure = SharedQuotaStore.Failure.classify(error)
                if self.tokens != nil { self.tokenHistoryUnavailable = true }
                self.message = "Couldn’t update usage. Your last reading is still shown."
            }
            guard let self, self.generation == id else { return }
            self.quietlyRefreshing = false
            self.busy = false
            self.challenge = nil
            self.work = nil
        }
    }
    func cancel() {
        guard !isDemo else { return }
        generation = UUID()
        work?.cancel()
        work = nil
        quietlyRefreshing = false
        busy = false
        challenge = nil
        message = "Check cancelled."
    }
    func disconnect() {
        guard !isDemo else { return }
        guard !busy else { return }
        run { [self] in try await clearConnection() }
    }
    /// Await cancelled requests before clearing so a late response cannot restore credentials.
    func resetForNewUser() async throws {
        guard !isDemo else { return }
        let pending = work
        clearTokenHistory()
        cancel()
        busy = true
        defer { busy = false }
        await pending?.value
        try await clearConnection()
        foregroundRefresh.reset()
        signInCompletionID = nil
        message = "Connect Codex to see your usage."
    }
    private func clearConnection() async throws {
        try await shared.withLease { [shared] in
            try TokenStore.clear()
            try WidgetStore.clear()
            try shared.clear()
        }
        await WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        WidgetCenter.shared.reloadAllTimelines()
        defaults.removeObject(forKey: cacheKey)
        defaults.removeObject(forKey: historyCacheKey)
        tokenHistoryCache.clear()
        clearTokenHistory()
        history = nil
        historyUnavailable = false
        foregroundRefresh.reset()
        tokens = nil
        reading = nil
        renewedAt = nil
        connectionFailure = nil
        error = nil
        message = "Connection removed from this device."
    }
}

import Foundation
import Observation
import WidgetKit
import UIKit
import MobileAccessCore

/// Devin has no sign-in flow on iOS: the user pastes the session token the
/// Devin CLI or desktop app already holds (`windsurf_api_key` in
/// `~/.local/share/devin/credentials.toml`). The token is validated against
/// GetUserStatus before it is saved to the shared Keychain store.
@MainActor @Observable
final class DevinProbeModel {
    private let shared: SharedQuotaStore
    private var foregroundRefresh = ForegroundRefreshPolicy()
    private(set) var quietlyRefreshing = false
    var loading: Bool { busy && !quietlyRefreshing }
    private let fetchUsage: (@Sendable (Bool, TimeInterval) async throws -> QuotaReading)?
    private var work: Task<Void, Never>?
    private var generation = UUID()
    private var tokens: DevinTokens?
    private(set) var reading: QuotaReading?
    private(set) var signInCompletionID: UUID?
    private(set) var busy = false
    private(set) var message = "Connect Devin to see your usage."
    private(set) var error: String?
    private(set) var connectionFailure: SharedQuotaStore.Failure?
    let isDemo: Bool
    var connected: Bool { isDemo || tokens != nil }
    private let cacheKey = "mobileProbe.devinReading"

    init(shared: SharedQuotaStore = SharedQuotaStore(.devin), restore: Bool = true, isDemo: Bool = false,
         fetchUsage: (@Sendable (Bool, TimeInterval) async throws -> QuotaReading)? = nil) {
        self.isDemo = isDemo
        self.fetchUsage = fetchUsage
        self.shared = shared
        if isDemo {
            reading = DemoQuotaData.reading(.devin)
            message = "Sample usage. No account connected."
            return
        }
        guard restore else { return }
        do {
            tokens = try shared.load(DevinTokens.self)
            if tokens != nil {
                connectionFailure = shared.failure()
                message = "Connected. Your usage updates automatically."
                reading = shared.reading()
                if reading == nil, let data = UserDefaults.standard.data(forKey: cacheKey) {
                    reading = try? JSONDecoder().decode(QuotaReading.self, from: data)
                }
            }
        } catch { self.error = "Could not read this device’s saved connection." }
    }

    /// Validates a pasted session token, then saves it to the shared store.
    func connect(token pasted: String) {
        guard !isDemo else { return }
        guard !busy else { return }
        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        run { [self] in
            let candidate = DevinTokens(apiKey: trimmed)
            // Reject bad tokens up front so a typo never replaces a working session.
            _ = try await shared.devinReadingProbe(candidate)
            try Task.checkCancellation()
            try await shared.withLease { [shared] in
                try shared.saveCredentials(candidate)
            }
            foregroundRefresh.reset()
            tokens = candidate
            message = "Connected on this device. Checking quota…"
            try await fetch(forceRenewal: false)
            signInCompletionID = UUID()
        }
    }

    func refresh(forceRenewal: Bool = false) {
        if isDemo {
            reading = DemoQuotaData.reading(.devin)
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
        // A widget may have published a newer successful reading while the app was inactive.
        if let cached = shared.reading(), cached.fetchedAt > (reading?.fetchedAt ?? .distantPast) {
            reading = cached
            error = nil
            connectionFailure = shared.failure()
        }
        guard foregroundRefresh.beginAutomatic(at: .now, reading: reading) else { return }
        quietlyRefreshing = reading != nil
        run { [self] in try await fetch(forceRenewal: false, minimumAge: 30) }
    }

    private func fetch(forceRenewal: Bool, minimumAge: TimeInterval = 0) async throws {
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Refresh Devin quota") { [weak self] in
            Task { @MainActor in self?.work?.cancel() }
        }
        defer { if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) } }

        message = "Updating quota…"
        let value: QuotaReading
        if let fetchUsage {
            value = try await fetchUsage(forceRenewal, minimumAge)
        } else {
            value = try await shared.fetch(source: "app", forceRenewal: forceRenewal, minimumAge: minimumAge)
        }
        try Task.checkCancellation()
        tokens = try shared.load(DevinTokens.self)
        connectionFailure = nil
        reading = value
        UserDefaults.standard.set(try JSONEncoder().encode(value), forKey: cacheKey)
        WidgetCenter.shared.reloadAllTimelines()
        message = "Usage updated."
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
                    ?? (error as? DevinAccessError)?.errorDescription
                    ?? "The request did not complete. Check your connection and try again."
                if self.tokens != nil {
                    self.connectionFailure = SharedQuotaStore.Failure.classify(error)
                    self.message = "Couldn’t update usage. Your last reading is still shown."
                } else {
                    self.message = "That token was not accepted. Check it and try again."
                }
            }
            guard let self, self.generation == id else { return }
            self.quietlyRefreshing = false
            self.busy = false
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
        cancel()
        busy = true
        defer { busy = false }
        await pending?.value
        try await clearConnection()
        foregroundRefresh.reset()
        signInCompletionID = nil
        message = "Connect Devin to see your usage."
    }
    private func clearConnection() async throws {
        try await shared.withLease { [shared] in
            try shared.clear()
        }
        WidgetCenter.shared.reloadAllTimelines()
        UserDefaults.standard.removeObject(forKey: cacheKey)
        foregroundRefresh.reset()
        tokens = nil
        reading = nil
        connectionFailure = nil
        error = nil
        message = "Connection removed from this device."
    }
}

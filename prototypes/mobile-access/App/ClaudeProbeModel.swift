import Foundation
import Observation
import WidgetKit
import UIKit
import MobileAccessCore

@MainActor @Observable
final class ClaudeProbeModel {
    private let shared = SharedQuotaStore(.claude)
    private var lastAutomaticRefresh: Date?
    private let api = ClaudeAPI()
    private var work: Task<Void, Never>?
    private var generation = UUID()
    private var tokens: ClaudeTokens?
    private(set) var challenge: ClaudeChallenge?
    private(set) var reading: QuotaReading?
    private(set) var busy = false
    private(set) var message = "Connect Claude to see your usage."
    private(set) var error: String?
    private(set) var renewedAt: Date?
    var connected: Bool { tokens != nil }
    private let cacheKey = "mobileProbe.claudeReading"

    init() {
        do {
            tokens = try shared.load(ClaudeTokens.self) ?? ClaudeTokenStore.load()
            if tokens != nil {
                message = "Connected. Your usage updates automatically."
                reading = shared.reading()
                if reading == nil, let data = UserDefaults.standard.data(forKey: cacheKey) {
                    reading = try? JSONDecoder().decode(QuotaReading.self, from: data)
                }
            }
        } catch { self.error = "Could not read this device’s saved connection." }
    }
    func connect() {
        guard !busy, !connected else { return }
        do {
            challenge = try ClaudeChallenge()
            error = nil
            message = "Sign in with Claude in Safari, then paste the authorization code here."
        } catch { self.error = "Could not prepare sign-in. Try again." }
    }
    func finishSignIn(_ pasted: String) {
        guard !busy, !connected, let pending = challenge else { return }
        run { [self] in
            let newTokens = try await api.exchange(pasted, challenge: pending)
            try Task.checkCancellation()
            try await shared.withLease { [shared] in
                        try shared.saveCredentials(newTokens)
                        try ClaudeTokenStore.clear()
                    }
            tokens = newTokens
            challenge = nil
            message = "Signed in on this device. Checking quota…"
            try await fetch(forceRenewal: false)
        }
    }
    func refresh(forceRenewal: Bool = false) {
        guard !busy, connected else { return }
        run { [self] in try await fetch(forceRenewal: forceRenewal) }
    }
    func refreshOnOpen() {
        guard !busy, connected else { return }
        if let lastAutomaticRefresh, Date.now.timeIntervalSince(lastAutomaticRefresh) < 15 { return }
        lastAutomaticRefresh = .now
        refresh()
    }
    private func fetch(forceRenewal: Bool) async throws {
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Refresh allowance") { [weak self] in
            Task { @MainActor in self?.work?.cancel() }
        }
        defer { if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) } }

        // Migrate once under the same lease used by widget renewal. Never overwrite newer shared credentials.
        try await shared.withLease { [shared] in
            if try shared.load(ClaudeTokens.self) == nil, let old = try ClaudeTokenStore.load() {
                try shared.saveCredentials(old)
            }
            try ClaudeTokenStore.clear()
        }
        message = "Updating allowance…"
        let value = try await shared.fetch(source: "app", forceRenewal: forceRenewal)
        try Task.checkCancellation()
        tokens = try shared.load(ClaudeTokens.self)
        reading = value
        UserDefaults.standard.set(try JSONEncoder().encode(value), forKey: cacheKey)
        if forceRenewal { renewedAt = .now }
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
                self.error = (error as? ClaudeAccessError)?.errorDescription
                    ?? (error as? AccessError)?.errorDescription
                    ?? "The request did not complete. Check your connection and try again."
                self.message = "Couldn’t update usage. Your last reading is still shown."
            }
            guard let self, self.generation == id else { return }
            self.busy = false
            self.challenge = nil
            self.work = nil
        }
    }
    func cancel() {
        generation = UUID()
        work?.cancel()
        work = nil
        busy = false
        challenge = nil
        message = "Check cancelled."
    }
    func disconnect() {
        guard !busy else { return }
        run { [self] in
            try await shared.withLease { [shared] in
                try ClaudeTokenStore.clear()
                try shared.clear()
            }
            WidgetCenter.shared.reloadAllTimelines()
            UserDefaults.standard.removeObject(forKey: cacheKey)
            tokens = nil
            reading = nil
            renewedAt = nil
            error = nil
            message = "Connection removed from this device."
        }
    }
}

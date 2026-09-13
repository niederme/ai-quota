import Foundation
import Observation
import WidgetKit
import UIKit
import MobileAccessCore

@MainActor @Observable
final class ProbeModel {
    private let shared = SharedQuotaStore(.codex)
    private var lastAutomaticRefresh: Date?
    private let api = CodexAPI()
    private var work: Task<Void, Never>?
    private var generation = UUID()
    private var tokens: CodexTokens?
    private(set) var challenge: DeviceChallenge?
    private(set) var reading: QuotaReading?
    private(set) var busy = false
    private(set) var message = "Connect Codex to see your usage."
    private(set) var error: String?
    private(set) var renewedAt: Date?
    var connected: Bool { tokens != nil }
    private let cacheKey = "mobileProbe.codexReading"

    init() {
        do {
            tokens = try shared.load(CodexTokens.self) ?? TokenStore.load()
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
        guard !busy else { return }
        run { [self] in
            let newChallenge = try await api.requestChallenge()
            try Task.checkCancellation()
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
                    tokens = newTokens
                    challenge = nil
                    message = "Signed in on this device. Checking quota…"
                    try await fetch(forceRenewal: false)
                    return
                }
            }
            throw AccessError.expired
        }
    }
    func refresh(forceRenewal: Bool = false) {
        guard !busy, connected else { return }
        run { [self] in try await fetch(forceRenewal: forceRenewal) }
    }
    func refreshAndWait() async {
        refresh()
        await work?.value
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
            if try shared.load(CodexTokens.self) == nil, let old = try TokenStore.load() {
                try shared.saveCredentials(old)
            }
            try TokenStore.clear()
            try WidgetStore.clearAccess()
        }
        message = "Updating allowance…"
        let value = try await shared.fetch(source: "app", forceRenewal: forceRenewal)
        try Task.checkCancellation()
        tokens = try shared.load(CodexTokens.self)
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
                self.error = (error as? AccessError)?.errorDescription
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
                try TokenStore.clear()
                try WidgetStore.clearAccess()
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

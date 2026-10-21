import BackgroundTasks
import Foundation
import WidgetKit
import MobileAccessCore

/// Opportunistic work only: earliestBeginDate never promises a polling cadence.
@MainActor final class MobileBackgroundRefresh {
    static let shared = MobileBackgroundRefresh()
    static let identifier = "com.niederme.AIQuota.refresh"
    private var activeRun: BackgroundRefreshRun?
    private var activeAccountRun: Task<Void, Never>?

    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: .main) { task in
            MainActor.assumeIsolated {
                guard let task = task as? BGAppRefreshTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                Self.shared.handle(task)
            }
        }
    }

    private func connectedProfiles() -> [AccountProfile] {
        guard !DemoQuotaData.isEnabled else { return [] }
        return AccountRegistry.all().filter { profile in
            let store = SharedQuotaStore(profile.service, namespace: profile.id)
            switch profile.service {
            case .codex: return (try? store.load(CodexTokens.self)) != nil
            case .claude: return (try? store.load(ClaudeTokens.self)) != nil
            }
        }
    }

    func scheduleNext() {
        // Replace our own request only; never alter another background task.
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.identifier)
        let profiles = connectedProfiles()
        guard !profiles.isEmpty else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
        request.earliestBeginDate = Date.now.addingTimeInterval(30 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            for profile in profiles { SharedQuotaStore(profile.service, namespace: profile.id).log("background", "scheduled") }
        }
        catch { SharedQuotaStore(.codex).log("background", "schedule_unavailable") }
    }

    private func handle(_ task: BGAppRefreshTask) {
        let profiles = connectedProfiles()
        for profile in profiles { SharedQuotaStore(profile.service, namespace: profile.id).log("background", "started") }
        activeAccountRun?.cancel()
        let work = Task { @MainActor in
            scheduleNext()
            let success = await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
                for profile in profiles {
                    group.addTask {
                        do {
                            try Task.checkCancellation()
                            _ = try await SharedQuotaStore(profile.service, namespace: profile.id)
                                .fetch(source: "background", minimumAge: 60)
                            return true
                        } catch { return false }
                    }
                }
                var allSucceeded = true
                for await result in group { allSucceeded = allSucceeded && result }
                return allSucceeded
            }
            guard !Task.isCancelled else { return }
            WidgetCenter.shared.reloadAllTimelines()
            for profile in profiles {
                let store = SharedQuotaStore(profile.service, namespace: profile.id)
                store.log("background", success ? "completed" : "failed_or_expired", reading: store.reading())
            }
            task.expirationHandler = nil
            task.setTaskCompleted(success: success)
            activeAccountRun = nil
        }
        activeAccountRun = work
        task.expirationHandler = {
            Task { @MainActor in
                self.activeAccountRun?.cancel()
                self.activeAccountRun = nil
                task.setTaskCompleted(success: false)
            }
        }
    }
}

/// Small injectable lifecycle keeps expiration/rescheduling testable without system scheduling.
@MainActor final class BackgroundRefreshRun {
    private let services: [QuotaService]
    private let reschedule: () -> Void
    private let refresh: @Sendable (QuotaService) async throws -> Void
    private let reload: () -> Void
    private let complete: (Bool) -> Void
    private var work: Task<Void, Never>?
    private var completed = false
    private var started = false

    init(services: [QuotaService], reschedule: @escaping () -> Void,
         refresh: @escaping @Sendable (QuotaService) async throws -> Void,
         reload: @escaping () -> Void, complete: @escaping (Bool) -> Void) {
        self.services = services; self.reschedule = reschedule; self.refresh = refresh
        self.reload = reload; self.complete = complete
    }
    func start() {
        guard !started, !completed else { return }
        started = true
        reschedule()
        work = Task {
            let success = await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
                for service in services {
                    group.addTask { [refresh] in
                        do { try Task.checkCancellation(); try await refresh(service); return true }
                        catch { return false }
                    }
                }
                var allSucceeded = true
                for await result in group { allSucceeded = allSucceeded && result }
                return allSucceeded
            }
            guard !completed, !Task.isCancelled else { return }
            // Failures also update the widget's saved-reading/reconnect presentation.
            if !services.isEmpty { reload() }
            finish(success)
        }
    }
    func expire() {
        guard !completed else { return }
        work?.cancel()
        finish(false)
    }
    private func finish(_ success: Bool) {
        guard !completed else { return }
        completed = true
        work = nil
        complete(success)
    }
}

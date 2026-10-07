import BackgroundTasks
import Foundation
import WidgetKit
import MobileAccessCore

/// Opportunistic work only: earliestBeginDate never promises a polling cadence.
@MainActor final class MobileBackgroundRefresh {
    static let shared = MobileBackgroundRefresh()
    static let identifier = "com.niederme.AIQuota.refresh"
    private var activeRun: BackgroundRefreshRun?

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

    private func connectedServices() -> [QuotaService] {
        guard !DemoQuotaData.isEnabled else { return [] }
        return QuotaService.allCases.filter { service in
            let store = SharedQuotaStore(service)
            switch service {
            case .codex: return (try? store.load(CodexTokens.self)) != nil
            case .claude: return (try? store.load(ClaudeTokens.self)) != nil
            }
        }
    }

    func scheduleNext() {
        // Replace our own request only; never alter another background task.
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.identifier)
        guard !connectedServices().isEmpty else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
        request.earliestBeginDate = Date.now.addingTimeInterval(30 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            for service in connectedServices() { SharedQuotaStore(service).log("background", "scheduled") }
        }
        catch { SharedQuotaStore(.codex).log("background", "schedule_unavailable") }
    }

    private func handle(_ task: BGAppRefreshTask) {
        let services = connectedServices()
        for service in services { SharedQuotaStore(service).log("background", "started") }
        let run = BackgroundRefreshRun(services: services, reschedule: { self.scheduleNext() },
            refresh: { service in
                _ = try await SharedQuotaStore(service).fetch(source: "background", minimumAge: 60)
            }, reload: { WidgetCenter.shared.reloadAllTimelines() }, complete: { success in
                task.expirationHandler = nil
                for service in services {
                    let store = SharedQuotaStore(service)
                    store.log("background", success ? "completed" : "failed_or_expired", reading: store.reading())
                }
                task.setTaskCompleted(success: success)
                self.activeRun = nil
            })
        activeRun = run
        task.expirationHandler = { Task { @MainActor in run.expire() } }
        run.start()
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

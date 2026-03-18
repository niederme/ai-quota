import Foundation
import AIQuotaKit
import WidgetKit
import Combine

@MainActor
@Observable
final class QuotaViewModel {
    var usage: CodexUsage?
    var isLoading = false
    var error: NetworkError?
    var settings: AppSettings = SharedDefaults.loadSettings()

    // Stored property so @Observable tracks changes correctly.
    // Kept in sync with authManager.$isAuthenticated via Combine.
    private(set) var isAuthenticated: Bool = false

    let authManager: AuthManager
    private let client: OpenAIClient
    private var refreshTask: Task<Void, Never>?
    private var authCancellable: AnyCancellable?

    init() {
        let auth = AuthManager()
        self.authManager = auth
        self.client = OpenAIClient(authManager: auth)
        self.isAuthenticated = auth.isAuthenticated
        usage = SharedDefaults.loadCachedUsage()

        // Bridge ObservableObject → @Observable so the view re-renders on auth changes
        authCancellable = auth.$isAuthenticated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.isAuthenticated = value
            }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let result = try await client.fetchUsage()
            usage = result
            SharedDefaults.saveUsage(result)
            WidgetCenter.shared.reloadTimelines(ofKind: "AIQuotaWidget")
            if settings.notificationsEnabled {
                await NotificationManager.shared.evaluate(current: result)
            }
        } catch let e as NetworkError {
            error = e
        } catch {
            self.error = .networkUnavailable
        }
    }

    func startAutoRefresh() {
        if settings.notificationsEnabled {
            Task { await NotificationManager.shared.requestPermission() }
        }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(settings.refreshInterval))
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func signIn() async {
        do {
            try await authManager.signIn()
            await refresh()
            startAutoRefresh()
        } catch {
            self.error = .notAuthenticated
        }
    }

    func signOut() {
        stopAutoRefresh()
        authManager.signOut()
        usage = nil
    }

    func saveSettings() {
        SharedDefaults.saveSettings(settings)
        if isAuthenticated { startAutoRefresh() }
    }

    // MARK: - Notification testing

    /// Fires all four notification types immediately, ignoring threshold state.
    /// For development/testing only.
    func testNotifications() async {
        await NotificationManager.shared.requestPermission()
        await NotificationManager.shared.fireTestNotifications()
    }
}

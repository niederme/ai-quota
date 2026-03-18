import Foundation
import AIQuotaKit
import WidgetKit

@MainActor
@Observable
final class QuotaViewModel {
    var usage: CodexUsage?
    var isLoading = false
    var error: NetworkError?
    var settings: AppSettings = SharedDefaults.loadSettings()

    var isAuthenticated: Bool { authManager.isAuthenticated }

    let authManager: AuthManager
    private let client: OpenAIClient
    private var refreshTask: Task<Void, Never>?

    init() {
        let auth = AuthManager()
        self.authManager = auth
        self.client = OpenAIClient(authManager: auth)
        usage = SharedDefaults.loadCachedUsage()
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
        } catch let e as NetworkError {
            error = e
        } catch {
            self.error = .networkUnavailable
        }
    }

    func startAutoRefresh() {
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
}

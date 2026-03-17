import Foundation
import WebKit
import AppKit

// MARK: - Session API response
// GET https://chatgpt.com/api/auth/session → { "accessToken": "eyJ...", "expires": "..." }

private struct SessionResponse: Decodable {
    let accessToken: String
    let expires: String?
}

// MARK: - AuthManager

/// Authentication flow:
/// 1. Show chatgpt.com in a WKWebView sheet (user logs in normally)
/// 2. Monitor WKHTTPCookieStore for __Secure-next-auth.session-token
/// 3. Once captured, exchange session token → Bearer JWT via /api/auth/session
/// 4. Cache Bearer JWT (expires ~24h); refresh cheaply via /api/auth/session
/// 5. Session token itself persists in Keychain (valid for weeks)

@MainActor
public final class AuthManager: NSObject, ObservableObject {
    @Published public var isAuthenticated = false

    private let baseURL = URL(string: "https://chatgpt.com")!
    private let sessionEndpoint = URL(string: "https://chatgpt.com/api/auth/session")!
    private let loginURL = URL(string: "https://chatgpt.com")!

    // In-memory token cache
    private var cachedAccessToken: String?
    private var tokenExpiresAt: Date?

    private weak var loginWindowController: LoginWindowController?

    public override init() {
        super.init()
        loadSessionFromKeychain()
    }

    // MARK: - Access Token (called before every API request)

    public var accessToken: String {
        get async throws {
            // Return cached token if still valid (with 60s buffer)
            if let token = cachedAccessToken,
               let exp = tokenExpiresAt,
               exp.addingTimeInterval(-60) > .now {
                return token
            }
            // Refresh from session endpoint using stored session token
            guard KeychainStore.load(forKey: "sessionToken") != nil else {
                throw NetworkError.notAuthenticated
            }
            return try await refreshAccessToken()
        }
    }

    // MARK: - Sign In (WKWebView sheet)

    public func signIn() async throws {
        // Show login window and wait for session token
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let controller = LoginWindowController(baseURL: loginURL) { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch result {
                    case .success(let sessionToken):
                        KeychainStore.save(sessionToken, forKey: "sessionToken")
                        do {
                            _ = try await self.refreshAccessToken()
                            self.isAuthenticated = true
                            continuation.resume()
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
            self.loginWindowController = controller
            controller.show()
        }
    }

    // MARK: - Sign Out

    public func signOut() {
        cachedAccessToken = nil
        tokenExpiresAt = nil
        isAuthenticated = false
        KeychainStore.deleteAll()
        // Also clear WKWebView cookies so next login starts fresh
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) {}
    }

    // MARK: - Token Refresh

    @discardableResult
    private func refreshAccessToken() async throws -> String {
        guard let sessionToken = KeychainStore.load(forKey: "sessionToken") else {
            isAuthenticated = false
            throw NetworkError.notAuthenticated
        }

        var req = URLRequest(url: sessionEndpoint)
        req.setValue("__Secure-next-auth.session-token=\(sessionToken)", forHTTPHeaderField: "Cookie")
        req.setValue("https://chatgpt.com", forHTTPHeaderField: "Referer")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                isAuthenticated = false
                KeychainStore.deleteAll()
                throw NetworkError.refreshFailed
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let session = try decoder.decode(SessionResponse.self, from: data)
            cachedAccessToken = session.accessToken
            // JWT expires in ~24h; parse from expires field or default
            tokenExpiresAt = parseExpiry(from: session.expires) ?? Date.now.addingTimeInterval(86400)
            isAuthenticated = true
            return session.accessToken
        } catch let e as NetworkError {
            throw e
        } catch {
            throw NetworkError.refreshFailed
        }
    }

    private func parseExpiry(from string: String?) -> Date? {
        guard let string else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: string)
    }

    // MARK: - Keychain bootstrap

    private func loadSessionFromKeychain() {
        guard KeychainStore.load(forKey: "sessionToken") != nil else { return }
        isAuthenticated = true // will verify on first token fetch
    }
}

// MARK: - Login Window Controller

/// Presents a WKWebView pointing at chatgpt.com and watches for the session cookie.
@MainActor
final class LoginWindowController: NSObject, WKNavigationDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var cookieObserver: CookieObserver?
    private let onComplete: (Result<String, Error>) -> Void
    private let targetURL: URL
    private var hasCompleted = false

    init(baseURL: URL, onComplete: @escaping (Result<String, Error>) -> Void) {
        self.targetURL = baseURL
        self.onComplete = onComplete
    }

    func show() {
        let config = WKWebViewConfiguration()
        // Use default data store so existing cookies are visible
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 520, height: 680), configuration: config)
        webView.navigationDelegate = self
        self.webView = webView

        // Observe cookie store for session token
        let observer = CookieObserver { [weak self] sessionToken in
            self?.complete(with: .success(sessionToken))
        }
        config.websiteDataStore.httpCookieStore.add(observer)
        self.cookieObserver = observer

        let win = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 520, height: 680),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Sign in to ChatGPT"
        win.contentView = webView
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self
        self.window = win

        webView.load(URLRequest(url: targetURL))
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func complete(with result: Result<String, Error>) {
        guard !hasCompleted else { return }
        hasCompleted = true
        window?.close()
        window = nil
        webView = nil
        onComplete(result)
    }
}

extension LoginWindowController: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            if !hasCompleted {
                complete(with: .failure(NetworkError.notAuthenticated))
            }
        }
    }
}

// MARK: - Cookie Observer

private final class CookieObserver: NSObject, WKHTTPCookieStoreObserver, @unchecked Sendable {
    private let onSessionToken: @Sendable (String) -> Void
    private var hasFound = false

    init(onSessionToken: @Sendable @escaping (String) -> Void) {
        self.onSessionToken = onSessionToken
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        guard !hasFound else { return }
        cookieStore.getAllCookies { [weak self] cookies in
            guard let self, !self.hasFound else { return }
            if let sessionCookie = cookies.first(where: {
                $0.name == "__Secure-next-auth.session-token" && $0.domain.contains("chatgpt.com")
            }) {
                self.hasFound = true
                DispatchQueue.main.async {
                    self.onSessionToken(sessionCookie.value)
                }
            }
        }
    }
}

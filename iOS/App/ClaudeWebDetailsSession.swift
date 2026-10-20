import Foundation
import Observation
import SwiftUI
import WebKit
import MobileAccessCore

/// Claude's detailed Enterprise usage is available to its signed-in web app,
/// not to the OAuth usage token. WebKit owns this app's Claude session; AIQuota
/// only receives the usage responses from same-origin requests.
@MainActor @Observable
final class ClaudeWebDetailsSession: NSObject, WKNavigationDelegate, WKUIDelegate {
    enum State: Equatable { case idle, checking, signInRequired, accountMismatch, organizationReconnectRequired, ready, unavailable }

    private(set) var state: State = .idle
    private(set) var spend: ClaudeSpendHistory?
    private(set) var skills: ClaudeEnterpriseSkillsResponse?
    private(set) var spendUnavailable = false
    private(set) var skillsUnavailable = false
    private(set) var detailsLoading = false
    private(set) var popup: WKWebView?
    private var expectedOrganizationID: String?
    private var isProbing = false
    private var pendingProbe = false
    private var generation = UUID()
    private var savedClaudeCookies: [HTTPCookie]?
    @ObservationIgnored let webView: WKWebView

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    func start(organization: ClaudeOrganizationLookup) {
        generation = UUID()
        webView.stopLoading()
        spend = nil
        skills = nil
        spendUnavailable = false
        skillsUnavailable = false
        detailsLoading = false
        switch organization {
        case .verified(let id): expectedOrganizationID = id
        case .reconnectRequired:
            expectedOrganizationID = nil
            state = .organizationReconnectRequired
            return
        case .temporarilyUnavailable:
            expectedOrganizationID = nil
            state = .unavailable
            return
        }
        state = .checking
        webView.load(URLRequest(url: URL(string: "https://claude.ai/settings/usage")!))
    }

    /// Begin a reversible change to the app-owned Claude web session. The
    /// existing OAuth allowance is untouched throughout this transaction.
    func beginReconnect(loadPage: Bool = true) async {
        generation = UUID()
        webView.stopLoading()
        spend = nil
        skills = nil
        spendUnavailable = false
        skillsUnavailable = false
        detailsLoading = false
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
        let claudeCookies = cookies.filter(Self.isAccountCookie)
        savedClaudeCookies = claudeCookies
        for cookie in claudeCookies {
            await withCheckedContinuation { continuation in
                store.delete(cookie) { continuation.resume() }
            }
        }
        state = .checking
        if loadPage {
            webView.load(URLRequest(url: URL(string: "https://claude.ai/settings/usage")!))
        }
    }

    /// Dismissing login restores the previous web account, if any.
    func cancelReconnect() async {
        guard let cookies = savedClaudeCookies else { return }
        savedClaudeCookies = nil
        generation = UUID()
        webView.stopLoading()
        let store = WKWebsiteDataStore.default().httpCookieStore
        let currentCookies = await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
        for cookie in currentCookies where Self.isAccountCookie(cookie) {
            await withCheckedContinuation { continuation in
                store.delete(cookie) { continuation.resume() }
            }
        }
        for cookie in cookies {
            await withCheckedContinuation { continuation in
                store.setCookie(cookie) { continuation.resume() }
            }
        }
        state = .idle
    }

    func refresh() {
        guard expectedOrganizationID != nil else { return }
        generation = UUID()
        webView.stopLoading()
        state = .checking
        webView.load(URLRequest(url: URL(string: "https://claude.ai/settings/usage")!))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        guard webView.url?.host == "claude.ai" else {
            state = .signInRequired
            return
        }
        Task { await probe() }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard webView === self.webView, (error as NSError).code != NSURLErrorCancelled else { return }
        state = .unavailable
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        let child = WKWebView(frame: .zero, configuration: configuration)
        child.uiDelegate = self
        popup = child
        return child
    }

    func webViewDidClose(_ webView: WKWebView) {
        if webView === popup { popup = nil; Task { await probe() } }
    }

    private struct WebOrganization: Decodable {
        let uuid: String
        let capabilities: [String]?
    }

    private struct WebResponse: Decodable {
        let status: Int
        let body: String
        let contentType: String
        let challenged: Bool
    }

    private func request(_ path: String) async throws -> Data {
        guard webView.url?.host == "claude.ai" else { throw ClaudeWebDetailError.notSignedIn }
        let value: String = try await withCheckedThrowingContinuation { continuation in
            webView.callAsyncJavaScript("""
                const response = await fetch(path, {
                    credentials: 'include', headers: {'Accept': 'application/json'}
                });
                const body = await response.text();
                return JSON.stringify({status: response.status, body,
                    contentType: response.headers.get('content-type') || '',
                    challenged: response.headers.get('cf-mitigated') === 'challenge' || body.includes('cf-chl-')});
            """, arguments: ["path": path], in: nil, in: .page) { result in
                switch result {
                case .success(let value):
                    if let text = value as? String { continuation.resume(returning: text) }
                    else { continuation.resume(throwing: ClaudeWebDetailError.badResponse) }
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
        let response = try JSONDecoder().decode(WebResponse.self, from: Data(value.utf8))
        if let error = Self.responseError(status: response.status,
                                          contentType: response.contentType,
                                          challenged: response.challenged,
                                          startsWithMarkup: response.body.trimmingCharacters(in: .whitespaces).hasPrefix("<")) {
            throw error
        }
        return Data(response.body.utf8)
    }

    static func responseError(status: Int, contentType: String, challenged: Bool,
                              startsWithMarkup: Bool) -> ClaudeWebDetailError? {
        if challenged { return .challenge }
        if status != 200 { return .http(status) }
        if contentType.contains("text/html") || startsWithMarkup { return .notSignedIn }
        return nil
    }

    static func organizationProbeFailureState(_ error: Error) -> State {
        guard let error = error as? ClaudeWebDetailError else { return .unavailable }
        switch error {
        case .http(401), .http(403), .notSignedIn: return .signInRequired
        default: return .unavailable
        }
    }

    private func probe() async {
        guard !isProbing else { pendingProbe = true; return }
        guard let expectedOrganizationID else { return }
        guard webView.url?.host == "claude.ai" else { return }
        isProbing = true
        let requestID = UUID()
        generation = requestID
        defer {
            isProbing = false
            if pendingProbe {
                pendingProbe = false
                Task { await probe() }
            }
        }
        do {
            let organizations = try JSONDecoder().decode([WebOrganization].self,
                from: try await request("/api/organizations"))
            guard generation == requestID else { return }
            guard let matchingOrganization = organizations.first(where: {
                $0.uuid.caseInsensitiveCompare(expectedOrganizationID) == .orderedSame
            }) else {
                spend = nil
                skills = nil
                detailsLoading = false
                state = .accountMismatch
                return
            }
            detailsLoading = true
            state = .ready
            await loadDetails(organizationID: matchingOrganization.uuid, requestID: requestID)
            if generation == requestID {
                detailsLoading = false
                if state == .ready { savedClaudeCookies = nil }
            }
        } catch {
            guard generation == requestID else { return }
            detailsLoading = false
            state = Self.organizationProbeFailureState(error)
        }
    }

    private func loadDetails(organizationID: String, requestID: UUID) async {
        let calendar = Calendar(identifier: .gregorian)
        var utc = calendar
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date()
        let start = utc.date(from: utc.dateComponents([.year, .month], from: now)) ?? now
        let formatter = DateFormatter()
        formatter.calendar = utc
        formatter.timeZone = utc.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let startDate = formatter.string(from: start)
        let endDate = formatter.string(from: now)
        var query = URLComponents()
        query.queryItems = [
            .init(name: "start_date", value: startDate), .init(name: "end_date", value: endDate),
            .init(name: "group_by", value: "product_surface"), .init(name: "granularity", value: "daily")
        ]
        let base = "/api/organizations/\(organizationID)/usage"
        do {
            let data = try await request(base + "/spend?" + (query.percentEncodedQuery ?? ""))
            let value = try JSONDecoder().decode(ClaudeSpendHistory.self, from: data)
            if generation == requestID { spend = value; spendUnavailable = false }
        } catch {
            if generation == requestID { spend = nil; spendUnavailable = true }
            if let detailError = error as? ClaudeWebDetailError,
               case .http(401) = detailError, generation == requestID {
                state = .signInRequired
                return
            }
        }
        do {
            let path = base + "/skills?start_date=\(startDate)&end_date=\(endDate)"
            let value = try JSONDecoder().decode(ClaudeEnterpriseSkillsResponse.self, from: try await request(path))
            if generation == requestID { skills = value; skillsUnavailable = false }
        } catch {
            if generation == requestID { skills = nil; skillsUnavailable = true }
            if let detailError = error as? ClaudeWebDetailError,
               case .http(401) = detailError, generation == requestID { state = .signInRequired }
        }
    }

    static func clearSession() async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
        for cookie in cookies where isClaudeCookie(cookie) {
            await withCheckedContinuation { continuation in
                store.delete(cookie) { continuation.resume() }
            }
        }
    }

    private static func isClaudeCookie(_ cookie: HTTPCookie) -> Bool {
        cookie.domain == "claude.ai" || cookie.domain.hasSuffix(".claude.ai")
    }

    private static func isAccountCookie(_ cookie: HTTPCookie) -> Bool {
        guard isClaudeCookie(cookie) else { return false }
        return cookie.name == "sessionKey" || cookie.name == "lastActiveOrg"
            || cookie.name == "unified_session_manifest"
            || cookie.name.hasPrefix("__Secure-next-auth.session-token")
            || cookie.name.hasPrefix("next-auth.session-token")
    }
}

enum ClaudeWebDetailError: Error, Equatable {
    case notSignedIn, badResponse, challenge, http(Int)
}

struct ClaudeWebSurface: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ webView: WKWebView, context: Context) {}
}

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
    enum State: Equatable { case idle, checking, signInRequired, accountMismatch, ready, unavailable }

    private(set) var state: State = .idle
    private(set) var spend: ClaudeSpendHistory?
    private(set) var skills: ClaudeEnterpriseSkillsResponse?
    private(set) var spendUnavailable = false
    private(set) var skillsUnavailable = false
    private(set) var detailsLoading = false
    private(set) var popup: WKWebView?
    private var expectedOrganizationID: String?
    private var isProbing = false
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

    func start(expectedOrganizationID: String?) {
        guard let expectedOrganizationID, !expectedOrganizationID.isEmpty else {
            state = .unavailable
            return
        }
        self.expectedOrganizationID = expectedOrganizationID
        state = .checking
        webView.load(URLRequest(url: URL(string: "https://claude.ai/settings/usage")!))
    }

    /// Begin a reversible change to the app-owned Claude web session. The
    /// existing OAuth allowance is untouched throughout this transaction.
    func beginReconnect(loadPage: Bool = true) async {
        generation = UUID()
        webView.stopLoading()
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
        let claudeCookies = cookies.filter(Self.isClaudeCookie)
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
        let store = WKWebsiteDataStore.default().httpCookieStore
        for cookie in cookies {
            await withCheckedContinuation { continuation in
                store.setCookie(cookie) { continuation.resume() }
            }
        }
        generation = UUID()
        state = .idle
    }

    func refresh() {
        guard expectedOrganizationID != nil else { return }
        Task { await probe() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView else { return }
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
    }

    private func request(_ path: String) async throws -> Data {
        guard webView.url?.host == "claude.ai" else { throw ClaudeWebDetailError.notSignedIn }
        let value: String = try await withCheckedThrowingContinuation { continuation in
            webView.callAsyncJavaScript("""
                const response = await fetch(path, {
                    credentials: 'include', headers: {'Accept': 'application/json'}
                });
                return JSON.stringify({status: response.status, body: await response.text()});
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
        guard response.status == 200 else { throw ClaudeWebDetailError.http(response.status) }
        return Data(response.body.utf8)
    }

    private func probe() async {
        guard !isProbing, let expectedOrganizationID else { return }
        guard webView.url?.host == "claude.ai" else { return }
        isProbing = true
        let requestID = UUID()
        generation = requestID
        defer { isProbing = false }
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
            savedClaudeCookies = nil
            await loadDetails(organizationID: matchingOrganization.uuid, requestID: requestID)
            if generation == requestID { detailsLoading = false }
        } catch ClaudeWebDetailError.http(401) {
            detailsLoading = false
            state = .signInRequired
        } catch {
            detailsLoading = false
            state = .unavailable
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
        }
        do {
            let path = base + "/skills?start_date=\(startDate)&end_date=\(endDate)"
            let value = try JSONDecoder().decode(ClaudeEnterpriseSkillsResponse.self, from: try await request(path))
            if generation == requestID { skills = value; skillsUnavailable = false }
        } catch {
            if generation == requestID { skills = nil; skillsUnavailable = true }
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
}

private enum ClaudeWebDetailError: Error {
    case notSignedIn, badResponse, http(Int)
}

struct ClaudeWebSurface: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ webView: WKWebView, context: Context) {}
}

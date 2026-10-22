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
    enum State: Equatable { case idle, checking, awaitingSignIn, signInRequired, accountMismatch, organizationReconnectRequired, ready, unavailable }

    private(set) var state: State = .idle
    private(set) var spend: ClaudeSpendHistory?
    private(set) var skills: ClaudeEnterpriseSkillsResponse?
    private(set) var spendFetchedAt: Date?
    private(set) var skillsFetchedAt: Date?
    private(set) var spendUnavailable = false
    private(set) var skillsUnavailable = false
    private(set) var detailsLoading = false
    private(set) var requestedStartDate: String?
    private(set) var requestedEndDate: String?
    private(set) var popup: WKWebView?
    private var expectedOrganizationID: String?
    private var isProbing = false
    private var pendingProbe = false
    private var generation = UUID()
    private var loadingTimeout: Task<Void, Never>?
    var checkingTimeout: Duration = .seconds(20)
    private var savedClaudeCookies: [HTTPCookie]?
    #if DEBUG
    var testResponses: [String: Data]?
    func testProbe() async { await probe() }
    func testRequireSignIn() {
        guard state == .checking else { return }
        loadingTimeout?.cancel()
        state = .signInRequired
    }
    #endif
    @ObservationIgnored let webView: WKWebView

    init(profileID: String? = nil, websiteDataStore: WKWebsiteDataStore? = nil) {
        let configuration = WKWebViewConfiguration()
        // Keep the migrated first account's existing web sign-in. Additional
        // accounts get persistent, separate WebKit profiles so two users in
        // the same Enterprise organization cannot share detail cookies.
        if let websiteDataStore {
            configuration.websiteDataStore = websiteDataStore
        } else if let profileID, profileID != "live", let identifier = UUID(uuidString: profileID) {
            configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: identifier)
        } else {
            configuration.websiteDataStore = .default()
        }
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    func invalidate() {
        generation = UUID()
        webView.stopLoading()
        loadingTimeout?.cancel()
        savedClaudeCookies = nil
        expectedOrganizationID = nil
        spend = nil
        skills = nil
        spendFetchedAt = nil
        skillsFetchedAt = nil
        spendUnavailable = false
        skillsUnavailable = false
        detailsLoading = false
        requestedStartDate = nil
        requestedEndDate = nil
        popup = nil
        state = .idle
    }

    func start(organization: ClaudeOrganizationLookup, loadPage: Bool = true, reuseReady: Bool = true) {
        if case .verified(let id) = organization, reuseReady,
           expectedOrganizationID?.caseInsensitiveCompare(id) == .orderedSame,
           state == .ready { return }
        generation = UUID()
        webView.stopLoading()
        spend = nil
        skills = nil
        spendFetchedAt = nil
        skillsFetchedAt = nil
        spendUnavailable = false
        skillsUnavailable = false
        detailsLoading = false
        requestedStartDate = nil
        requestedEndDate = nil
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
        beginChecking()
        if loadPage { loadUsagePage() }
    }

    /// Begin a reversible change to the app-owned Claude web session. The
    /// existing OAuth allowance is untouched throughout this transaction.
    func beginReconnect(loadPage: Bool = true) async {
        guard savedClaudeCookies == nil else { return }
        generation = UUID()
        webView.stopLoading()
        loadingTimeout?.cancel()
        spend = nil
        skills = nil
        spendFetchedAt = nil
        skillsFetchedAt = nil
        spendUnavailable = false
        skillsUnavailable = false
        detailsLoading = false
        requestedStartDate = nil
        requestedEndDate = nil
        let store = webView.configuration.websiteDataStore.httpCookieStore
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
        state = .awaitingSignIn
        if loadPage {
            loadUsagePage()
        }
    }

    /// Dismissing login restores the previous web account, if any.
    func cancelReconnect() async {
        guard let cookies = savedClaudeCookies else { return }
        savedClaudeCookies = nil
        generation = UUID()
        webView.stopLoading()
        loadingTimeout?.cancel()
        let store = webView.configuration.websiteDataStore.httpCookieStore
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
        beginChecking()
        loadUsagePage()
    }

    private func loadUsagePage() {
        #if DEBUG
        if testResponses != nil { return }
        #endif
        webView.load(URLRequest(url: URL(string: "https://claude.ai/settings/usage")!))
    }

    private func beginChecking() {
        state = .checking
        loadingTimeout?.cancel()
        let id = generation
        let timeout = checkingTimeout
        loadingTimeout = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self, self.generation == id,
                  self.state == .checking else { return }
            self.detailsLoading = false
            self.state = .unavailable
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === popup {
            if webView.url?.host == "claude.ai" {
                popup = nil
                refresh()
            }
            return
        }
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

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard webView === self.webView, (error as NSError).code != NSURLErrorCancelled else { return }
        state = .unavailable
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView else { return }
        state = .unavailable
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        let child = WKWebView(frame: .zero, configuration: configuration)
        child.uiDelegate = self
        child.navigationDelegate = self
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
        #if DEBUG
        if let testResponses {
            let key = path == "/api/organizations" ? "organizations"
                : path.contains("/skills?") ? "skills" : "spend"
            guard let data = testResponses[key] else { throw ClaudeWebDetailError.badResponse }
            return data
        }
        #endif
        guard webView.url?.host == "claude.ai" else { throw ClaudeWebDetailError.notSignedIn }
        let value: String = try await withCheckedThrowingContinuation { continuation in
            let completion = ClaudeWebRequestCompletion(continuation)
            completion.timeoutTask = Task {
                try? await Task.sleep(for: .seconds(14))
                guard !Task.isCancelled else { return }
                completion.finish(.failure(ClaudeWebDetailError.timeout))
            }
            webView.callAsyncJavaScript("""
                const controller = new AbortController();
                const timeout = setTimeout(() => controller.abort(), 10000);
                try {
                    const response = await fetch(path, {
                        credentials: 'include', headers: {'Accept': 'application/json'},
                        signal: controller.signal
                    });
                    const body = await response.text();
                    return JSON.stringify({status: response.status, body,
                        contentType: response.headers.get('content-type') || '',
                        challenged: response.headers.get('cf-mitigated') === 'challenge' || body.includes('cf-chl-')});
                } finally { clearTimeout(timeout); }
            """, arguments: ["path": path], in: nil, in: .page) { result in
                switch result {
                case .success(let value):
                    if let text = value as? String { completion.finish(.success(text)) }
                    else { completion.finish(.failure(ClaudeWebDetailError.badResponse)) }
                case .failure(let error): completion.finish(.failure(error))
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
        #if DEBUG
        if testResponses == nil {
            guard webView.url?.host == "claude.ai" else { return }
        }
        #else
        guard webView.url?.host == "claude.ai" else { return }
        #endif
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
            acceptVerifiedOrganization(matchingOrganization.uuid)
            await loadDetails(organizationID: matchingOrganization.uuid, requestID: requestID)
            if generation == requestID {
                detailsLoading = false
            }
        } catch {
            guard generation == requestID else { return }
            detailsLoading = false
            state = Self.organizationProbeFailureState(error)
        }
    }

    /// Commit the web session before publishing ready. Auto-dismiss of the
    /// sign-in sheet must never restore the previous cookies after this point.
    func acceptVerifiedOrganization(_ organizationID: String) {
        guard let expectedOrganizationID,
              expectedOrganizationID.caseInsensitiveCompare(organizationID) == .orderedSame else { return }
        savedClaudeCookies = nil
        loadingTimeout?.cancel()
        detailsLoading = true
        state = .ready
    }

    private func loadDetails(organizationID: String, requestID: UUID) async {
        var reportingCalendar = Calendar(identifier: .gregorian)
        reportingCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date()
        let start = reportingCalendar.dateInterval(of: .month, for: now)?.start ?? now
        let formatter = DateFormatter()
        formatter.calendar = reportingCalendar
        formatter.timeZone = reportingCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let startDate = formatter.string(from: start)
        let endDate = formatter.string(from: now)
        requestedStartDate = startDate
        requestedEndDate = endDate
        var query = URLComponents()
        query.queryItems = [
            .init(name: "start_date", value: startDate), .init(name: "end_date", value: endDate),
            .init(name: "group_by", value: "product_surface"), .init(name: "granularity", value: "daily")
        ]
        let base = "/api/organizations/\(organizationID)/usage"
        do {
            let data = try await request(base + "/spend?" + (query.percentEncodedQuery ?? ""))
            let value = try JSONDecoder().decode(ClaudeSpendHistory.self, from: data)
            if generation == requestID { spend = value; spendFetchedAt = .now; spendUnavailable = false }
        } catch {
            if generation == requestID { spend = nil; spendUnavailable = true }
            if Self.detailRequiresSignIn(error), generation == requestID {
                state = .signInRequired
                return
            }
        }
        do {
            let path = base + "/skills?start_date=\(startDate)&end_date=\(endDate)"
            let value = try JSONDecoder().decode(ClaudeEnterpriseSkillsResponse.self, from: try await request(path))
            if generation == requestID { skills = value; skillsFetchedAt = .now; skillsUnavailable = false }
        } catch {
            if generation == requestID { skills = nil; skillsUnavailable = true }
            if Self.detailRequiresSignIn(error), generation == requestID { state = .signInRequired }
        }
    }

    static func detailRequiresSignIn(_ error: Error) -> Bool {
        guard let error = error as? ClaudeWebDetailError else { return false }
        switch error {
        case .http(401), .notSignedIn: return true
        default: return false
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

    func clearProfileSession() async {
        let store = webView.configuration.websiteDataStore
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
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
    case notSignedIn, badResponse, challenge, timeout, http(Int)
}

@MainActor private final class ClaudeWebRequestCompletion {
    private var continuation: CheckedContinuation<String, Error>?
    var timeoutTask: Task<Void, Never>?

    init(_ continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }

    func finish(_ result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        continuation.resume(with: result)
    }
}

struct ClaudeWebSurface: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ webView: WKWebView, context: Context) {}
}

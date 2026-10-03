import SwiftUI
import MobileAccessCore

@MainActor @Observable
final class CodexResetNotice {
    static let dismissalKey = "codexResetNotice.dismissedID"
    static let website = URL(string: "https://codex-resets.com/")!
    // Fixed sample shown independently of the live tracker and its expiry rules.
    static let demoAnnouncement: CodexResetAnnouncement = {
        let data = Data("""
        {"id":"demo-codex-reset","status":"scheduled","reset_type":"regular",
         "announced_at":"2026-01-01T12:00:00Z","scheduled_for":"2026-01-01T18:00:00Z",
         "source":{"type":"demo","author":null,"url":null}}
        """.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode(CodexResetAnnouncement.self, from: data)
    }()
    private(set) var status: CodexResetStatus?
    private var checkedAt = Date.now
    private var nextFetch = Date.distantPast
    private(set) var fetching = false
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.urlCredentialStorage = nil
            self.session = URLSession(configuration: configuration)
        }
    }

    func refresh(at now: Date = .now) async {
        checkedAt = now
        guard !fetching, now >= nextFetch else { return }
        fetching = true
        nextFetch = now.addingTimeInterval(15 * 60)
        defer { fetching = false }
        do {
            // Public data only. Never send provider credentials or account details.
            var request = URLRequest(url: URL(string: "https://codex-resets.com/api/v1/status")!,
                                     cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpShouldHandleCookies = false
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { status = nil; return }
            if response.statusCode == 429,
               let retry = response.value(forHTTPHeaderField: "Retry-After"),
               let seconds = TimeInterval(retry), seconds.isFinite, seconds > 0 {
                nextFetch = now.addingTimeInterval(max(15 * 60, seconds))
            }
            guard response.statusCode == 200 else { status = nil; return }
            let decoded = try CodexResetStatus.decode(data)
            try Task.checkCancellation()
            status = decoded
        } catch {
            // An unavailable tracker is not an account error. Hide quietly.
            status = nil
            if Task.isCancelled { nextFetch = .distantPast }
        }
    }

    func announcement(dismissedID: String) -> CodexResetAnnouncement? {
        status?.announcement(at: checkedAt, dismissedID: dismissedID)
    }
}


import AppKit
import Foundation
import Testing
@testable import AIQuotaKit

@Suite("Codex login recovery")
struct CodexLoginRecoveryTests {
    private func session(_ workspace: String) throws -> CodexWebSessionResult {
        let payload = try JSONSerialization.data(withJSONObject: ["chatgpt_account_id": workspace])
            .base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return .init(sessionToken: "", accessToken: "e30.\(payload).fixture", expiresAt: nil)
    }

    @Test("personal login cannot complete an Enterprise reconnect; switching workspace can")
    func workspaceMismatchCanRecover() throws {
        let gate = CodexLoginCompletionGate()
        #expect(gate.evaluate(try session("personal-fixture"), expectedAccountID: "enterprise-fixture") == .waitForAccount)
        #expect(gate.evaluate(try session("enterprise-fixture"), expectedAccountID: "enterprise-fixture") == .complete)
    }

    @Test("retry rejects an old fetch and old verification without unlocking a new fetch")
    func retryInvalidatesOutstandingWork() throws {
        var attempt = CodexLoginAttempt()
        let originalResult = attempt.beginFetch()
        let original = try #require(originalResult)
        #expect(attempt.beginFetch() == nil)
        attempt.restart()
        let retriedResult = attempt.beginFetch()
        let retried = try #require(retriedResult)
        #expect(!attempt.accepts(original))
        #expect(attempt.accepts(retried))
        attempt.finishFetch(original)
        #expect(attempt.beginFetch() == nil)
        attempt.finishFetch(retried)
        #expect(attempt.beginFetch() == retried)
    }

    @Test("repeated retries never revive any previous attempt")
    func repeatedRetriesStayIsolated() throws {
        var attempt = CodexLoginAttempt()
        var oldAttempts: [Int] = []
        for _ in 0..<5 {
            let result = attempt.beginFetch()
            oldAttempts.append(try #require(result))
            attempt.restart()
        }
        let currentResult = attempt.beginFetch()
        let current = try #require(currentResult)
        #expect(oldAttempts.allSatisfy { !attempt.accepts($0) })
        #expect(attempt.accepts(current))
    }

    @MainActor
    @Test("mismatch recovery is visible in browser content, with workspace and login instructions")
    func visibleRecoveryMessage() {
        let view = CodexLoginFeedbackView()
        view.isHidden = true
        view.show(.differentAccount)
        #expect(!view.isHidden)
        let copy = view.arrangedSubviews.compactMap { ($0 as? NSTextField)?.stringValue }.joined(separator: " ")
        #expect(copy.contains("Different ChatGPT account or workspace"))
        #expect(copy.contains("Choose its workspace"))
        #expect(copy.contains("try another account"))
        #expect(copy.contains("saved connection hasn’t changed"))
    }
}

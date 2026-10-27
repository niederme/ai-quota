import AppKit

/// Feedback belongs above the browser, where it remains visible after login.
enum CodexLoginFeedback: Equatable {
    case differentAccount, verificationFailed, inconsistentSession, noSession

    var title: String {
        switch self {
        case .differentAccount: "Different ChatGPT account or workspace"
        case .verificationFailed, .inconsistentSession: "Couldn’t verify sign-in"
        case .noSession: "Sign-in isn’t ready yet"
        }
    }

    var message: String {
        switch self {
        case .differentAccount:
            "This sign-in doesn’t match the saved Codex account. Choose its workspace in ChatGPT, then click Check sign-in, or try another account. Your saved connection hasn’t changed."
        case .verificationFailed:
            "We couldn’t verify this sign-in. Click Check sign-in to retry, or try another account. Your saved connection hasn’t changed."
        case .inconsistentSession:
            "The browser session changed while we were checking it. Click Check sign-in again, or try another account. Your saved connection hasn’t changed."
        case .noSession:
            "Finish signing in to ChatGPT, then click Check sign-in. You can also try another account or cancel."
        }
    }
}

/// Restarting a browser invalidates both an in-flight fetch and verification.
/// An old response must never complete or unlock the new sign-in attempt.
struct CodexLoginAttempt {
    private(set) var generation = 0
    private(set) var isFetching = false

    mutating func beginFetch() -> Int? {
        guard !isFetching else { return nil }
        isFetching = true
        return generation
    }

    func accepts(_ generation: Int) -> Bool { generation == self.generation }

    mutating func finishFetch(_ generation: Int) {
        guard accepts(generation) else { return }
        isFetching = false
    }

    mutating func restart() {
        generation += 1
        isFetching = false
    }
}

@MainActor
final class CodexLoginFeedbackView: NSStackView {
    private let heading = NSTextField(labelWithString: "")
    private let message = NSTextField(wrappingLabelWithString: "")

    init() {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 4
        edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        heading.font = .boldSystemFont(ofSize: 13)
        heading.textColor = .labelColor
        message.font = .systemFont(ofSize: 13)
        message.textColor = .secondaryLabelColor
        message.preferredMaxLayoutWidth = 488
        addArrangedSubview(heading)
        addArrangedSubview(message)
        heading.setContentCompressionResistancePriority(.required, for: .vertical)
        message.setContentCompressionResistancePriority(.required, for: .vertical)
        wantsLayer = true
        layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.10).cgColor
        setAccessibilityIdentifier("codexSignInFeedback")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ feedback: CodexLoginFeedback) {
        heading.stringValue = feedback.title
        message.stringValue = feedback.message
        isHidden = false
        NSAccessibility.post(element: self, notification: .announcementRequested,
            userInfo: [.announcement: "\(feedback.title). \(feedback.message)",
                       .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}

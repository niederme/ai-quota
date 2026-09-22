import UIKit

/// A non-UI action copies the code without asking Safari to present a view controller.
@MainActor
final class CopySignInCodeRequestHandler: NSObject, @preconcurrency NSExtensionRequestHandling {
    private var request: NSExtensionContext?

    func beginRequest(with context: NSExtensionContext) {
        request = context
        do {
            guard let entry = try SignInCodeStore.load() else {
                finish("Code unavailable. Start sign-in again in AIQuota.", success: false)
                return
            }
            UIPasteboard.general.setItems(
                [[UIPasteboard.typeAutomatic: entry.code]],
                options: [.localOnly: true, .expirationDate: entry.expiresAt]
            )
            finish("Code copied", success: true)
        } catch {
            finish("Couldn’t copy. Try again in AIQuota.", success: false)
        }
    }

    private func finish(_ text: String, success: Bool) {
        UINotificationFeedbackGenerator().notificationOccurred(success ? .success : .warning)
        UIAccessibility.post(notification: .announcement, argument: text)
        request?.completeRequest(returningItems: nil)
        request = nil
    }
}

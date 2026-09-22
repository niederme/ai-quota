import UIKit

/// Safari invokes this extension directly from its toolbar, leaving the page open.
final class CopySignInCodeViewController: UIViewController {
    private var attempted = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !attempted else { return }
        attempted = true
        do {
            guard let entry = try SignInCodeStore.load() else {
                showError("This sign-in code has expired. Return to AIQuota and start sign-in again.")
                return
            }
            UIPasteboard.general.setItems(
                [[UIPasteboard.typeAutomatic: entry.code]],
                options: [.localOnly: true, .expirationDate: entry.expiresAt]
            )
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            showError("Couldn’t copy the sign-in code. Return to AIQuota and try again.")
        }
    }
    private func showError(_ message: String) {
        view.backgroundColor = .systemBackground
        let alert = UIAlertController(title: "Copy sign-in code", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Done", style: .default) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        present(alert, animated: true)
    }
}

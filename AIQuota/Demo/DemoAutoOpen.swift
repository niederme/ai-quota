import SwiftUI
import AppKit

// MARK: - Auto-open popover on launch (DEMO_MODE builds only)

#if DEMO_MODE

/// Opens the menu bar popover automatically shortly after launch so demos
/// start playing without anyone having to click the status item.
///
/// SwiftUI has no API to present a `MenuBarExtra` programmatically, so this
/// finds our own status-bar button and synthesizes a click. Demo builds only —
/// never compiled into Debug or Release.
private struct DemoAutoOpenModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.task {
            // Give the status item a beat to land in the menu bar.
            try? await Task.sleep(for: .milliseconds(600))
            clickStatusItem()
        }
    }

    @MainActor
    private func clickStatusItem() {
        for window in NSApp.windows where window.className == "NSStatusBarWindow" {
            guard let contentView = window.contentView,
                  let button = statusBarButton(in: contentView) else { continue }
            button.performClick(nil)
            return
        }
    }

    private func statusBarButton(in view: NSView) -> NSStatusBarButton? {
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let button = statusBarButton(in: subview) { return button }
        }
        return nil
    }
}

extension View {
    func demoAutoOpen() -> some View {
        modifier(DemoAutoOpenModifier())
    }
}

#endif

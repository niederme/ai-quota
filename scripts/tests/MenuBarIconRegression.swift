import AppKit
import SwiftUI
import AIQuotaKit

// Run with test-menubar-icons.sh in a logged-in macOS session. This exercises
// SwiftUI's actual MenuBarExtra -> NSStatusBarButton bridge, not an HStack preview.
@MainActor
private final class Fixture: ObservableObject {
    static let shared = Fixture()
    @Published var count = 1
    @Published var badge = false

    var inputs: [MenuBarGaugeInput] {
        (0..<count).map { index in
            let used = [61, 90, 100][index % 3]
            return MenuBarGaugeInput(usedPercent: used, secondaryPercent: 0,
                                     limitReached: used == 100, isLoading: false,
                                     worstPercent: used, showsSecondaryMetric: false)
        }
    }

    func run() async {
        let legacy = CommandLine.arguments.contains("--legacy")
        for count in [1, 2, 3, 6, 2, 1, 3] {
            self.count = count
            badge = count == 3 && !legacy
            try? await Task.sleep(for: .milliseconds(700))
            let buttons = NSApp.windows.flatMap { buttons(in: $0.contentView) }
            guard let button = buttons.first, let image = button.image else {
                fail("No native status button image")
            }
            let expected = CGFloat(count * 22 + (count - 1) * 5)
            if legacy && count == 3 {
                guard image.size.width == 22 else { fail("Legacy case did not reproduce") }
                print("REPRODUCED: three selected gauges yield one 22-point native image")
                NSApp.terminate(nil)
                return
            }
            guard image.size == NSSize(width: expected, height: 22) else {
                fail("\(count) gauges: native image \(image.size), expected width \(expected)")
            }
            guard button.bounds.width >= expected else { fail("Native button clips its image") }
            verifyPixels(image)
            print("PASS: \(count) gauges, image width \(expected), button width \(button.bounds.width), badge \(badge)")
        }
        NSApp.terminate(nil)
    }

    private func verifyPixels(_ image: NSImage) {
        guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data) else {
            fail("Cannot read rendered pixels")
        }
        let scale = CGFloat(bitmap.pixelsWide) / image.size.width
        for index in 0..<count {
            let x = Int(CGFloat(index * 27 + 11) * scale)
            let y = bitmap.pixelsHigh / 2
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                  color.alphaComponent > 0.5 else { fail("Gauge \(index) is missing") }
            // The center spark uses the account's status color, so this also
            // catches duplicated images and reordered account inputs.
            switch index % 3 {
            case 0: guard abs(color.redComponent - color.blueComponent) < 0.05 else { fail("Wrong healthy gauge") }
            case 1: guard color.redComponent > color.greenComponent + 0.1,
                          color.greenComponent > color.blueComponent + 0.2 else { fail("Wrong warning gauge") }
            default: guard color.redComponent > color.greenComponent + 0.3 else { fail("Wrong capped gauge") }
            }
        }
        if badge {
            let x = Int((image.size.width - 4) * scale)
            let y = Int(4 * scale)
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                  color.redComponent > color.blueComponent + 0.3 else { fail("Missing update badge") }
        }
    }

    private func buttons(in view: NSView?) -> [NSStatusBarButton] {
        guard let view else { return [] }
        if let button = view as? NSStatusBarButton { return [button] }
        return view.subviews.flatMap { buttons(in: $0) }
    }

    private func fail(_ message: String) -> Never {
        print("FAIL: \(message)")
        exit(1)
    }
}

private final class Delegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in await Fixture.shared.run() }
    }
}

@main
private struct MenuBarIconRegression: App {
    @NSApplicationDelegateAdaptor(Delegate.self) private var delegate
    @StateObject private var fixture = Fixture.shared

    var body: some Scene {
        MenuBarExtra {
            Text("AIQuota menu bar regression fixture")
        } label: {
            if CommandLine.arguments.contains("--legacy") && fixture.count != 2 {
                HStack(spacing: 5) {
                    ForEach(0..<fixture.count, id: \.self) { index in
                        MenuBarIconView(input: fixture.inputs[index])
                    }
                }
            } else {
                MultiMenuBarIconView(inputs: fixture.inputs, showsUpdateBadge: fixture.badge)
            }
        }
        .menuBarExtraStyle(.window)
    }
}

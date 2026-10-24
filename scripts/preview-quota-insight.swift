// Compile together with QuotaExhaustionForecast.swift and MacQuotaInsightBanner.swift.
// This standalone sample never loads app defaults, account data or networking.
import SwiftUI
import AppKit

private let sampleNow = Date(timeIntervalSince1970: 1_800_000_000)
private func sampleForecast() -> QuotaExhaustionForecast {
    let scope = QuotaForecastScope(accountID: "sample", provider: "claude", identity: "sample",
        source: "web", plan: "pro", window: .weekly, resetAt: sampleNow.addingTimeInterval(4 * 86400))
    let observations = (0...24).map { i in
        QuotaPaceObservation(scope: scope, date: sampleNow.addingTimeInterval(Double(i - 24) * 3600),
                             used: 25 + Double(i) * 40 / 24)
    }
    return QuotaExhaustionForecast.estimate(scope: scope, observations: observations, now: sampleNow)!
}

private struct SampleInsightView: View {
    @State private var dismissed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sample forecast · Simulated usage")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.top, 16)
            if dismissed {
                Text("Dismissed for this sample window.")
                    .font(.callout).padding(20)
            } else {
                MacQuotaInsightBanner(forecast: sampleForecast(), accountLabel: "Sample Claude") { dismissed = true }
            }
        }
        .padding(.bottom, 8)
    }
}

@main
struct QuotaInsightPreview: App {
    init() {
        // Optional headless visual verification. Uses only the synthetic fixture above.
        if let index = CommandLine.arguments.firstIndex(of: "--render"),
           CommandLine.arguments.count > index + 1 {
            let folder = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
            try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for width in [320, 420, 480] {
                for scheme in [ColorScheme.light, .dark] {
                    let content = SampleInsightView().frame(width: CGFloat(width))
                        .background(scheme == .dark ? Color.black : Color.white)
                        .environment(\.colorScheme, scheme)
                    let renderer = ImageRenderer(content: content)
                    renderer.scale = 2
                    let data = renderer.nsImage!.tiffRepresentation!
                    let png = NSBitmapImageRep(data: data)!.representation(using: .png, properties: [:])!
                    try! png.write(to: folder.appendingPathComponent("insight-\(width)-\(scheme == .dark ? "dark" : "light").png"))
                }
            }
            exit(0)
        }
    }
    var body: some Scene {
        WindowGroup("Quota insight preview — simulated data") {
            SampleInsightView().frame(minWidth: 320, idealWidth: 420, maxWidth: 480)
        }
        .defaultSize(width: 420, height: 180)
        .windowResizability(.contentSize)
    }
}

// Compile together with QuotaExhaustionForecast.swift and MacQuotaInsightBanner.swift.
// This standalone sample never loads app defaults, account data or networking.
import SwiftUI
import AppKit

private let sampleNow = Date.now
private func sampleForecast() -> QuotaExhaustionForecast {
    let scope = QuotaForecastScope(accountID: "sample", provider: "codex", identity: "sample",
        source: "web", plan: "pro", window: .weekly, resetAt: sampleNow.addingTimeInterval(4 * 86400))
    return .init(scope: scope, basis: .weeklyPattern, projectedUsedPercent: 140,
                 validUntil: sampleNow.addingTimeInterval(3600))
}

private struct SampleInsightView: View {
    @State private var dismissed = false
    var resetCount: Int? = 1
    var age: TimeInterval = 0
    var longName = false
    private var bankedResets: CodexBankedResetContext? {
        resetCount.map { .init(accountID: "sample", providerIdentity: "sample", credits: .init(availableCount: $0), fetchedAt: sampleNow.addingTimeInterval(-age)) }
    }
    private let identities = [
        AccountIdentity(key: "pro", service: "Codex", label: "Account 2", plan: "Pro"),
        AccountIdentity(key: "business", service: "Codex", label: "Codex Business", plan: "Business"),
        AccountIdentity(key: "max", service: "Claude", label: "Account 1", plan: "Max"),
        AccountIdentity(key: "enterprise", service: "Claude", label: "Claude Enterprise", plan: "Enterprise")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sample forecast · Simulated usage")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.top, 16)
            if dismissed {
                Text("Dismissed for this sample window.")
                    .font(.callout).padding(20)
            } else {
                MacAlertGroup {
                    MacResetNoticeBanner(title: "Codex reset credit announced", onReadMore: {}, onDismiss: {})
                    Color.overviewTrack.frame(height: 0.5).padding(.leading, 40)
                    MacQuotaInsightBanner(forecast: sampleForecast(),
                        accountLabel: longName ? "Codex Pro · A deliberately long custom connection name" : AccountPresentation.resolve(identities[0], among: identities).title,
                        bankedResets: bankedResets, inset: false) { dismissed = true }
                }.padding(.horizontal, 16)
                ForEach(identities, id: \.key) { identity in
                    VStack(alignment: .leading) {
                        Text(AccountPresentation.resolve(identity, among: identities).title).font(.headline)
                        Text(AccountPresentation.resolve(identity, among: identities).subtitle).font(.subheadline)
                    }.padding(.horizontal, 20).padding(.vertical, 4)
                }

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
                  for (tag, count, age) in [("unknown", nil, 0.0), ("zero", 0, 0.0), ("one", 1, 0.0), ("three", 3, 0.0), ("stale", 2, 301.0)] as [(String, Int?, TimeInterval)] {
                    let content = SampleInsightView(resetCount: count, age: age, longName: width == 320).frame(width: CGFloat(width))
                        .background(scheme == .dark ? Color.black : Color.white)
                        .environment(\.colorScheme, scheme)
                    let renderer = ImageRenderer(content: content)
                    renderer.scale = 2
                    let data = renderer.nsImage!.tiffRepresentation!
                    let png = NSBitmapImageRep(data: data)!.representation(using: .png, properties: [:])!
                    try! png.write(to: folder.appendingPathComponent("insight-\(width)-\(scheme == .dark ? "dark" : "light")-\(tag).png"))
                  }
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

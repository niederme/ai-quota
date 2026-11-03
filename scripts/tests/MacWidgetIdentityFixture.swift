import AppKit
import SwiftUI
import Vision
import AIQuotaKit

// Exercises production entries and SwiftUI branches. All accounts are in memory;
// cached-plan lookups use random fixture IDs and never mutate persisted data.
@main
@MainActor
struct MacWidgetIdentityFixture {
    static func main() throws {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let primary = ConnectedAccount(provider: .codex, displayLabel: "Primary", authSource: .oauth,
                                       connectionKind: .legacyPrimary, labelExplicitlyNamed: true)
        let studio = ConnectedAccount(provider: .codex, displayLabel: "Studio", authSource: .oauth,
                                      labelExplicitlyNamed: true)
        let family = ConnectedAccount(provider: .claude, displayLabel: "Family", authSource: .webSession,
                                      labelExplicitlyNamed: true)
        let accounts = [primary, studio, family]
        func usage(_ plan: String) throws -> CodexUsage {
            let response = try JSONDecoder().decode(WhamUsageResponse.self,
                from: Data("{\"planType\":\"\(plan)\"}".utf8))
            return CodexUsage(from: response)
        }
        func entry(_ selected: ConnectedAccount?, _ usage: CodexUsage? = nil,
                   available: [ConnectedAccount] = accounts) -> QuotaEntry {
            let config = ConfigurationAppIntent()
            config.account = selected.map(WidgetAccount.init)
            return QuotaEntry(date: .now, codexUsage: usage, claudeUsage: nil,
                              configuration: config, enrolledServices: [.codex, .claude], accounts: available)
        }
        let missingCodex = entry(studio)
        precondition(missingCodex.displayName(for: .codex) == "Codex · Studio")
        let missingClaude = entry(family)
        precondition(missingClaude.displayName(for: .claude) == "Claude · Family")
        let unsupportedCodex = entry(studio, try usage("business"))
        precondition(unsupportedCodex.codexUsage?.reportedWindowShape == nil)
        precondition(unsupportedCodex.displayName(for: .codex) == "Codex Business · Studio")

        // A removed Business selection still retained in widget configuration,
        // with a Pro primary remaining. Retained usage must not acquire its alias.
        let removed = entry(studio, try usage("business"), available: [primary, family])
        precondition(removed.selectedAccountUnavailable)
        precondition(removed.displayName(for: .codex) == "Codex connection unavailable")
        precondition(!removed.displayName(for: .codex).contains("Primary"))
        let removedWithoutReading = entry(studio, available: [primary, family])
        precondition(removedWithoutReading.selectedAccountUnavailable)
        let noSelection = entry(nil, try usage("pro"))
        precondition(!noSelection.selectedAccountUnavailable)
        precondition(noSelection.displayName(for: .codex) == "Codex Pro · Primary")
        let noRegistry = entry(nil, try usage("pro"), available: [])
        precondition(noRegistry.displayName(for: .codex) == "Codex Pro")
        let wrongProvider = ConnectedAccount(id: UUID(uuidString: studio.id)!, provider: .claude,
                                             displayLabel: "Other", authSource: .webSession)
        precondition(entry(studio, available: [wrongProvider]).selectedAccountUnavailable)

        var results: [[String: String]] = []
        func render<V: View>(_ view: V, _ name: String, width: CGFloat = 170,
                             contains phrases: [String], excludes: [String] = []) throws {
            let renderer = ImageRenderer(content: view.frame(width: width, height: 170)
                .background(Color(red: 0.12, green: 0.07, blue: 0.14))
                .environment(\.colorScheme, .dark))
            renderer.scale = 3
            guard let cgImage = renderer.cgImage else { fatalError("Render failed: \(name)") }
            let image = NSBitmapImageRep(cgImage: cgImage)
            try image.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ").replacingOccurrences(of: "•", with: "·")
            for phrase in phrases { precondition(text.localizedCaseInsensitiveContains(phrase), "\(name): missing '\(phrase)' in '\(text)'") }
            for phrase in excludes { precondition(!text.localizedCaseInsensitiveContains(phrase), "\(name): unexpected '\(phrase)' in '\(text)'") }
            results.append(["fixture": name, "recognized_text": text])
        }
        try render(WidgetSmallView(entry: missingCodex), "small-codex-missing",
                   contains: ["Codex", "Studio", "Sign in"])
        try render(WidgetSmallView(entry: missingClaude), "small-claude-missing",
                   contains: ["Claude", "Family", "Sign in"])
        try render(WidgetSmallView(entry: unsupportedCodex), "small-codex-unsupported",
                   contains: ["Codex Business", "Studio", "Usage unavailable"])
        try render(WidgetSmallView(entry: removed), "small-selection-removed",
                   contains: ["Codex connection unavailable", "choose a connection"], excludes: ["Primary", "Business", "Sign in"])
        try render(WidgetSmallView(entry: removedWithoutReading), "small-selection-removed-empty",
                   contains: ["connection unavailable", "choose a connection"], excludes: ["Primary", "Sign in"])
        try render(WidgetSingleServiceMediumView(entry: removed), "medium-selection-removed", width: 360,
                   contains: ["connection unavailable", "choose a connection"], excludes: ["Primary", "Business", "Sign in"])
        try render(WidgetSingleServiceMediumView(entry: missingCodex), "medium-codex-missing", width: 360,
                   contains: ["Codex", "Studio", "Sign in"])
        try render(WidgetSingleServiceMediumView(entry: missingClaude), "medium-claude-missing", width: 360,
                   contains: ["Claude", "Family", "Sign in"])
        try render(WidgetSingleServiceMediumView(entry: unsupportedCodex), "medium-codex-unsupported", width: 360,
                   contains: ["Codex Business", "Studio", "Usage unavailable"])
        let data = try JSONSerialization.data(withJSONObject: ["status": "passed", "render_cases": results], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent("results.json"))
        print("PASS: selection/default naming checks and \(results.count) production widget render/OCR cases")
    }
}

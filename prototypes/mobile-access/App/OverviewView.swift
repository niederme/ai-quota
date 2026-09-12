import SwiftUI
import MobileAccessCore

struct OverviewView: View {
    @State private var codex = ProbeModel()
    @State private var navigationID = UUID()
    @State private var showCodex = false
    @State private var showClaude = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var claude = ClaudeProbeModel()
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Allowance used")
                            .font(.subheadline).foregroundStyle(.secondary)
                        VStack(spacing: 16) {
                            ProviderDialCard(name: "Codex", icon: "logo-openai", reading: codex.reading,
                                             connected: codex.connected, busy: codex.busy, error: codex.error) {
                                ProbeView(model: codex)
                            }
                            ProviderDialCard(name: "Claude", icon: "logo-claude", reading: claude.reading,
                                             connected: claude.connected, busy: claude.busy, error: claude.error) {
                                ClaudeProbeView(model: claude)
                            }
                        }
                        Text("Outer arc · 5 hours    Inner arc · 7 days")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .frame(maxWidth: 780)
                    .frame(maxWidth: .infinity)
                }
                .background(Color(uiColor: .systemGroupedBackground))
            }
            .navigationTitle("AI Quota")
            .navigationDestination(isPresented: $showCodex) { ProbeView(model: codex) }
            .navigationDestination(isPresented: $showClaude) { ClaudeProbeView(model: claude) }
            .onOpenURL { url in
                guard url.scheme == "aiquota-probe" else { return }
                if url.host == "overview" {
                    showCodex = false
                    showClaude = false
                    navigationID = UUID()
                    codex.refreshOnOpen()
                    claude.refreshOnOpen()
                }
                if url.host == "codex" { showCodex = true; codex.refreshOnOpen() }
                if url.host == "claude" { showClaude = true; claude.refreshOnOpen() }
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                codex.refreshOnOpen()
                claude.refreshOnOpen()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        codex.refresh()
                        claude.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh all usage")
                    .disabled((!codex.connected || codex.busy) && (!claude.connected || claude.busy))
                }
            }
        }.id(navigationID).tint(Color(uiColor: .systemPurple))
    }
}

private struct ProviderDialCard<Destination: View>: View {
    let name: String
    let icon: String
    let reading: QuotaReading?
    let connected: Bool
    let busy: Bool
    let error: String?
    @ViewBuilder let destination: () -> Destination
    @Environment(\.colorSchemeContrast) private var contrast

    private var worst: Double { max(reading?.shortTerm?.usedPercent ?? 0, reading?.weekly?.usedPercent ?? 0) }
    private var tint: Color {
        if worst >= 95 { return Color(uiColor: .systemRed) }
        if worst >= 85 { return Color(uiColor: .systemOrange) }
        return Color(uiColor: .systemPurple)
    }
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var dialSize = 146.0

    var body: some View {
        NavigationLink(destination: destination) {
            cardContent
        }
        .buttonStyle(.plain)
        .accessibilityHint(connected ? "Opens \(name) account details" : "Connect \(name)")
    }
    private var cardContent: some View {
        ViewThatFits(in: .horizontal) {
            if !typeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: 16) {
                    identity
                    details.frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
                }
            }
            VStack(alignment: .leading, spacing: 16) {
                identity.frame(maxWidth: .infinity, alignment: .leading)
                details
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 218, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
    private var identity: some View {
        VStack(spacing: 4) {
            dial
            Text(name).font(.title3.bold())
                .multilineTextAlignment(.center)
                .frame(width: min(dialSize, 300))
        }
    }
    private var dial: some View {
        ZStack {
            arc(reading?.shortTerm, width: 9, opacity: 1)
            arc(reading?.weekly, width: 7, opacity: contrast == .increased ? 0.85 : (worst >= 85 ? 0.65 : 0.45))
                .padding(10)
            VStack(spacing: 5) {
                Image(icon).resizable().scaledToFit()
                    .frame(width: 22, height: 22)
                dialValue(reading?.shortTerm, label: "5h")
                    .font(.headline.monospacedDigit())
                dialValue(reading?.weekly, label: "7d")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .opacity(contrast == .increased ? 0.9 : 0.7)
            }
            .foregroundStyle(tint)
        }
        .padding(6)
        .frame(width: min(dialSize, 300), height: min(dialSize, 300))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) allowance used")
        .accessibilityValue("5 hours: \(accessibleValue(reading?.shortTerm)). 7 days: \(accessibleValue(reading?.weekly)).")
    }
    private func dialValue(_ window: QuotaWindow?, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            if let window { Text("\(window.usedPercent, specifier: "%.0f")%") }
            else { Text("—") }
            Text(label)
        }
    }
    private func accessibleValue(_ window: QuotaWindow?) -> String {
        window.map { "\(Int($0.usedPercent.rounded())) percent" } ?? "not reported"
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                resetCaption(reading?.shortTerm, label: "5h")
                resetCaption(reading?.weekly, label: "7d")
            }
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(alignment: .leading, spacing: 4) {
                    if busy { Text("Updating…") }
                    else if error != nil { Label("Refresh failed", systemImage: "exclamationmark.triangle") }
                    else if !connected { Text("Not connected") }
                    else if reading == nil { Text("No reading yet") }
                    else if worst >= 100 { Text("Limit reached").fontWeight(.semibold) }
                    if let reading {
                        let minutes = max(0, Int(context.date.timeIntervalSince(reading.fetchedAt) / 60))
                        Text(minutes == 0 ? "Checked just now" : "\(minutes >= 30 ? "Older reading" : "Checked") · \(minutes)m ago")
                    }
                }.font(.caption).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    private func resetCaption(_ window: QuotaWindow?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let reset = window?.resetsAt {
                Text("\(label) resets").foregroundStyle(.secondary)
                Text(reset.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                    .fontWeight(.semibold)
            } else {
                Text(window == nil ? "\(label) not reported" : "\(label) reset unavailable")
            }
        }
        .font(.subheadline)
        .foregroundStyle(label == "5h" ? tint : tint.opacity(contrast == .increased ? 0.9 : 0.7))
    }
    private func arc(_ window: QuotaWindow?, width: CGFloat, opacity: Double) -> some View {
        ZStack {
            Circle().trim(from: 0, to: 0.75)
                .stroke(Color(uiColor: .tertiarySystemFill), style: StrokeStyle(lineWidth: width, lineCap: .butt))
            if let window {
                Circle().trim(from: 0, to: 0.75 * min(100, max(0, window.usedPercent)) / 100)
                    .stroke(tint.opacity(opacity), style: StrokeStyle(lineWidth: width, lineCap: .butt))
            }
        }.rotationEffect(.degrees(135))
    }
}

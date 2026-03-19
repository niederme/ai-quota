import SwiftUI
import AIQuotaKit

struct PopoverView: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @Environment(\.openSettings) private var openSettings

    /// Captured reference to the MenuBarExtra NSWindow so we can re-show it
    /// after Settings opens (which steals key focus and causes the window to close).
    @State private var menuBarWindow: NSWindow?

    var body: some View {
        Group {
            if viewModel.isCodexAuthenticated || viewModel.isClaudeAuthenticated {
                authenticatedContent
            } else {
                signInContent
            }
        }
        .frame(width: 340)
        .background(WindowCapture { menuBarWindow = $0 })
        .task {
            if viewModel.usage == nil && viewModel.claudeUsage == nil {
                await viewModel.refresh()
            }
        }
    }

    private func openSettingsKeepingPopover() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        DispatchQueue.main.async { menuBarWindow?.orderFront(nil) }
    }

    // MARK: - Authenticated layout

    @ViewBuilder
    private var authenticatedContent: some View {
        VStack(spacing: 0) {
            header

            // Error banners
            if let error = viewModel.codexError {
                errorBanner(error,
                    dismiss: { viewModel.codexError = nil },
                    signIn: error.isAuthError ? { Task { await viewModel.signIn() } } : nil)
                Divider()
            }
            if let error = viewModel.claudeError {
                errorBanner(error,
                    dismiss: { viewModel.claudeError = nil },
                    signIn: error.isAuthError ? { Task { await viewModel.signInClaude() } } : nil)
                Divider()
            }

            // Two halves separated by a single vertical rule
            HStack(alignment: .top, spacing: 0) {
                // Left: Codex
                VStack(spacing: 12) {
                    codexGaugeSlot.frame(maxWidth: .infinity)
                    if viewModel.codexUsage != nil {
                        codexSecondaryStats
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)

                Divider()

                // Right: Claude
                VStack(spacing: 12) {
                    claudeGaugeSlot.frame(maxWidth: .infinity)
                    if viewModel.claudeUsage != nil {
                        claudeSecondaryStats
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }

            Divider()
            footer
        }
    }

    // MARK: - Gauge slots

    @ViewBuilder
    private var codexGaugeSlot: some View {
        if viewModel.isCodexAuthenticated {
            if let usage = viewModel.codexUsage {
                CircularGaugeView(
                    percent: usage.hourlyUsedPercent,
                    limitReached: usage.limitReached,
                    isLoading: false,
                    icon: "logo-openai",
                    iconColor: .purple,
                    label: "Codex",
                    windowLabel: "\(formatWindowDuration(usage.hourlyWindowSeconds)) window",
                    resetSeconds: usage.hourlyResetAfterSeconds,
                    isRefreshing: viewModel.isCodexLoading,
                    onRefresh: { Task { await viewModel.refreshCodex() } }
                )
            } else {
                CircularGaugeView(
                    percent: 0, limitReached: false, isLoading: true,
                    icon: "logo-openai", iconColor: .purple,
                    label: "Codex", windowLabel: "Loading…", resetSeconds: 0,
                    isRefreshing: true, onRefresh: {}
                )
            }
        } else {
            connectGauge(icon: "logo-openai", label: "Codex", color: .purple) {
                Task { await viewModel.signIn() }
            }
        }
    }

    @ViewBuilder
    private var claudeGaugeSlot: some View {
        let claudeColor = Color(red: 0.8, green: 0.45, blue: 0.1)
        if viewModel.isClaudeAuthenticated {
            if let usage = viewModel.claudeUsage {
                CircularGaugeView(
                    percent: usage.usedPercent,
                    limitReached: usage.limitReached,
                    isLoading: false,
                    icon: "logo-claude",
                    iconColor: claudeColor,
                    label: "Claude Code",
                    windowLabel: "5h window",
                    resetSeconds: usage.resetAfterSeconds,
                    isRefreshing: viewModel.isClaudeLoading,
                    onRefresh: { Task { await viewModel.refreshClaude() } }
                )
            } else {
                CircularGaugeView(
                    percent: 0, limitReached: false, isLoading: true,
                    icon: "logo-claude", iconColor: claudeColor,
                    label: "Claude Code", windowLabel: "Loading…", resetSeconds: 0,
                    isRefreshing: true, onRefresh: {}
                )
            }
        } else {
            connectGauge(icon: "logo-claude", label: "Claude Code", color: claudeColor) {
                Task { await viewModel.signInClaude() }
            }
        }
    }

    private func connectGauge(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(.fill.quaternary, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                    .rotationEffect(.degrees(135))
                VStack(spacing: 2) {
                    Image(icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .foregroundStyle(color.opacity(0.35))
                    Text("—")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.quaternary)
                }
            }
            .frame(width: 100, height: 100)

            VStack(spacing: 5) {
                Text(label).font(.caption.bold()).foregroundStyle(.secondary)
                Button("Connect", action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Secondary stats

    @ViewBuilder
    private var codexSecondaryStats: some View {
        if let usage = viewModel.codexUsage {
            VStack(alignment: .leading, spacing: 5) {
                compactRow("7-day", "\(usage.weeklyUsedPercent)%", "calendar")
                if let balance = usage.creditBalance {
                    compactRow("Credits", "\(Int(balance))", "creditcard.fill")
                }
                compactRow("Plan", usage.planType.capitalized, "person.fill")
            }
        }
    }

    @ViewBuilder
    private var claudeSecondaryStats: some View {
        if let usage = viewModel.claudeUsage {
            VStack(alignment: .leading, spacing: 5) {
                compactRow("7-day", "\(Int(usage.sevenDayUtilization.rounded()))%", "calendar")
                if let extra = usage.extraUsage, extra.isEnabled {
                    compactRow("Extra", "\(Int(extra.usedCredits))/\(extra.monthlyLimit)", "plus.circle.fill")
                }
                compactRow("Plan", usage.planDisplayName, "person.fill")
            }
        }
    }

    private func compactRow(_ label: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(width: 13)
            Text(label + ":").font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption2.monospacedDigit().bold())
        }
    }

    // MARK: - Header

    @ViewBuilder private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 20, height: 20)
            Text("AIQuota").font(.headline)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        Divider()
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Settings") { openSettingsKeepingPopover() }
            Spacer()
            Button("Quit", role: .destructive) { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .font(.body)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Sign-In landing (both unauthenticated)

    private var signInContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(spacing: 4) {
                    Text("AIQuota").font(.title3.bold())
                    Text("Monitor your AI quota at a glance.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 10) {
                    Button("Sign In with ChatGPT") {
                        Task { await viewModel.signIn() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.62, green: 0.22, blue: 0.93))
                    .controlSize(.large)

                    Button("Sign In with Claude Code") {
                        Task { await viewModel.signInClaude() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.8, green: 0.45, blue: 0.1))
                    .controlSize(.large)
                }
            }
            .padding(24)
            Divider()
            HStack {
                Spacer()
                Button("Quit", role: .destructive) { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.footnote)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ error: NetworkError, dismiss: @escaping () -> Void, signIn: (() -> Void)? = nil) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange).font(.footnote)
            Text(error.localizedDescription)
                .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            Spacer()
            if let signIn {
                Button("Sign In", action: signIn)
                    .buttonStyle(.borderless)
                    .font(.footnote.bold())
                    .foregroundStyle(.orange)
            }
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.orange.opacity(0.1))
    }

    // MARK: - Helpers

    private func formatWindowDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        return hours > 0 ? "\(hours)h" : "\(seconds / 60)m"
    }
}

// MARK: - Window capture helper

/// Reads the hosting NSWindow reference as soon as the view is in the hierarchy.
private struct WindowCapture: NSViewRepresentable {
    let onCapture: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onCapture(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onCapture(nsView.window) }
    }
}

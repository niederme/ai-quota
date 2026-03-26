import SwiftUI
import AIQuotaKit

struct PopoverView: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @Environment(\.openSettings) private var openSettings

    /// Captured reference to the MenuBarExtra NSWindow so we can re-show it
    /// after Settings opens (which steals key focus and causes the window to close).
    @State private var menuBarWindow: NSWindow?

    private var popoverWidth: CGFloat {
        viewModel.enrolledServices.count == 1 ? 240 : 340
    }

    var body: some View {
        Group {
            if viewModel.isRestoringSession {
                restoringSessionContent
            } else if !viewModel.enrolledServices.isEmpty {
                authenticatedContent
            } else {
                signInContent
            }
        }
        .frame(width: popoverWidth)
        .background(WindowCapture { menuBarWindow = $0 })
        .background {
            Button("") { viewModel.manualRefresh() }
                .keyboardShortcut("r", modifiers: .command)
                .hidden()
        }
        .task {
            if viewModel.usage == nil && viewModel.claudeUsage == nil {
                await viewModel.refresh()
            }
        }
    }

    // MARK: - Restoring session

    private var restoringSessionContent: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Restoring session…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(width: popoverWidth, height: 120)
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

            if viewModel.isCodexEnrolled, let error = viewModel.codexError {
                errorBanner(error,
                    dismiss: { viewModel.codexError = nil },
                    signIn: error.isAuthError ? { Task { await viewModel.signIn() } } : nil)
                Divider()
            }
            if viewModel.isClaudeEnrolled, let error = viewModel.claudeError {
                errorBanner(error,
                    dismiss: { viewModel.claudeError = nil },
                    signIn: error.isAuthError ? { Task { await viewModel.signInClaude() } } : nil)
                Divider()
            }

            gaugeRow
                .padding(.top, 16).padding(.bottom, 10)

            statsRow

            Divider()
            footer
        }
    }

    // MARK: - Gauge slots

    @ViewBuilder
    private var codexGaugeSlot: some View {
        if viewModel.isCodexAuthenticated {
            if let u = viewModel.codexUsage {
                CircularGaugeView(
                    primaryPercent: u.hourlyUsedPercent,
                    primaryLimitReached: u.limitReached,
                    secondaryPercent: u.weeklyUsedPercent,
                    secondaryLimitReached: u.isWeeklyExhausted,
                    isLoading: false,
                    icon: "logo-openai",
                    label: "Codex",
                    primaryLabel: formatWindowDuration(u.hourlyWindowSeconds),
                    secondaryLabel: "7d",
                    resetSeconds: u.hourlyResetAfterSeconds,
                    weeklyResetSeconds: u.weeklyResetAfterSeconds,
                    isRefreshing: viewModel.isCodexLoading,
                    onRefresh: { viewModel.manualRefresh() }
                )
                .help(codexTooltip(u))
            } else {
                CircularGaugeView(
                    primaryPercent: 0, primaryLimitReached: false,
                    secondaryPercent: 0, secondaryLimitReached: false,
                    isLoading: true, icon: "logo-openai",
                    label: "Codex", primaryLabel: "5h", secondaryLabel: "7d",
                    resetSeconds: 0, weeklyResetSeconds: 0, isRefreshing: true, onRefresh: {}
                )
            }
        } else {
            connectGauge(icon: "logo-openai", label: "Codex") {
                Task { await viewModel.signIn() }
            }
        }
    }

    @ViewBuilder
    private var claudeGaugeSlot: some View {
        if viewModel.isClaudeAuthenticated {
            if let u = viewModel.claudeUsage {
                CircularGaugeView(
                    primaryPercent: u.usedPercent,
                    primaryLimitReached: u.limitReached,
                    secondaryPercent: Int(u.sevenDayUtilization.rounded()),
                    secondaryLimitReached: u.sevenDayUtilization >= 100,
                    isLoading: false,
                    icon: "logo-claude",
                    label: "Claude Code",
                    primaryLabel: "5h",
                    secondaryLabel: "7d",
                    resetSeconds: u.resetAfterSeconds,
                    weeklyResetSeconds: u.sevenDayResetAfterSeconds,
                    isRefreshing: viewModel.isClaudeLoading,
                    onRefresh: { viewModel.manualRefresh() }
                )
                .help(claudeTooltip(u))
            } else {
                CircularGaugeView(
                    primaryPercent: 0, primaryLimitReached: false,
                    secondaryPercent: 0, secondaryLimitReached: false,
                    isLoading: true, icon: "logo-claude",
                    label: "Claude Code", primaryLabel: "5h", secondaryLabel: "7d",
                    resetSeconds: 0, weeklyResetSeconds: 0, isRefreshing: true, onRefresh: {}
                )
            }
        } else {
            connectGauge(icon: "logo-claude", label: "Claude Code") {
                Task { await viewModel.signInClaude() }
            }
        }
    }

    @ViewBuilder
    private var gaugeRow: some View {
        if viewModel.isCodexEnrolled && viewModel.isClaudeEnrolled {
            HStack(alignment: .top, spacing: 0) {
                codexGaugeSlot.frame(maxWidth: .infinity)
                Divider()
                claudeGaugeSlot.frame(maxWidth: .infinity)
            }
        } else if viewModel.isCodexEnrolled {
            codexGaugeSlot
        } else {
            claudeGaugeSlot
        }
    }

    @ViewBuilder
    private var statsRow: some View {
        let bothEnrolled = viewModel.isCodexEnrolled && viewModel.isClaudeEnrolled
        let hasCodexStats = viewModel.isCodexEnrolled && viewModel.codexUsage != nil
        let hasClaudeStats = viewModel.isClaudeEnrolled && viewModel.claudeUsage != nil

        if hasCodexStats || hasClaudeStats {
            Divider()
            if bothEnrolled && hasCodexStats && hasClaudeStats {
                HStack(alignment: .top, spacing: 0) {
                    codexSecondaryStats
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                    claudeSecondaryStats
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 10)
            } else if hasCodexStats {
                codexSecondaryStats
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                claudeSecondaryStats
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func codexTooltip(_ u: CodexUsage) -> String {
        var lines = [
            "\(formatWindowDuration(u.hourlyWindowSeconds)) window: \(u.hourlyUsedPercent)% used",
            "7-day window: \(u.weeklyUsedPercent)% used",
        ]
        if let balance = u.creditBalance { lines.append("Credits: \(Int(balance))") }
        if let local = u.approxLocalMessages, local.count == 2 {
            lines.append("Local messages: ~\(local[0]) / \(local[1])")
        }
        if let cloud = u.approxCloudMessages, cloud.count == 2 {
            lines.append("Cloud messages: ~\(cloud[0]) / \(cloud[1])")
        }
        lines.append("Plan: \(u.planType.capitalized)")
        return lines.joined(separator: "\n")
    }

    private func claudeTooltip(_ u: ClaudeUsage) -> String {
        var lines = [
            "5h window: \(u.usedPercent)% used",
            "7-day window: \(Int(u.sevenDayUtilization.rounded()))% used",
        ]
        if let extra = u.extraUsage, extra.isEnabled {
            lines.append("Extra credits: \(Int(extra.usedCredits)) / \(extra.monthlyLimit)")
        }
        lines.append("Plan: \(u.planDisplayName)")
        return lines.joined(separator: "\n")
    }

    private func connectGauge(icon: String, label: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(.fill.quaternary, style: StrokeStyle(lineWidth: 8, lineCap: .butt))
                    .rotationEffect(.degrees(135))
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(.fill.quaternary, style: StrokeStyle(lineWidth: 8, lineCap: .butt))
                    .rotationEffect(.degrees(135))
                    .padding(8)
                VStack(spacing: 2) {
                    Image(icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 15, height: 15)
                        .foregroundStyle(CircularGaugeView.accent.opacity(0.35))
                    Text("—")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.quaternary)
                }
                VStack {
                    Spacer()
                    Button("Connect", action: action)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.bottom, 2)
                }
            }
            .frame(width: 114, height: 114)

            VStack(spacing: 2) {
                Text(label)
                    .font(.headline.bold())
                Text("Not connected")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Secondary stats

    @ViewBuilder
    private var codexSecondaryStats: some View {
        if let usage = viewModel.codexUsage {
            VStack(alignment: .leading, spacing: 5) {
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
            // Colour key for the dual rings
            HStack(spacing: 8) {
                ringKey(label: "5h",    opacity: 1.0)
                ringKey(label: "7d", opacity: 0.5)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        Divider()
    }

    private func ringKey(label: String, opacity: Double) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(CircularGaugeView.accent.opacity(opacity))
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CircularGaugeView.accent.opacity(opacity))
        }
    }

    // MARK: - Footer

    private var footer: some View {
        ZStack {
            HStack {
                Button { openSettingsKeepingPopover() } label: {
                    footerActionLabel("Settings")
                }
                Spacer()
                Button(role: .destructive) { NSApp.terminate(nil) } label: {
                    footerActionLabel("Quit")
                }
            }
            if let date = viewModel.lastRefreshedAt {
                TimelineView(.periodic(from: date, by: 60)) { _ in
                    Text(date.relativeFormatted)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Sign-In landing (both unauthenticated)

    private var signInContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 24) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 60, height: 60)
                VStack(spacing: 5) {
                    Text("AIQuota").font(.title3.bold())
                    Text("Monitor your AI quota at a glance.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                VStack(spacing: 8) {
                    signInButton(
                        logo: "logo-openai",
                        label: "Sign in with ChatGPT",
                        action: { Task { await viewModel.signIn() } }
                    )
                    signInButton(
                        logo: "logo-claude",
                        label: "Sign in with Claude",
                        action: { Task { await viewModel.signInClaude() } }
                    )
                }
            }
            .padding(24)
            Divider()
            HStack {
                Button { openSettingsKeepingPopover() } label: {
                    footerActionLabel("Settings")
                }
                Spacer()
                Button(role: .destructive) { NSApp.terminate(nil) } label: {
                    footerActionLabel("Quit")
                }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private func signInButton(logo: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Image(logo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                Text(label)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                // Invisible spacer to balance the logo and keep text visually centred
                Color.clear.frame(width: 16, height: 16)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    private func footerActionLabel(_ title: String) -> some View {
        Text(title)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
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
            } else {
                Button {
                    dismiss()
                    viewModel.manualRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise").font(.caption)
                }
                .buttonStyle(.borderless)
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

// MARK: - Date helpers

private extension Date {
    /// "just now", "1m ago", "5m ago" — suitable for the freshness cue.
    var relativeFormatted: String {
        let elapsed = Int(-timeIntervalSinceNow)
        switch elapsed {
        case ..<10:  return "Just now"
        case ..<60:  return "\(elapsed)s ago"
        case ..<3600:
            let m = elapsed / 60
            return "\(m)m ago"
        default:
            let h = elapsed / 3600
            return "\(h)h ago"
        }
    }
}

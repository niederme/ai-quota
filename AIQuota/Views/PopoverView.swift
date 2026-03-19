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
            // Auto-refresh starts on launch; only need to kick it here
            // if the user opens the popover before the first cycle fires.
            if viewModel.usage == nil && viewModel.claudeUsage == nil {
                await viewModel.refresh()
            }
        }
    }

    /// Opens Settings and immediately brings the MenuBarExtra window back to the
    /// front so both panels are visible at the same time.
    private func openSettingsKeepingPopover() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        // The MenuBarExtra window closes when it loses key status (on the next
        // run-loop tick after openSettings fires). Re-show it right after.
        DispatchQueue.main.async {
            menuBarWindow?.orderFront(nil)
        }
    }

    // MARK: - Authenticated shell (single sheet)

    @ViewBuilder
    private var authenticatedContent: some View {
        VStack(spacing: 0) {
            header

            // Cards scroll if the window is short, but typically fit without scrolling.
            VStack(spacing: 8) {
                serviceCard {
                    codexCard
                }
                serviceCard {
                    claudeCard
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)

            Divider()
            footer
        }
    }

    // MARK: - Service card shell

    @ViewBuilder
    private func serviceCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .background(.fill.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 0.5)
            }
    }

    // MARK: - Per-service card content

    @ViewBuilder private var codexCard: some View {
        VStack(spacing: 0) {
            if let error = viewModel.codexError {
                errorBanner(error,
                    dismiss: { viewModel.codexError = nil },
                    signIn: error.isAuthError ? { Task { await viewModel.signIn() } } : nil)
                Divider()
            }
            if viewModel.isCodexAuthenticated {
                if let usage = viewModel.codexUsage {
                    codexContent(usage)
                } else if viewModel.isCodexLoading {
                    loadingPlaceholder
                } else {
                    emptyState
                }
            } else {
                connectRow(for: .codex)
            }
        }
    }

    @ViewBuilder private var claudeCard: some View {
        VStack(spacing: 0) {
            if let error = viewModel.claudeError {
                errorBanner(error,
                    dismiss: { viewModel.claudeError = nil },
                    signIn: error.isAuthError ? { Task { await viewModel.signInClaude() } } : nil)
                Divider()
            }
            if viewModel.isClaudeAuthenticated {
                if let usage = viewModel.claudeUsage {
                    claudeContent(usage)
                } else if viewModel.isClaudeLoading {
                    loadingPlaceholder
                } else {
                    emptyState
                }
            } else {
                connectRow(for: .claude)
            }
        }
    }

    // MARK: - Header

    @ViewBuilder private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 20, height: 20)
            Text("AIQuota")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        Divider()
    }

    // MARK: - Codex content

    // MARK: - Service header

    private func serviceHeader(label: String, isLoading: Bool, refresh: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Spacer()
            if isLoading {
                ProgressView().controlSize(.mini)
            } else {
                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Refresh")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    // MARK: - Codex content

    @ViewBuilder
    private func codexContent(_ usage: CodexUsage) -> some View {
        VStack(spacing: 0) {
            serviceHeader(label: "CODEX",
                          isLoading: viewModel.isCodexLoading,
                          refresh: { Task { await viewModel.refreshCodex() } })

            if usage.limitReached {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(.red)
                    Text("Rate limit reached").font(.subheadline.bold())
                    Spacer()
                    Text(countdownText(seconds: usage.hourlyResetAfterSeconds, short: true))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.red.opacity(0.08))
                Divider()
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(formatWindowDuration(usage.hourlyWindowSeconds)) window")
                        .font(.subheadline.bold()).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(usage.hourlyUsedPercent)%")
                        .font(.subheadline.monospacedDigit().bold())
                        .foregroundStyle(codexColor(usage))
                }
                Gauge(value: usage.hourlyPercentFraction) { EmptyView() }
                    .gaugeStyle(.linearCapacity)
                    .tint(codexColor(usage))
                    .animation(.easeInOut(duration: 0.4), value: usage.hourlyUsedPercent)
                HStack {
                    Text("\(100 - usage.hourlyUsedPercent)% remaining")
                        .font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    if !usage.limitReached {
                        Label(countdownText(seconds: usage.hourlyResetAfterSeconds, short: false),
                              systemImage: "clock.arrow.circlepath")
                            .font(.footnote).foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 8)

            Divider()
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("7-day window")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("\(usage.weeklyUsedPercent)% utilized")
                        .font(.subheadline.monospacedDigit())
                }
                Spacer()
                Text(countdownText(seconds: usage.weeklyResetAfterSeconds, short: true))
                    .font(.footnote).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            if let balance = usage.creditBalance,
               let local = usage.approxLocalMessages, local.count == 2,
               let cloud = usage.approxCloudMessages, cloud.count == 2 {
                Divider()
                VStack(spacing: 7) {
                    creditsRow(label: "Credits",        value: "\(Int(balance))",             icon: "creditcard.fill")
                    creditsRow(label: "Local messages", value: "~\(local[0]) / \(local[1])", icon: "desktopcomputer")
                    creditsRow(label: "Cloud messages", value: "~\(cloud[0]) / \(cloud[1])", icon: "cloud.fill")
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }

            Divider()
            planRow(plan: usage.planType.capitalized, fetchedAt: usage.fetchedAt)
        }
    }

    // MARK: - Claude content

    @ViewBuilder
    private func claudeContent(_ usage: ClaudeUsage) -> some View {
        VStack(spacing: 0) {
            serviceHeader(label: "CLAUDE CODE",
                          isLoading: viewModel.isClaudeLoading,
                          refresh: { Task { await viewModel.refreshClaude() } })

            if usage.limitReached {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(.red)
                    Text("Rate limit reached").font(.subheadline.bold())
                    Spacer()
                    Text(countdownText(seconds: usage.resetAfterSeconds, short: true))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.red.opacity(0.08))
                Divider()
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("5h window").font(.subheadline.bold()).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(usage.usedPercent)%")
                        .font(.subheadline.monospacedDigit().bold())
                        .foregroundStyle(claudeColor(usage))
                }
                Gauge(value: usage.percentFraction) { EmptyView() }
                    .gaugeStyle(.linearCapacity)
                    .tint(claudeColor(usage))
                    .animation(.easeInOut(duration: 0.4), value: usage.usedPercent)
                HStack {
                    Text("\(usage.remainingPercent)% remaining")
                        .font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    if !usage.limitReached {
                        Label(countdownText(seconds: usage.resetAfterSeconds, short: false),
                              systemImage: "clock.arrow.circlepath")
                            .font(.footnote).foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 8)

            Divider()
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("7-day window")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("\(Int(usage.sevenDayUtilization.rounded()))% utilized")
                        .font(.subheadline.monospacedDigit())
                }
                Spacer()
                Text(countdownText(seconds: usage.sevenDayResetAfterSeconds, short: true))
                    .font(.footnote).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            if let extra = usage.extraUsage, extra.isEnabled {
                Divider()
                creditsRow(
                    label: "Credits",
                    value: "\(Int(extra.usedCredits.rounded())) / \(extra.monthlyLimit)",
                    icon: "creditcard.fill"
                )
                .padding(.horizontal, 12).padding(.vertical, 8)
            }

            Divider()
            planRow(plan: usage.planDisplayName, fetchedAt: usage.fetchedAt)
        }
    }

    // MARK: - Connect row (unauthenticated service, compact)

    private func connectRow(for service: ServiceType) -> some View {
        let color: Color = service == .codex
            ? Color(red: 0.62, green: 0.22, blue: 0.93)
            : Color(red: 0.8, green: 0.45, blue: 0.1)
        return HStack(spacing: 8) {
            Image(systemName: service == .codex ? "brain.fill" : "sparkles")
                .font(.footnote)
                .foregroundStyle(color.opacity(0.5))
                .frame(width: 16)
            Text(service.displayName)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Connect") {
                Task {
                    if service == .codex { await viewModel.signIn() }
                    else { await viewModel.signInClaude() }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Shared rows

    private func creditsRow(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.footnote).foregroundStyle(.secondary).frame(width: 16)
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(.primary)
        }
    }

    private func planRow(plan: String, fetchedAt: Date) -> some View {
        HStack {
            Label(plan, systemImage: "person.fill")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
            Text("\(Text(fetchedAt, style: .relative)) ago")
                .font(.footnote).foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
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

    // MARK: - States

    private var loadingPlaceholder: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Loading…").font(.footnote).foregroundStyle(.secondary)
        }
        .frame(height: 80)
    }

    private var emptyState: some View {
        Text("No data yet").font(.footnote).foregroundStyle(.secondary).frame(height: 60)
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

    private func codexColor(_ usage: CodexUsage) -> Color {
        switch usage.hourlyUsedPercent {
        case ..<60: return .green
        case ..<85: return .yellow
        default:    return .red
        }
    }

    private func claudeColor(_ usage: ClaudeUsage) -> Color {
        switch usage.usedPercent {
        case ..<60: return .green
        case ..<85: return .yellow
        default:    return .red
        }
    }

    private func countdownText(seconds: Int, short: Bool) -> String {
        let days    = seconds / 86400
        let hours   = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0  { return short ? "\(days)d \(hours)h"    : "Resets in \(days)d \(hours)h" }
        if hours > 0 { return short ? "\(hours)h \(minutes)m" : "Resets in \(hours)h \(minutes)m" }
        return short ? "\(minutes)m" : "Resets in \(minutes)m"
    }

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

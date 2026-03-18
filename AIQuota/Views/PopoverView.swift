import SwiftUI
import AIQuotaKit

struct PopoverView: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            if viewModel.isAuthenticated {
                authenticatedContent
            } else {
                signInContent
            }
        }
        .frame(width: 340)
        .task {
            if viewModel.isAuthenticated && viewModel.usage == nil {
                await viewModel.refresh()
                viewModel.startAutoRefresh()
            }
        }
    }

    // MARK: - Authenticated

    @ViewBuilder
    private var authenticatedContent: some View {
        VStack(spacing: 0) {
            header
            if let error = viewModel.error {
                errorBanner(error)
            }
            if let usage = viewModel.usage {
                usageContent(usage)
            } else if viewModel.isLoading {
                loadingPlaceholder
            } else {
                emptyState
            }
            footer
        }
    }

    // MARK: Header

    @ViewBuilder private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 20, height: 20)
            Text("AIQuota")
                .font(.headline)
            Spacer()
            if viewModel.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.footnote)
                }
                .buttonStyle(.borderless)
                .help("Refresh now")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        Divider()
    }

    // MARK: Usage Content

    @ViewBuilder
    private func usageContent(_ usage: CodexUsage) -> some View {
        VStack(spacing: 0) {
            // Limit reached banner
            if usage.limitReached {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .foregroundStyle(.red)
                    Text("Weekly limit reached")
                        .font(.subheadline.bold())
                    Spacer()
                    Text(countdownText(seconds: usage.weeklyResetAfterSeconds, short: true))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.red.opacity(0.08))
                Divider()
            }

            // Weekly usage
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 5) {
                        Text("Codex")
                            .font(.subheadline.bold())
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("Weekly Usage")
                            .font(.subheadline.bold())
                    }
                    .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(usage.weeklyUsedPercent)%")
                        .font(.subheadline.monospacedDigit().bold())
                        .foregroundStyle(weeklyColor(usage))
                }

                Gauge(value: usage.weeklyPercentFraction) { EmptyView() }
                    .gaugeStyle(.linearCapacity)
                    .tint(weeklyColor(usage))
                    .animation(.easeInOut(duration: 0.4), value: usage.weeklyUsedPercent)

                HStack {
                    Text("\(usage.weeklyRemaining)% remaining")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !usage.limitReached {
                        Label(countdownText(seconds: usage.weeklyResetAfterSeconds, short: false), systemImage: "clock.arrow.circlepath")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider()

            // Short window (if active)
            if usage.hourlyUsedPercent > 0 {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Short window (\(formatWindowDuration(usage.hourlyWindowSeconds)))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("\(usage.hourlyUsedPercent)% used")
                            .font(.subheadline.monospacedDigit())
                    }
                    Spacer()
                    Text(countdownText(seconds: usage.hourlyResetAfterSeconds, short: true))
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                Divider()
            }

            // Credits / message estimates
            if let balance = usage.creditBalance, let local = usage.approxLocalMessages, local.count == 2,
               let cloud = usage.approxCloudMessages, cloud.count == 2 {
                VStack(spacing: 7) {
                    creditsRow(label: "Credits", value: "\(Int(balance))", icon: "creditcard.fill")
                    creditsRow(label: "Local messages", value: "~\(local[0]) / \(local[1])", icon: "desktopcomputer")
                    creditsRow(label: "Cloud messages", value: "~\(cloud[0]) / \(cloud[1])", icon: "cloud.fill")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                Divider()
            }

            // Plan badge
            HStack {
                Label(usage.planType.capitalized, systemImage: "person.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                if let fetchedAt = viewModel.usage?.fetchedAt {
                    Text("\(Text(fetchedAt, style: .relative)) ago")
                        .font(.footnote)
                        .foregroundStyle(.quaternary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }

    private func creditsRow(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.primary)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("Settings") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            Spacer()
            Button("Sign Out", role: .destructive) { viewModel.signOut() }
        }
        .buttonStyle(.borderless)
        .font(.footnote)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: States

    private var loadingPlaceholder: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Loading…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(height: 80)
    }

    private var emptyState: some View {
        Text("No data yet")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(height: 60)
    }

    // MARK: Sign-In

    private var signInContent: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            VStack(spacing: 4) {
                Text("AIQuota")
                    .font(.title3.bold())
                Text("Monitor your Codex weekly usage.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Sign In with ChatGPT") {
                Task { await viewModel.signIn() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.62, green: 0.22, blue: 0.93))
            .controlSize(.large)
        }
        .padding(24)
    }

    // MARK: Error Banner

    private func errorBanner(_ error: NetworkError) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.footnote)
            Text(error.localizedDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button { viewModel.error = nil } label: {
                Image(systemName: "xmark").font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.orange.opacity(0.1))
    }

    // MARK: Helpers

    private func weeklyColor(_ usage: CodexUsage) -> Color {
        switch usage.weeklyUsedPercent {
        case ..<60: return .green
        case ..<85: return .yellow
        default: return .red
        }
    }

    private func countdownText(seconds: Int, short: Bool) -> String {
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 { return short ? "\(days)d \(hours)h" : "Resets in \(days)d \(hours)h" }
        if hours > 0 { return short ? "\(hours)h \(minutes)m" : "Resets in \(hours)h \(minutes)m" }
        return short ? "\(minutes)m" : "Resets in \(minutes)m"
    }

    private func formatWindowDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        return hours > 0 ? "\(hours)h" : "\(seconds / 60)m"
    }
}

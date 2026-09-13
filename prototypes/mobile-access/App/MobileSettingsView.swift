import SwiftUI

struct MobileSettingsView: View {
    @AppStorage("refreshIntervalMinutes") private var refreshMinutes = 0
    let codex: ProbeModel
    let claude: ClaudeProbeModel
    var body: some View {
        Form {
            Section {
                Picker("Refresh every", selection: $refreshMinutes) {
                    Text("Auto").tag(0)
                    ForEach([1, 5, 10, 30], id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
            } header: { Text("General") } footer: {
                Text("While the app is open, Auto refreshes every 5 minutes, or every minute near a limit. iOS controls background widget updates. Opening the app also checks for fresh usage.")
            }
            Section {
                NavigationLink { ProbeView(model: codex) } label: {
                    account("Codex", connected: codex.connected, error: codex.error, updated: codex.reading?.fetchedAt, busy: codex.busy)
                }
                NavigationLink { ClaudeProbeView(model: claude) } label: {
                    account("Claude", connected: claude.connected, error: claude.error, updated: claude.reading?.fetchedAt, busy: claude.busy)
                }
            } header: { Text("Accounts") } footer: {
                Text("Manage accounts, reconnect, and check when usage last updated.")
            }
            Section("Privacy") {
                Text("Sign-in credentials stay in this device’s Keychain and are shared with its widgets. Usage is requested directly from each service.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
            }
        }.navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
    }
    private func account(_ name: String, connected: Bool, error: String?, updated: Date?, busy: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(name) {
                Text(busy ? "Updating…" : !connected ? "Connect" : error == nil ? "Connected" : "Needs attention")
                    .foregroundStyle(.secondary)
            }
            if let updated {
                Text("Last updated \(updated.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

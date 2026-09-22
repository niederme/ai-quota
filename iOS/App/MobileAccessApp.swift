import SwiftUI
import SafariServices
import MobileAccessCore

@main
struct MobileAccessApp: App {
    var body: some Scene {
        WindowGroup { OverviewView() }
    }
}

struct ProbeView: View {
    let model: ProbeModel
    @Environment(\.openURL) private var openURL
    @State private var confirmDisconnect = false
    @State private var showSecuritySettings = false
    @State private var didCopyCode = false
    var body: some View {
        Group {
            if model.connected && model.challenge == nil {
                AccountConnectionForm(plan: model.reading?.metadata?.displayPlan,
                    updated: model.reading?.fetchedAt, busy: model.busy,
                    needsReconnect: model.connectionFailure == .reconnect || model.connectionFailure == .renewal,
                    error: model.error, retry: { model.refresh() }, reconnect: { model.connect() },
                    disconnect: { confirmDisconnect = true })
            } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.message).font(.callout).accessibilityIdentifier("probe.status")
                    }
                    if !model.connected {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Enable device-code sign-in").font(.headline)
                            Text("Turn on device-code authorization in ChatGPT’s Security settings, then return here to sign in.")
                                .font(.callout)
                            Button("Open ChatGPT security settings") {
                                showSecuritySettings = true
                            }

                        }
                    }
                    if let challenge = model.challenge {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(challenge.userCode).font(.title.monospaced().bold()).textSelection(.enabled)
                            Button {
                                UIPasteboard.general.setItems(
                                    [[UIPasteboard.typeAutomatic: challenge.userCode]],
                                    options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(15 * 60)]
                                )
                                didCopyCode = true
                            } label: {
                                Label(didCopyCode ? "Copied" : "Copy code",
                                      systemImage: didCopyCode ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel(didCopyCode ? "Code copied. Copy again" : "Copy sign-in code")
                            Button("Open OpenAI sign-in") { openURL(challenge.verificationURL) }
                                .buttonStyle(.borderedProminent)
                            Text("Enter this code on OpenAI’s page, then return after approving.")
                                .font(.footnote).foregroundStyle(OverviewStyle.secondary)
                        }
                    }

                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(OverviewStyle.critical).font(.callout)
                    }
                    if model.busy {
                        HStack { ProgressView(); Button("Cancel") { model.cancel() } }
                    } else if model.connected {
                        VStack(alignment: .leading, spacing: 12) {
                            if model.connectionFailure == .reconnect {
                                Button("Reconnect Codex") { model.connect() }.buttonStyle(.borderedProminent)
                                Button("Retry refresh") { model.refresh() }
                            } else {
                                Button("Refresh quota") { model.refresh() }.buttonStyle(.borderedProminent)
                                Button("Reconnect Codex") { model.connect() }
                            }
                            if let date = model.renewedAt {
                                Text("Renewed \(date.formatted(date: .omitted, time: .standard))")
                                    .font(.caption).foregroundStyle(OverviewStyle.secondary)
                            }
                        }
                    } else {
                        Button("Connect Codex") { model.connect() }.buttonStyle(.borderedProminent)
                    }
                    if model.connected {
                        Divider().padding(.top, 12)
                        Button("Disconnect", role: .destructive) { confirmDisconnect = true }
                            .tint(OverviewStyle.critical).foregroundStyle(OverviewStyle.critical)
                            .frame(minHeight: 44).disabled(model.busy)
                    }
                }
                .frame(maxWidth: 700, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            }
            }
            .foregroundStyle(OverviewStyle.primary)
            .background(OverviewStyle.base)
            .navigationTitle("Codex account")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Remove this device’s connection?", isPresented: $confirmDisconnect) {
                Button("Disconnect", role: .destructive) { model.disconnect() }
            } message: {
                Text("Removes the local token and saved reading. It does not revoke the connection at OpenAI.")
            }
        .onChange(of: model.challenge?.userCode) { _, _ in
            didCopyCode = false
        }.sheet(isPresented: $showSecuritySettings) {
            ProbeBrowser(url: URL(string: "https://chatgpt.com/#settings/Security")!)
        }.tint(OverviewStyle.accent)
    }
    @ViewBuilder private func windows(_ reading: QuotaReading) -> some View {
        window(reading.shortTerm, unavailableLabel: "Short-term")
        window(reading.weekly, unavailableLabel: "Weekly")
    }
    private func window(_ window: QuotaWindow?, unavailableLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(window?.label ?? unavailableLabel).font(.headline)
            if let window {
                Text("\(window.usedPercent, specifier: "%.0f")% used").font(.title2.bold()).monospacedDigit()
                ProgressView(value: window.usedPercent, total: 100)
                    .accessibilityLabel("\(window.label) usage")
                if let reset = window.resetsAt {
                    Text("Reported reset \(reset.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(OverviewStyle.secondary)
                } else {
                    Text("Reset time unavailable").font(.caption).foregroundStyle(OverviewStyle.secondary)
                }
            } else {
                Text("Not reported").foregroundStyle(OverviewStyle.secondary)
            }
        }.frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
            .padding(16).background(OverviewStyle.track, in: RoundedRectangle(cornerRadius: OverviewStyle.radius))
    }
}

/// Present the web settings URL directly instead of dispatching a universal link.
/// Safari owns the page and credentials; the probe does not inspect its contents.
struct ProbeBrowser: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .done
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

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
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.message).font(.callout).accessibilityIdentifier("probe.status")
                    }
                    if !model.connected {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Before connecting").font(.headline)
                            Text("On the ChatGPT website, enable “Enable device code authorization for Codex” under Settings → Security and login. Then return here to connect.")
                                .font(.callout)
                            Button("Open ChatGPT security settings") {
                                showSecuritySettings = true
                            }
                            Text("This opens the website inside AI Quota. Sign in if asked, then use Settings → Security and login if needed. The toggle is on the website, not in the ChatGPT app. Tap Done when finished.")
                                .font(.footnote).foregroundStyle(.secondary)
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
                            Text("Enter this code on OpenAI’s page. If device-code sign-in is disabled, you can enable it in your ChatGPT security settings. Return here after approving.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if let reading = model.reading {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 16) { windows(reading) }
                            VStack(alignment: .leading, spacing: 16) { windows(reading) }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last successful reading").font(.caption).foregroundStyle(.secondary)
                            Text(reading.fetchedAt.formatted(date: .abbreviated, time: .standard))
                                .font(.callout.monospacedDigit())
                            Text("Saved reading. Refresh to check current usage.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red).font(.callout)
                    }
                    if model.busy {
                        HStack { ProgressView(); Button("Cancel") { model.cancel() } }
                    } else if model.connected {
                        VStack(alignment: .leading, spacing: 12) {
                            Button("Refresh quota") { model.refresh() }.buttonStyle(.borderedProminent)
                            Button("Reconnect Codex") { model.connect() }
                            if let date = model.renewedAt {
                                Text("Renewed \(date.formatted(date: .omitted, time: .standard))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Button("Connect Codex") { model.connect() }.buttonStyle(.borderedProminent)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("About this connection").font(.footnote.bold())
                        Text("Uses Codex’s device-code sign-in. OpenAI may identify this connection as Codex CLI. Tokens stay in this device’s Keychain. AI Quota only reads quota; it never sends prompts or uses reset credits.")
                    }.font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: 700, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Codex account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.connected {
                    Button("Disconnect", role: .destructive) { confirmDisconnect = true }.disabled(model.busy)
                }
            }
            .confirmationDialog("Remove this device’s connection?", isPresented: $confirmDisconnect) {
                Button("Disconnect", role: .destructive) { model.disconnect() }
            } message: {
                Text("Removes the local token and saved reading. It does not revoke the connection at OpenAI.")
            }
        }.onChange(of: model.challenge?.userCode) { _, _ in
            didCopyCode = false
        }.sheet(isPresented: $showSecuritySettings) {
            ProbeBrowser(url: URL(string: "https://chatgpt.com/#settings/Security")!)
        }.tint(Color(uiColor: .systemPurple))
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
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Reset time unavailable").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Not reported").foregroundStyle(.secondary)
            }
        }.frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
            .padding(16).background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
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

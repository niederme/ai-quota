import SwiftUI
import MobileAccessCore

struct ClaudeProbeView: View {
    let model: ClaudeProbeModel
    @State private var pastedCode = ""
    @State private var confirmDisconnect = false
    @State private var showSignIn = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Claude account").font(.title.bold())
                Text(model.message).font(.callout)
                if let reading = model.reading {
                    window(reading.shortTerm, label: "5 hours")
                    window(reading.weekly, label: "Weekly")
                    Text("Last successful reading: \(reading.fetchedAt.formatted(date: .abbreviated, time: .standard))")
                        .font(.footnote)
                    Text("Saved reading. Refresh to check current usage.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
                if model.busy {
                    ProgressView()
                    Button("Cancel") { model.cancel(); pastedCode = "" }
                } else if model.connected {
                    Button("Refresh quota") { model.refresh() }.buttonStyle(.borderedProminent)
                    Button("Refresh connection") { model.refresh(forceRenewal: true) }
                    if let date = model.renewedAt {
                        Text("Renewed \(date.formatted(date: .omitted, time: .standard))").font(.caption)
                    }
                    Button("Disconnect Claude", role: .destructive) { confirmDisconnect = true }
                } else if model.challenge != nil {
                    Button("Open Claude sign-in") { showSignIn = true }
                        .buttonStyle(.borderedProminent)
                    Text("Authorize in the browser, copy the complete code shown by Claude, then tap Done and paste it below. The code belongs to this attempt and expires after 15 minutes.")
                        .font(.callout)
                    SecureField("Authorization code", text: $pastedCode)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    Button("Finish connecting") {
                        let code = pastedCode
                        pastedCode = ""
                        model.finishSignIn(code)
                    }.disabled(pastedCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Cancel sign-in") { model.cancel(); pastedCode = "" }
                } else {
                    Button("Connect Claude") { model.connect() }.buttonStyle(.borderedProminent)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("About this connection").bold()
                    Text("Claude may identify this sign-in as Claude Code. The requested permissions include profile access and API-key creation. AI Quota never creates keys, sends prompts, or requests inference permission. Tokens stay in a separate Keychain entry on this device.")
                }.font(.footnote).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: 700, alignment: .leading).frame(maxWidth: .infinity)
        }
        .navigationTitle("Claude account")
        .sheet(isPresented: $showSignIn) {
            if let challenge = model.challenge {
                ProbeBrowser(url: challenge.authorizationURL)
            }
        }
        .confirmationDialog("Remove Claude from this device?", isPresented: $confirmDisconnect) {
            Button("Disconnect", role: .destructive) { model.disconnect() }
        } message: {
            Text("Removes the local connection and reading. It does not revoke authorization at Claude.")
        }
    }
    private func window(_ value: QuotaWindow?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.headline)
            if let value {
                Text("\(value.usedPercent, specifier: "%.0f")% used").font(.title2.bold())
                ProgressView(value: value.usedPercent, total: 100)
                if let date = value.resetsAt {
                    Text("Reported reset \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption)
                } else { Text("Reset time unavailable").font(.caption) }
            } else { Text("Not reported") }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(16).background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
    }
}

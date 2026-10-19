import SwiftUI
import MobileAccessCore

struct DevinProbeView: View {
    let model: DevinProbeModel
    @State private var pastedToken = ""
    @State private var confirmDisconnect = false

    var body: some View {
        Group {
        if model.isDemo {
            DemoAccountView()
        } else if model.connected, model.connectionFailure != .reconnect, model.connectionFailure != .renewal {
            AccountConnectionForm(plan: model.reading?.metadata?.displayPlan,
                updated: model.reading?.fetchedAt, busy: model.busy,
                needsReconnect: false,
                error: model.error, retry: { model.refresh() },
                reconnect: { }, disconnect: { confirmDisconnect = true })
        } else {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(model.connected ? "Reconnect Devin" : "Connect Devin").font(.title2.bold())
                if model.connected {
                    Text("This session token was rejected. Paste a fresh one to keep updating.")
                        .foregroundStyle(OverviewStyle.warning)
                }
                Text("Paste the session token Devin keeps on your Mac: `windsurf_api_key` in `~/.local/share/devin/credentials.toml`, or the API key shown by `devin` in your terminal.").foregroundStyle(OverviewStyle.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Devin session token").font(.headline)
                    SecureField("devin-session-token$…", text: $pastedToken)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder).submitLabel(.go)
                        .onSubmit { submit() }
                    if let error = model.error {
                        Text(error).font(.callout).foregroundStyle(OverviewStyle.critical)
                    }
                }
                Button(action: submit) {
                    HStack {
                        if model.busy { ProgressView().tint(.white) }
                        Text(model.busy ? "Connecting…" : "Connect Devin")
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(model.busy || pastedToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if model.connected {
                    Divider().padding(.top, 12)
                    Button("Disconnect", role: .destructive) { confirmDisconnect = true }
                        .tint(OverviewStyle.critical).foregroundStyle(OverviewStyle.critical)
                        .frame(minHeight: 44).disabled(model.busy)
                }
            }.padding(24).frame(maxWidth: 700, alignment: .leading).frame(maxWidth: .infinity)
        }
        }
        }
        .foregroundStyle(OverviewStyle.primary)
        .background(OverviewStyle.base)
        .tint(OverviewStyle.accent)
        .navigationTitle("Devin account")
        .modifier(DismissAfterAccountConnection(completionID: model.signInCompletionID))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove Devin from this device?", isPresented: $confirmDisconnect) {
            Button("Disconnect", role: .destructive) { model.disconnect() }
        } message: {
            Text("Removes the local connection and reading. It does not sign you out of Devin.")
        }
    }

    private func submit() {
        guard !model.busy, !pastedToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.connect(token: pastedToken)
    }
}

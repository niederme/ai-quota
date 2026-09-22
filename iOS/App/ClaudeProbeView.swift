import SwiftUI
import MobileAccessCore

struct ClaudeProbeView: View {
    let model: ClaudeProbeModel
    @State private var pastedCode = ""
    @State private var confirmDisconnect = false
    @State private var showSignIn = false

    var body: some View {
        Group {
        if model.isDemo {
            DemoAccountView()
        } else if model.connected && model.challenge == nil {
            AccountConnectionForm(plan: model.reading?.metadata?.displayPlan,
                updated: model.reading?.fetchedAt, busy: model.busy,
                needsReconnect: model.connectionFailure == .reconnect || model.connectionFailure == .renewal,
                error: model.error, updatesPaused: SharedQuotaStore(.claude).updatesPaused, retry: { model.refresh() }, reconnect: { startSignIn() },
                disconnect: { confirmDisconnect = true })
        } else {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if model.challenge != nil {
                    Text("Connect Claude").font(.title2.bold())
                    Text("Sign in, then copy the code from Claude and paste it here.").foregroundStyle(OverviewStyle.secondary)
                    Button("Open Claude sign-in") { showSignIn = true }.buttonStyle(.bordered)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Authorization code").font(.headline)
                        SecureField("Paste your code", text: $pastedCode)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder).submitLabel(.go)
                            .onSubmit { submit() }
                        if let error = model.error { Text(error).font(.callout).foregroundStyle(OverviewStyle.critical) }
                    }
                    Button(action: submit) {
                        HStack {
                            if model.busy { ProgressView().tint(.white) }
                            Text(model.busy ? "Connecting…" : "Connect Claude")
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(model.busy || pastedCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Cancel sign-in") { model.cancel(); pastedCode = "" }
                } else {
                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(OverviewStyle.warning)
                    } else if model.connectionFailure != nil {
                        Label("This connection needs attention. Retry or reconnect Claude.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(OverviewStyle.warning)
                    } else { Text(model.message).font(.callout) }
                    if model.busy {
                        ProgressView("Refreshing…")
                    } else if model.connected {
                        if model.connectionFailure == .reconnect || model.connectionFailure == .renewal {
                            Button("Reconnect Claude") { startSignIn() }.buttonStyle(.borderedProminent)
                            Button("Retry update") { model.refresh() }
                        } else {
                            Button("Refresh usage") { model.refresh() }.buttonStyle(.borderedProminent)
                            Button("Reconnect Claude") { startSignIn() }
                        }
                    } else {
                        Button("Sign In") { startSignIn() }.buttonStyle(.borderedProminent)
                    }

                }
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
        .navigationTitle("Claude Code account")
        .modifier(DismissAfterAccountConnection(completionID: model.signInCompletionID))
        .navigationBarTitleDisplayMode(.inline)
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
    private func startSignIn() {
        pastedCode = ""
        model.connect()
        showSignIn = model.challenge != nil
    }
    private func submit() {
        guard !model.busy, !pastedCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.finishSignIn(pastedCode)
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
            .padding(16).background(OverviewStyle.track, in: RoundedRectangle(cornerRadius: OverviewStyle.radius))
    }
}

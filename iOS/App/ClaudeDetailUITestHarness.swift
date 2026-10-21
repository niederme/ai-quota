#if DEBUG
import SwiftUI

/// Exercises the shipped detail view without credentials or provider traffic.
@MainActor private final class ClaudeDetailLookupFixture {
    private var attempts = 0

    func lookup() async -> ClaudeOrganizationLookup {
        attempts += 1
        return attempts == 1 ? .temporarilyUnavailable : .reconnectRequired
    }
}

struct ClaudeDetailUITestHarness: View {
    @State private var fixture = ClaudeDetailLookupFixture()
    @State private var account = ClaudeProbeModel(restore: false)

    var body: some View {
        NavigationStack {
            ScrollView {
                ClaudeEnterpriseDetailView(account: account) { await fixture.lookup() }
                    .padding()
            }
            .navigationTitle("Claude")
        }
    }
}

struct ServiceDetailLoadingUITestHarness: View {
    let service: String

    var body: some View {
        ServiceAccountSheet(showsClose: false) {
            ServiceDetailContent(
                name: service,
                icon: service == "Claude" ? "logo-claude" : "logo-openai",
                reading: nil,
                connected: true,
                busy: true,
                error: nil,
                failure: nil,
                refresh: {}
            ) { Text("Account") }
        }
    }
}

struct ClaudeEnterpriseLoadingUITestHarness: View {
    @State private var account = ClaudeProbeModel(restore: false)

    var body: some View {
        NavigationStack {
            ScrollView {
                ClaudeEnterpriseDetailView(account: account) {
                    try? await Task.sleep(for: .seconds(300))
                    return .temporarilyUnavailable
                }
                .padding(16)
            }
            .navigationTitle("Claude")
        }
    }
}

/// Drives the real SwiftUI sheet and session transaction through a successful
/// same-organization SSO result, with local response fixtures.
struct ClaudeDetailSSOUITestHarness: View {
    private let organizationID = "123e4567-e89b-12d3-a456-426614174000"
    @State private var account = ClaudeProbeModel(restore: false)
    @State private var configured = false
    @State private var showDetail = false
    @State private var prompted = false
    @State private var completedSignIn = false

    var body: some View {
        Group {
            if configured {
                Button("Open Claude details") { showDetail = true }
            } else {
                ProgressView()
            }
        }
            .sheet(isPresented: $showDetail) {
                ServiceAccountSheet {
                    ScrollView {
                        ClaudeEnterpriseDetailView(account: account) {
                            .verified(organizationID)
                        }
                        .padding(16)
                    }
                    .navigationTitle("Claude")
                }
            }
            .task {
                guard !configured else { return }
                account.webDetailsSession.testResponses = [
                    "organizations": Data("[{\"uuid\":\"\(organizationID)\"}]".utf8),
                    "spend": Data(#"{"currency":"USD","series":[{"bucket":"2026-10-20","group":"Claude Code","cost_minor_units":425}],"totals":[{"group":"Claude Code","cost_minor_units":425,"pct_of_total":100}]}"#.utf8),
                    "skills": Data(#"{"items":[{"skill_name":"sample-skill","invocation_count":2,"total_cost_minor_units":120}],"has_more":false}"#.utf8)
                ]
                configured = true
            }
            .onChange(of: account.webDetailsSession.state) { _, state in
                if state == .checking && !prompted {
                    prompted = true
                    Task { account.webDetailsSession.testRequireSignIn() }
                } else if state == .awaitingSignIn && !completedSignIn {
                    completedSignIn = true
                    Task { await account.webDetailsSession.testProbe() }
                }
            }
    }
}
#endif

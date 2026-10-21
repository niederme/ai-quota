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

/// Drives the real SwiftUI sheet and session transaction through a successful
/// same-organization SSO result, with local response fixtures.
struct ClaudeDetailSSOUITestHarness: View {
    private let organizationID = "123e4567-e89b-12d3-a456-426614174000"
    @State private var account = ClaudeProbeModel(restore: false)
    @State private var configured = false
    @State private var showDetail = false

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
                var prompted = false
                var completedSignIn = false
                while !Task.isCancelled && !completedSignIn {
                    let state = account.webDetailsSession.state
                    if state == .checking && !prompted {
                        prompted = true
                        account.webDetailsSession.testRequireSignIn()
                    } else if state == .awaitingSignIn {
                        completedSignIn = true
                        await account.webDetailsSession.testProbe()
                    }
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
    }
}
#endif

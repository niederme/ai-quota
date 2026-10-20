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
#endif

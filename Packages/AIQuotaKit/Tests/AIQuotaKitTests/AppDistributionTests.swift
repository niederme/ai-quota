import Testing
@testable import AIQuotaKit

@Suite("Distribution channel credential policy")
struct AppDistributionTests {
    @Test("Store builds cannot discover host tool credentials")
    func storeChannel() {
        #expect(!AppDistribution.allowsHostCredentialDiscovery(info: ["AIQuotaAppStoreBuild": true]))
    }
    @Test("Existing direct builds retain host tool credential discovery")
    func directChannel() {
        #expect(AppDistribution.allowsHostCredentialDiscovery(info: [:]))
        #expect(AppDistribution.allowsHostCredentialDiscovery(info: ["AIQuotaAppStoreBuild": false]))
    }
}

import Foundation
import Testing
@testable import AIQuotaKit

@Test func accountAlertNamesPreserveIdentityAndExplicitNamesAcrossCoding() throws {
    var accounts = [
        ConnectedAccount(provider: .codex, displayLabel: "Account 2", authSource: .oauth, labelExplicitlyNamed: false),
        ConnectedAccount(provider: .codex, displayLabel: "Work", authSource: .oauth),
        ConnectedAccount(provider: .claude, displayLabel: "Service 2", authSource: .webSession, labelExplicitlyNamed: false),
        ConnectedAccount(provider: .claude, displayLabel: "Family", authSource: .webSession)
    ]
    #expect(accounts.map(\.alertDisplayName) == ["Codex", "Codex · Work", "Claude", "Claude · Family"])
    accounts[0].labelExplicitlyNamed = true
    let decoded = try JSONDecoder().decode([ConnectedAccount].self, from: JSONEncoder().encode(accounts))
    #expect(decoded == accounts)
    #expect(decoded[0].alertDisplayName == "Codex · Account 2")
    #expect(Set(decoded.map(\.id)).count == 4)
    var old = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(accounts[0])) as? [String: Any])
    old.removeValue(forKey: "labelExplicitlyNamed")
    let legacy = try JSONDecoder().decode(ConnectedAccount.self, from: JSONSerialization.data(withJSONObject: old))
    // Older Mac records cannot distinguish an ordinal alias chosen by the owner.
    #expect(legacy.alertDisplayName == "Codex · Account 2")
    #expect(legacy.id == accounts[0].id)
}

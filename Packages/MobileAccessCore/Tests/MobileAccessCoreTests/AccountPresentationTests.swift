import Testing
@testable import MobileAccessCore

private func item(_ id: String, _ service: String, _ plan: String?, _ label: String = "Account 2", _ origin: AccountIdentity.Origin = .unknown) -> AccountIdentity {
    .init(key: id, service: service, label: label, plan: plan, origin: origin)
}
@Test func fourConnectionsUseRealPlansOnEveryIdentitySurface() {
    let peers = [item("a", "Codex", "pro"), item("b", "Codex", "business"), item("c", "Claude", "max"), item("d", "Claude", "enterprise")]
    for (peer, title) in zip(peers, ["Codex Pro", "Codex Business", "Claude Max", "Claude Enterprise"]) {
        let name = AccountPresentation.resolve(peer, among: peers)
        #expect(name.title == title)
        #expect(name.notificationTitle == title)
        #expect(!name.requiresName)
        #expect(!name.subtitle.contains("Account 2"))
    }
}
@Test func matchingPlansAskForNamesWithoutInventingAnIdentity() {
    let peers = [item("opaque-a", "Codex", "Pro"), item("opaque-b", "Codex", "Pro")]
    for order in [peers, Array(peers.reversed())] {
        for p in peers {
            let name = AccountPresentation.resolve(p, among: order)
            #expect(name.title == "Codex Pro")
            #expect(name.requiresName)
            #expect(name.managementHint != nil)
            #expect(!name.title.contains(p.key))
            #expect(name.notificationTitle == "Codex usage update")
        }
    }
    let named = [item("opaque-a", "Codex", "Pro", "Research", .user), item("opaque-b", "Codex", "Pro", "Writing", .user)]
    #expect(!AccountPresentation.resolve(named[0], among: named).requiresName)
    #expect(AccountPresentation.resolve(named[0], among: named).title == "Codex Pro · Research")
    #expect(AccountPresentation.resolve(named[0], among: named).notificationTitle == "Codex usage update")
}
@Test func aliasesProvenanceAndUnavailablePlansAreHandledConservatively() {
    #expect(AccountPresentation.resolve(item("a", "Codex", "Business", "Codex Pro", .user), among: []).title == "Codex Business · Codex Pro")
    #expect(AccountPresentation.resolve(item("a", "Codex", "Business", "Codex Pro 2", .generated), among: []).title == "Codex Business")
    #expect(AccountPresentation.resolve(item("a", "Claude", nil, "Claude Enterprise 2", .generated), among: []).title == "Claude Enterprise")
    #expect(AccountPresentation.resolve(item("a", "Claude", nil, "Research"), among: []).title == "Claude · Research")
    #expect(AccountPresentation.resolve(item("a", "Codex", nil), among: []).subtitle == "Plan unavailable")
    #expect(AccountPresentation.resolve(item("a", "Codex", "Pro", "Account 2", .user), among: []).title == "Codex Pro · Account 2")
    let duplicates = [item("a", "Claude", "Max", "  RESEARCH  ", .user), item("b", "Claude", "Max", "research", .user)]
    #expect(AccountPresentation.resolve(duplicates[0], among: duplicates).requiresName)
    let long = String(repeating: "Long alias ", count: 30)
    #expect(AccountPresentation.resolve(item("a", "Codex", "Pro", long, .user), among: []).title.contains("Long alias"))
}

@Test func uncertainLegacyAliasesSurvivePlanChanges() {
    let alias = item("legacy", "Codex", "Business", "Codex Pro 2", .unknown)
    #expect(AccountPresentation.resolve(alias, among: []).title == "Codex Business · Codex Pro 2")
    let missing = item("legacy", "Claude", nil, "Claude Enterprise", .unknown)
    #expect(AccountPresentation.resolve(missing, among: []).plan == nil)
    #expect(AccountPresentation.resolve(missing, among: []).subtitle.hasPrefix("Plan unavailable"))
}

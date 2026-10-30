import XCTest
@testable import AIQuota_iOS

final class AccountCardOrderTests: XCTestCase {
    private func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    func testVersionOneStateMigratesFromServiceGroupedOrderWithoutLosingProfiles() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let versionOneState: [String: Any] = [
            "version": 1,
            "profiles": [
                ["id": "live", "service": "codex", "label": "Codex Personal", "isLegacy": true],
                ["id": "codex-work", "service": "codex", "label": "Codex Work", "isLegacy": false],
                ["id": "live", "service": "claude", "label": "Claude Personal", "isLegacy": true],
                ["id": "claude-work", "service": "claude", "label": "Claude Work", "isLegacy": false]
            ],
            "defaults": ["codex": "live", "claude": "live"],
            "serviceOrder": ["claude", "codex"]
        ]
        let data = try JSONSerialization.data(withJSONObject: versionOneState)
        try data.write(to: root.appendingPathComponent("account-registry-v1.json"))

        let registry = AccountRegistry.Store(root: root, legacyServices: [])

        XCTAssertEqual(registry.accountOrder(), [
            "claude\u{0}live",
            "claude\u{0}claude-work",
            "codex\u{0}live",
            "codex\u{0}codex-work"
        ])
        XCTAssertEqual(Set(registry.all().map(\.orderKey)), Set(registry.accountOrder()))
        XCTAssertEqual(registry.all().count, 4)
    }

    func testInterleavedAccountOrderDistinguishesBothLegacyLiveProfilesAndPersists() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = AccountRegistry.Store(root: root, legacyServices: [.codex, .claude])
        let codexWork = registry.add(service: .codex)
        let claudeWork = registry.add(service: .claude)
        let order = [
            AccountProfile(id: "live", service: .claude, label: "", isLegacy: true).orderKey,
            codexWork.orderKey,
            AccountProfile(id: "live", service: .codex, label: "", isLegacy: true).orderKey,
            claudeWork.orderKey
        ]

        registry.setAccountOrder(order)

        let reopened = AccountRegistry.Store(root: root, legacyServices: [])
        XCTAssertEqual(reopened.accountOrder(), order)
        XCTAssertEqual(Set(reopened.all().map(\.orderKey)), Set(order))
    }

    func testAddAndRemoveKeepOrderCompleteAndDurable() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = AccountRegistry.Store(root: root, legacyServices: [])
        let codex = registry.add(service: .codex)
        let claude = registry.add(service: .claude)
        let work = registry.add(service: .codex)
        registry.setAccountOrder([claude.orderKey, codex.orderKey, work.orderKey])

        registry.remove(service: .codex, id: codex.id)
        let replacement = registry.add(service: .claude)

        let expected = [claude.orderKey, work.orderKey, replacement.orderKey]
        XCTAssertEqual(registry.accountOrder(), expected)

        let reopened = AccountRegistry.Store(root: root, legacyServices: [])
        XCTAssertEqual(reopened.accountOrder(), expected)
        XCTAssertEqual(Set(reopened.all().map(\.orderKey)), Set(expected))
    }

    func testInvalidOrderIsRepairedWithoutDroppingAccounts() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = AccountRegistry.Store(root: root, legacyServices: [.codex, .claude])
        let profiles = registry.all()
        let claude = try XCTUnwrap(profiles.first { $0.service == .claude })
        let codex = try XCTUnwrap(profiles.first { $0.service == .codex })

        registry.setAccountOrder([claude.orderKey, "missing\u{0}account", claude.orderKey])

        XCTAssertEqual(registry.accountOrder(), [claude.orderKey, codex.orderKey])
        XCTAssertEqual(registry.all().count, 2)
    }

    func testSuggestedPlanNameIsAppliedOnceWithoutReplacingCustomNames() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = AccountRegistry.Store(root: root, legacyServices: [])
        let first = registry.add(service: .claude)
        XCTAssertEqual(first.label, "Claude")
        registry.applySuggestedPlan(service: .claude, id: first.id, plan: "Enterprise")
        XCTAssertEqual(registry.all().first?.label, "Claude Enterprise")

        let second = registry.add(service: .claude)
        registry.applySuggestedPlan(service: .claude, id: second.id, plan: "Enterprise")
        XCTAssertEqual(registry.all().last?.label, "Claude Enterprise 2")

        registry.rename(service: .claude, id: second.id, label: "Work")
        registry.applySuggestedPlan(service: .claude, id: second.id, plan: "Pro")
        XCTAssertEqual(registry.all().last?.label, "Work")

        let reopened = AccountRegistry.Store(root: root, legacyServices: [])
        XCTAssertEqual(reopened.all().map(\.label), ["Claude Enterprise", "Work"])
    }
}


extension AccountCardOrderTests {
    func testRepeatedMovesPersistAndOrderedReadsAppendNewAccounts() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = AccountRegistry.Store(root: root, legacyServices: [])
        let codex = registry.add(service: .codex, label: "Work")
        let claude = registry.add(service: .claude, label: "Work")
        let other = registry.add(service: .codex, label: "Work")
        var order = [other.orderKey, claude.orderKey, codex.orderKey]
        for _ in 0..<6 {
            XCTAssertTrue(registry.setAccountOrder(order))
            XCTAssertFalse(registry.setAccountOrder(order), "Repeated no-op moves must not trigger refresh work")
            let reopened = AccountRegistry.Store(root: root, legacyServices: [])
            XCTAssertEqual(reopened.orderedProfiles().map(\.orderKey), order)
            order = Array(order.reversed())
        }
        let added = registry.add(service: .claude, label: "Work")
        XCTAssertEqual(registry.orderedProfiles().last?.id, added.id)
        let before = registry.accountOrder()
        registry.rename(service: .codex, id: codex.id, label: "Renamed")
        registry.setProviderIdentity(service: .codex, id: codex.id, identity: "new@example.com")
        XCTAssertEqual(registry.accountOrder(), before)
        registry.remove(service: .codex, id: other.id)
        XCTAssertEqual(registry.orderedProfiles().map(\.orderKey), before.filter { $0 != other.orderKey })
        XCTAssertEqual(registry.defaultProfile(for: .codex)?.id, codex.id)
    }
}


extension AccountCardOrderTests {
    func testOldGenericLabelsUpgradeWithoutChangingCustomNamesDefaultsOrOrder() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let old: [String: Any] = [
            "version": 2,
            "profiles": [
                ["id": "live", "service": "codex", "label": "Account 1", "isLegacy": true],
                ["id": "work", "service": "codex", "label": "Codex Pro", "isLegacy": false],
                ["id": "live", "service": "claude", "label": "Account 1", "isLegacy": true, "suggestedNamePending": false],
                ["id": "custom", "service": "claude", "label": "Family", "isLegacy": true]
            ],
            "defaults": ["codex": "work", "claude": "live"],
            "serviceOrder": ["claude", "codex"],
            "accountOrder": ["claude\u{0}custom", "codex\u{0}work", "claude\u{0}live", "codex\u{0}live"]
        ]
        try JSONSerialization.data(withJSONObject: old).write(to: root.appendingPathComponent("account-registry-v1.json"))
        let registry = AccountRegistry.Store(root: root, legacyServices: [])
        let initial = registry.all()
        XCTAssertEqual(initial.map(\.label), ["Codex", "Codex Pro", "Account 1", "Family"])
        XCTAssertEqual(initial.first?.suggestedNamePending, true)
        registry.applySuggestedPlan(service: .codex, id: "live", plan: "Unknown")
        XCTAssertEqual(registry.all().first?.label, "Codex")
        registry.applySuggestedPlan(service: .codex, id: "live", plan: "Pro")
        registry.applySuggestedPlan(service: .claude, id: "live", plan: "Max")
        registry.applySuggestedPlan(service: .claude, id: "custom", plan: "Max")
        let reopened = AccountRegistry.Store(root: root, legacyServices: [])
        XCTAssertEqual(reopened.all().map(\.label), ["Codex Pro 2", "Codex Pro", "Account 1", "Family"])
        XCTAssertEqual(reopened.defaultProfile(for: .codex)?.id, "work")
        XCTAssertEqual(reopened.defaultProfile(for: .claude)?.id, "live")
        XCTAssertEqual(reopened.accountOrder(), old["accountOrder"] as? [String])
    }
}

@MainActor
final class MobileAccountNamingTests: XCTestCase {
    func testNewAccountDoesNotBorrowExistingPlanAndNamesAfterConnection() throws {
        let accounts = MobileAccountCollection(fixtureProfiles: [
            AccountProfile(id: "existing", service: .codex, label: "Work", isLegacy: false)
        ])
        // The existing model has a known Demo plan; it must not name the new connection.
        XCTAssertEqual(accounts.suggestedName(for: .codex), "Codex")
        let added = accounts.add(.codex)
        XCTAssertEqual(added.label, "Codex")
        let connected = try XCTUnwrap(accounts.finishAdding(added))
        XCTAssertEqual(connected.label, "Codex Demo")
        accounts.rename(connected, to: "Personal")
        accounts.updateSuggestedNameIfReady(connected)
        XCTAssertEqual(accounts.all(.codex).last?.label, "Personal")
        XCTAssertEqual(accounts.all(.codex).first?.label, "Work")
    }

    func testExplicitNameMatchingPlaceholderIsPreserved() throws {
        let accounts = MobileAccountCollection(fixtureProfiles: [])
        let added = accounts.add(.claude, named: "Claude")
        XCTAssertEqual(added.suggestedNamePending, false)
        XCTAssertEqual(accounts.finishAdding(added)?.label, "Claude")
    }

    func testMissingConnectionDoesNotProceedToNaming() {
        let accounts = MobileAccountCollection(fixtureProfiles: [])
        let missing = AccountProfile(id: "cancelled", service: .codex, label: "Codex", isLegacy: false)
        XCTAssertNil(accounts.finishAdding(missing))
        XCTAssertTrue(accounts.profiles.isEmpty)
    }
}

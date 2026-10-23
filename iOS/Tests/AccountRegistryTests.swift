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

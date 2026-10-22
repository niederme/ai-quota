import XCTest
import SwiftUI
import WidgetKit

final class WidgetAccountConfigurationTests: XCTestCase {
    private let codexPersonal = AccountProfile(
        id: "codex-personal",
        service: .codex,
        label: "Personal",
        providerIdentity: "personal@example.com",
        isLegacy: false
    )
    private let codexWork = AccountProfile(
        id: "codex-work",
        service: .codex,
        label: "Work",
        providerIdentity: "member@example.com",
        isLegacy: false
    )
    private let claudeWork = AccountProfile(
        id: "claude-work",
        service: .claude,
        label: "Work",
        providerIdentity: "member@example.com",
        isLegacy: false
    )

    func testOptionsAreStrictlyFilteredToSelectedService() {
        let profiles = [codexPersonal, claudeWork, codexWork]

        let codex = WidgetAccount.options(for: .codex, profiles: profiles)
        let claude = WidgetAccount.options(for: .claude, profiles: profiles)

        XCTAssertEqual(codex.map(\.id), ["codex:codex-personal", "codex:codex-work"])
        XCTAssertTrue(codex.allSatisfy { $0.service == .codex })
        XCTAssertEqual(claude.map(\.id), ["claude:claude-work"])
        XCTAssertTrue(claude.allSatisfy { $0.service == .claude })
    }

    func testDuplicateNicknamesUseIdentityThenStableIDSuffixToStayDistinct() {
        let uniqueIdentities = WidgetAccount.make([
            codexWork,
            AccountProfile(id: "codex-other", service: .codex, label: "Work", providerIdentity: "other@example.com", isLegacy: false)
        ])
        XCTAssertEqual(uniqueIdentities.map(\.label), ["Work", "Work"])
        XCTAssertEqual(uniqueIdentities.map(\.pickerDetail), [
            "Codex · member@example.com",
            "Codex · other@example.com"
        ])

        let sameIdentity = WidgetAccount.make([
            codexWork,
            AccountProfile(id: "codex-other", service: .codex, label: "Work", providerIdentity: "member@example.com", isLegacy: false)
        ])
        XCTAssertEqual(Set(sameIdentity.map(\.pickerDetail)).count, 2)
        XCTAssertTrue(sameIdentity.allSatisfy { $0.pickerDetail.hasPrefix("Codex · account ") })
    }

    func testStableIdentitySurvivesRenameAndReorder() throws {
        let selectedID = try XCTUnwrap(WidgetAccount.make([codexPersonal, codexWork]).last).id
        var renamed = codexWork
        renamed.label = "Hearst"

        let refreshed = WidgetAccount.make([renamed, codexPersonal])

        XCTAssertEqual(selectedID, "codex:codex-work")
        XCTAssertEqual(refreshed.first?.id, selectedID)
        XCTAssertEqual(refreshed.first?.label, "Hearst")
    }

    func testOnlySoleAccountIsAutoSelected() {
        let one = WidgetAccount.make([codexPersonal])
        let multiple = WidgetAccount.make([codexPersonal, codexWork])

        XCTAssertEqual(WidgetAccount.soleDefault(in: one)?.id, "codex:codex-personal")
        XCTAssertNil(WidgetAccount.soleDefault(in: multiple))
    }

    func testAccountlessMigrationUsesPriorDefaultButInvalidExplicitSelectionDoesNotFallback() throws {
        let profiles = [codexPersonal, codexWork]
        let selected = try XCTUnwrap(WidgetAccount.make(profiles).last)

        let migrated = resolveWidgetProfile(nil, for: .codex, profiles: profiles, defaultProfile: codexPersonal)
        guard case let .selected(profile, _) = migrated else { return XCTFail("Expected migrated default") }
        XCTAssertEqual(profile.id, codexPersonal.id)

        let crossService = resolveWidgetProfile(selected, for: .claude, profiles: [claudeWork], defaultProfile: claudeWork)
        XCTAssertEqual(crossService, .unavailable)

        let removed = resolveWidgetProfile(selected, for: .codex, profiles: [codexPersonal], defaultProfile: codexPersonal)
        XCTAssertEqual(removed, .unavailable)
    }

    func testExplicitDisconnectedAccountWithoutCredentialsRequiresReconnectEvenWithCache() {
        XCTAssertTrue(widgetNeedsReconnect(
            explicitlyConfigured: true,
            reconnectFailure: false,
            hasCredentials: false,
            hasReading: false
        ))
        XCTAssertTrue(widgetNeedsReconnect(
            explicitlyConfigured: true,
            reconnectFailure: false,
            hasCredentials: false,
            hasReading: true
        ))
        XCTAssertFalse(widgetNeedsReconnect(
            explicitlyConfigured: false,
            reconnectFailure: true,
            hasCredentials: false,
            hasReading: false
        ))
        XCTAssertTrue(widgetNeedsReconnect(
            explicitlyConfigured: false,
            reconnectFailure: true,
            hasCredentials: true,
            hasReading: false
        ))
    }

    @MainActor
    func testMediumWidgetRendersDistinctAccountHeaders() throws {
        let entry = QuotaEntry(
            date: .now,
            values: [
                ProviderReading(service: .codex, reading: nil, needsApp: false),
                ProviderReading(service: .claude, reading: nil, needsApp: true)
            ],
            accountLabels: [.codex: "Personal", .claude: "Choose or reconnect"]
        )
        let content = HomeEntryView(entry: entry, both: true, previewFamily: .systemMedium)
            .frame(width: 329, height: 155)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(image.size, CGSize(width: 329, height: 155))
        let screenshot = XCTAttachment(image: image)
        screenshot.name = "Medium widget with distinct account headers"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

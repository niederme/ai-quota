import XCTest
import SwiftUI
import WidgetKit
import MobileAccessCore

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

extension WidgetAccountConfigurationTests {
    func testMixedAccountsKeepIdentityAndRankByWorstWindowWithStableTies() {
        let now = Date.now
        func account(_ id: String, short: Double, week: Double) -> WidgetAccountContent {
            .init(id: id, value: .init(service: .codex, reading: .init(fetchedAt: now,
                shortTerm: .init(usedPercent: short, durationSeconds: 18000, resetsAt: nil),
                weekly: .init(usedPercent: week, durationSeconds: 604800, resetsAt: nil)), needsApp: false), label: id)
        }
        let values = [account("personal", short: 62, week: 41), account("work", short: 10, week: 98), account("other", short: 98, week: 11),
                      WidgetAccountContent(id: "missing", value: .init(service: .claude, reading: nil, needsApp: true))]
        XCTAssertEqual(WidgetAccountOrdering.closestFirst(values).map(\.id), ["work", "other", "personal", "missing"])
        let entry = QuotaEntry(date: now, values: values.map(\.value), accountLabels: [:], accountContents: values)
        XCTAssertEqual(Set(entry.accounts.map(\.id)).count, 4)
        XCTAssertEqual(entry.accounts.map(\.name).prefix(2), ["Codex personal", "Codex work"])
        XCTAssertEqual(WidgetAccountContent(id: "named", value: values[0].value, label: "Codex Pro").name, "Codex Pro")
    }

    func testMonthlyBudgetParticipatesInClosestLimitAndReconnectHidesReset() throws {
        let now = Date.now
        let reading = try QuotaReading.decode(Data("""
        {"spend_control":{"individual_limit":{"used":660,"limit":1000,"unit":"USD"}}}
        """.utf8), now: now)
        let budget = WidgetAccountContent(id: "budget", value: .init(service: .codex, reading: reading, needsApp: false))
        XCTAssertEqual(budget.worstPercent, 66)
        XCTAssertEqual(WidgetCopy.key(reading.primaryDisplayWindow), "31d")
        let reconnect = WidgetAccountContent(id: "reconnect", value: .init(service: .codex, reading: reading, needsApp: true))
        XCTAssertEqual(reconnect.status(at: now), "Reconnect to update")
        XCTAssertFalse(reconnect.accessibility(at: now).contains(" resets "))
    }

    func testResetCopyUsesLocalCalendarAndNeverInfersPastResets() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-28T16:00:00Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        XCTAssertEqual(WidgetCopy.reset(now.addingTimeInterval(3600), at: now, calendar: calendar), "1:00 PM")
        XCTAssertEqual(WidgetCopy.reset(now.addingTimeInterval(3600), at: now, compact: true, calendar: calendar), "1P")
        XCTAssertEqual(WidgetCopy.reset(now.addingTimeInterval(86400), at: now, calendar: calendar), "Thu 12:00 PM")
        XCTAssertEqual(WidgetCopy.reset(now.addingTimeInterval(7 * 86400), at: now, calendar: calendar), "Nov 4")
        XCTAssertEqual(WidgetCopy.reset(now, at: now), "Reset unconfirmed")
        XCTAssertEqual(WidgetCopy.reset(nil, at: now), "Reset unavailable")
    }

    @MainActor
    func testRedesignedFamiliesAndStatesRenderForVisualReview() throws {
        let now = Date.now
        let rows: [[String: Any]] = (0..<7).map { offset in
            ["date": CodexUsageHistory.dateString(now.addingTimeInterval(-Double(offset) * 86400)),
             "product_surface_usage_values": ["CLI": 58.0, "IDE": 30.0, "Cloud": 12.0],
             "models": [["model": "Model A", "credits": 71.0], ["model": "Model B", "credits": 22.0], ["model": "Other", "credits": 7.0]]]
        }
        let usage = try CodexUsageHistory.decode(JSONSerialization.data(withJSONObject: ["data": rows]), now: now)
        let samples = (0..<4).map { index in
            WidgetAccountContent(id: "account-\(index)", value: .init(service: index == 1 ? .claude : .codex,
                reading: .init(fetchedAt: now,
                    shortTerm: .init(usedPercent: [62, 88, 98, 18][index], durationSeconds: 18000, resetsAt: now.addingTimeInterval(3600)),
                    weekly: .init(usedPercent: [41, 42, 56, 62][index], durationSeconds: 604800, resetsAt: now.addingTimeInterval(86400)),
                    metadata: .init(plan: "Pro", balanceUSD: nil, usageSpent: nil, usageCurrency: nil)), needsApp: false),
                label: ["Personal", "Work", "Enterprise", "Personal Workspace"][index],
                tokenHistory: DemoQuotaData.tokenHistory(now: now), usageHistory: usage)
        }
        func capture<V: View>(_ view: V, name: String, width: CGFloat, height: CGFloat) throws {
            let renderer = ImageRenderer(content: view.frame(width: width, height: height).environment(\.colorScheme, .dark))
            renderer.scale = 3
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size, CGSize(width: width, height: height))
            let attachment = XCTAttachment(image: image); attachment.name = "redesign-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("redesign-\(name).png")
            try XCTUnwrap(image.pngData()).write(to: path)
            print("REDESIGN_REVIEW " + path.path)
        }
        for (name, layout, count, width, height) in [
            ("account-small", HomeQuotaView.Layout.small, 1, 158.0, 158.0),
            ("account-medium", .singleMedium, 1, 338.0, 158.0),
            ("account-large", .accountLarge, 1, 338.0, 354.0),
            ("accounts-small", .accountsSmall, 2, 158.0, 158.0),
            ("accounts-medium", .dualMedium, 4, 338.0, 158.0),
            ("accounts-large", .large, 4, 338.0, 354.0)] {
            let accounts = Array(samples.prefix(count))
            try capture(HomeQuotaView(values: accounts.map(\.value), date: now, layout: layout, accounts: accounts).background(HomeWidgetBackground()).clipShape(RoundedRectangle(cornerRadius: 24)), name: name, width: width, height: height)
        }
        try capture(AccountLockView(account: samples[0], date: now, circular: true).background(.black), name: "lock-circular", width: 72, height: 72)
        try capture(AccountLockView(account: samples[0], date: now).background(.black), name: "lock-account", width: 160, height: 72)
        try capture(AccountsLockView(accounts: Array(samples.prefix(2)), date: now).background(.black), name: "lock-accounts", width: 160, height: 72)
        let budgetReading = QuotaReading(fetchedAt: now, shortTerm: nil, weekly: nil,
            monthlyBudget: MonthlyBudget(used: 660, limit: 1000, unit: "USD", resetsAt: now.addingTimeInterval(9 * 86400)))
        let budgetAccount = WidgetAccountContent(id: "claude:enterprise", value: .init(service: .claude, reading: budgetReading, needsApp: false), label: "Enterprise")
        try capture(HomeQuotaView(values: [budgetAccount.value], date: now, layout: .small, accounts: [budgetAccount]).background(HomeWidgetBackground()).clipShape(RoundedRectangle(cornerRadius: 24)), name: "budget", width: 158, height: 158)
        try capture(AccountLockView(account: budgetAccount, date: now, circular: true).background(.black), name: "lock-budget", width: 72, height: 72)
        let missing = WidgetAccountContent(id: "codex:missing", value: .init(service: .codex, reading: .init(fetchedAt: now, shortTerm: samples[0].value.reading?.shortTerm, weekly: nil), needsApp: false), label: "Personal")
        try capture(HomeQuotaView(values: [missing.value], date: now, layout: .small, accounts: [missing]).background(HomeWidgetBackground()), name: "missing-window", width: 158, height: 158)
        try capture(HomeQuotaView(values: samples.map(\.value), date: now, layout: .dualMedium, accounts: samples).background(HomeWidgetBackground()).environment(\.dynamicTypeSize, .accessibility3), name: "accounts-accessibility", width: 338, height: 158)
        let stale = now.addingTimeInterval(7200)
        try capture(HomeQuotaView(values: [samples[0].value], date: stale, layout: .small, accounts: [samples[0]]).background(HomeWidgetBackground()), name: "stale", width: 158, height: 158)
        let reconnect = WidgetAccountContent(id: "reconnect", value: .init(service: .codex, reading: samples[0].value.reading, needsApp: true), label: "Personal")
        try capture(HomeQuotaView(values: [reconnect.value], date: now, layout: .small, accounts: [reconnect]).background(HomeWidgetBackground()), name: "reconnect", width: 158, height: 158)
    }
}

extension WidgetAccountConfigurationTests {
    func testWeeklySplitsRetainUnattributedCreditsAndMissingDayCoverage() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-28T16:00:00Z"))
        let history = try CodexUsageHistory.decode(Data(#"{"data":[{"date":"2026-10-28","product_surface_usage_values":{"CLI":80,"IDE":20},"models":[{"model":"Model A","credits":60}]}]}"#.utf8), now: now)
        let account = WidgetAccountContent(id: "codex:work", value: .init(service: .codex, reading: nil, needsApp: false), usageHistory: history)
        let splits = WidgetWeeklySplit.make(account, at: now)
        let models = try XCTUnwrap(splits.first { $0.title == "This week by model" })
        XCTAssertEqual(models.denominator, 100)
        XCTAssertEqual(models.parts.first { $0.label == "Unattributed" }?.value, 40)
        XCTAssertEqual(models.coverage, "1/4 days")
        XCTAssertEqual(URLComponents(url: account.url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "work")
    }
}

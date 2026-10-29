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

    func testDuplicateNicknamesUseFriendlyIdentityThenNumberedChoices() {
        let uniqueIdentities = WidgetAccount.make([
            codexWork,
            AccountProfile(id: "codex-other", service: .codex, label: "Work", providerIdentity: "other@example.com", isLegacy: false)
        ])
        XCTAssertEqual(uniqueIdentities.map(\.label), ["Work", "Work"])
        XCTAssertEqual(uniqueIdentities.map(\.pickerDetail), [
            "member@example.com",
            "other@example.com"
        ])

        let sameIdentity = WidgetAccount.make([
            codexWork,
            AccountProfile(id: "codex-other", service: .codex, label: "Work", providerIdentity: "member@example.com", isLegacy: false)
        ])
        XCTAssertEqual(Set(sameIdentity.map(\.pickerDetail)).count, 2)
        XCTAssertEqual(Set(sameIdentity.map(\.pickerDetail)), Set(["Saved account 1", "Saved account 2"]))
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

extension WidgetAccountConfigurationTests {
    @MainActor func testDesignProportionsSurviveLargerWidgetFrames() throws {
        let now = Date.now
        let reading = QuotaReading(fetchedAt: now,
            shortTerm: .init(usedPercent: 26, durationSeconds: 18000, resetsAt: now.addingTimeInterval(3600)),
            weekly: .init(usedPercent: 42, durationSeconds: 604800, resetsAt: now.addingTimeInterval(86400)))
        let samples = (0..<4).map { index in
            WidgetAccountContent(id: "proportions-\(index)", value: .init(
                service: index % 2 == 0 ? .codex : .claude, reading: reading, needsApp: false), label: "Personal")
        }
        func render(_ layout: HomeQuotaView.Layout, count: Int, size: CGSize, name: String) throws -> CGRect {
            let shown = Array(samples.prefix(count))
            let view = HomeQuotaView(values: shown.map(\.value), date: now, layout: layout, accounts: shown)
                .frame(width: size.width, height: size.height).background(HomeWidgetBackground())
                .environment(\.colorScheme, .dark).environment(\.widgetRenderingMode, .fullColor)
            let renderer = ImageRenderer(content: view); renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
            let cg = try XCTUnwrap(image.cgImage)
            var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
            let context = try XCTUnwrap(CGContext(data: &pixels, width: cg.width, height: cg.height, bitsPerComponent: 8,
                bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            var minX = cg.width, minY = cg.height, maxX = 0, maxY = 0
            for y in 0..<cg.height { for x in 0..<cg.width {
                let i = (y * cg.width + x) * 4
                let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
                if r - g > 35 && b - g > 35 && max(r, b) > 100 && pixels[i + 3] > 240 {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            } }
            XCTAssertLessThan(minX, maxX)
            return CGRect(x: Double(minX) / 2, y: Double(minY) / 2,
                          width: Double(maxX - minX + 1) / 2, height: Double(maxY - minY + 1) / 2)
        }
        let cases: [(String, HomeQuotaView.Layout, Int, CGSize, CGSize)] = [
            ("account-small", .small, 1, .init(width: 158, height: 158), .init(width: 170, height: 170)),
            ("accounts-small", .accountsSmall, 2, .init(width: 158, height: 158), .init(width: 170, height: 170)),
            ("account-medium", .singleMedium, 1, .init(width: 338, height: 158), .init(width: 364, height: 170)),
            ("accounts-medium", .dualMedium, 4, .init(width: 338, height: 158), .init(width: 364, height: 170)),
            ("account-large", .accountLarge, 1, .init(width: 338, height: 354), .init(width: 364, height: 382)),
            ("accounts-large", .large, 4, .init(width: 338, height: 354), .init(width: 364, height: 382))]
        for (name, layout, count, reference, actual) in cases {
            let a = try render(layout, count: count, size: reference, name: "\(name)-reference")
            let b = try render(layout, count: count, size: actual, name: "\(name)-larger-host")
            let scale = min(actual.width / reference.width, actual.height / reference.height)
            let dx = (actual.width - reference.width * scale) / 2
            let dy = (actual.height - reference.height * scale) / 2
            XCTAssertEqual(b.minX, a.minX * scale + dx, accuracy: 2, name)
            XCTAssertEqual(b.minY, a.minY * scale + dy, accuracy: 2, name)
            XCTAssertEqual(b.width, a.width * scale, accuracy: 2, name)
            XCTAssertEqual(b.height, a.height * scale, accuracy: 2, name)
        }
    }
}


extension WidgetAccountConfigurationTests {
    @MainActor func testCompactNamesKeepSelectionAndIdentity() throws {
        var account = WidgetAccountContent(id: "codex:work-account", value: .init(service: .codex, reading: nil, needsApp: false), label: "Account With A Long Name")
        let destination = account.url
        XCTAssertEqual(account.compactName(showAccountNames: false), "Codex")
        XCTAssertEqual(account.compactName(showAccountNames: true), "Codex Account With A Long Name")
        XCTAssertTrue(account.accessibility(at: .now).contains("Account With A Long Name"))
        XCTAssertEqual(account.url, destination)
        XCTAssertEqual(account.id, "codex:work-account")
        account.label = ""
        XCTAssertEqual(account.compactName(showAccountNames: true), "Codex")
        let claude = WidgetAccountContent(id: "claude:work", value: .init(service: .claude, reading: nil, needsApp: false), label: "Claude Enterprise")
        XCTAssertEqual(claude.compactName(showAccountNames: false), "Claude")
        XCTAssertEqual(claude.compactName(showAccountNames: true), "Claude Enterprise")
        XCTAssertFalse(QuotaConfiguration().showAccountNames)
        XCTAssertFalse(BothConfiguration().showAccountNames)
        XCTAssertFalse(CompactConfiguration().showAccountNames)
    }

    @MainActor func testNamePreferenceRendersAcrossCompactFamilies() throws {
        let now = Date.now
        let reading = QuotaReading(fetchedAt: now,
            shortTerm: .init(usedPercent: 12, durationSeconds: 18000, resetsAt: now.addingTimeInterval(3600)),
            weekly: .init(usedPercent: 31, durationSeconds: 604800, resetsAt: now.addingTimeInterval(86400)))
        let accounts = QuotaService.allCases.map { service in
            WidgetAccountContent(id: "\(service.rawValue):work", value: .init(service: service, reading: reading, needsApp: false), label: "Account With A Long Name")
        }
        for show in [false, true] {
            let entry = QuotaEntry(date: now, values: accounts.map(\.value), accountLabels: [:], accountContents: accounts, showAccountNames: show)
            for both in [false, true] {
                for (family, size) in [(WidgetFamily.systemSmall, CGSize(width: 164, height: 164)), (.systemMedium, CGSize(width: 350, height: 164)), (.systemLarge, CGSize(width: 350, height: 366)), (.accessoryRectangular, CGSize(width: 160, height: 72))] {
                    let view = HomeEntryView(entry: entry, both: both, previewFamily: family)
                        .frame(width: size.width, height: size.height)
                        .background(Color(red: 0.25, green: 0.19, blue: 0.30)).foregroundStyle(.white)
                        .environment(\.colorScheme, .dark)
                    let renderer = ImageRenderer(content: view); renderer.scale = 3
                    let image = try XCTUnwrap(renderer.uiImage)
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "names-\(show)-both-\(both)-\(family)"; attachment.lifetime = .keepAlways; add(attachment)
                }
            }
        }
    }
}


extension WidgetAccountConfigurationTests {
    func testPickerUsesServiceFirstNamesWithoutBackendIdentifiers() throws {
        let profiles = [
            AccountProfile(id: "live", service: .codex, label: "Account 1", providerIdentity: "145b2756-fb5a-4da7-96bc-fe86a4b82cd5", isLegacy: true),
            AccountProfile(id: "live", service: .claude, label: "Account 1", providerIdentity: "org_03D337", isLegacy: true),
            AccountProfile(id: "codex-second", service: .codex, label: "Account 2", providerIdentity: "acct_opaque", isLegacy: false),
            AccountProfile(id: "claude-second", service: .claude, label: "Account 2", providerIdentity: "org_opaque", isLegacy: false)]
        let values = WidgetAccount.make(profiles)
        XCTAssertEqual(values.map(\.pickerTitle), ["Codex · Account 1", "Claude · Account 1", "Codex · Account 2", "Claude · Account 2"])
        XCTAssertTrue(values.allSatisfy { $0.pickerDetail.isEmpty })
        XCTAssertEqual(values.map(\.id), ["codex:live", "claude:live", "codex:codex-second", "claude:claude-second"])
        let selected = try XCTUnwrap(values.first)
        guard case let .selected(profile, _) = resolveWidgetProfile(selected, for: .codex, profiles: profiles.filter { $0.service == .codex }, defaultProfile: nil) else { return XCTFail("Selection must survive presentation cleanup") }
        XCTAssertEqual(profile.id, "live")
        let duplicates = [
            AccountProfile(id: "b", service: .codex, label: "Work", providerIdentity: "opaque-b", isLegacy: false),
            AccountProfile(id: "a", service: .codex, label: "Work", providerIdentity: "opaque-a", isLegacy: false)]
        let before = Dictionary(uniqueKeysWithValues: WidgetAccount.make(duplicates).map { ($0.id, $0.pickerDetail) })
        let after = Dictionary(uniqueKeysWithValues: WidgetAccount.make(Array(duplicates.reversed())).map { ($0.id, $0.pickerDetail) })
        XCTAssertEqual(before, after)
        XCTAssertEqual(Set(before.values), Set(["Saved account 1", "Saved account 2"]))
        let missing = WidgetAccount.make([AccountProfile(id: "live", service: .claude, label: "", isLegacy: true)])
        XCTAssertEqual(missing.first?.pickerTitle, "Claude · Account")
        XCTAssertTrue(missing.first?.pickerDetail.isEmpty == true)
        let unnamed = WidgetAccount.make([
            AccountProfile(id: "b", service: .codex, label: "", providerIdentity: "opaque", isLegacy: false),
            AccountProfile(id: "a", service: .codex, label: "live", providerIdentity: "opaque", isLegacy: true)])
        XCTAssertEqual(unnamed.map(\.pickerTitle), ["Codex · Account 2", "Codex · Account 1"])
        XCTAssertTrue(unnamed.allSatisfy { $0.pickerDetail.isEmpty })
    }

    @MainActor func testReadablePickerPreview() throws {
        let profiles = [
            AccountProfile(id: "live", service: .codex, label: "Account 1", providerIdentity: "opaque", isLegacy: true),
            AccountProfile(id: "live", service: .claude, label: "Account 1", providerIdentity: "opaque", isLegacy: true),
            AccountProfile(id: "second", service: .codex, label: "Account 2", providerIdentity: "opaque", isLegacy: false),
            AccountProfile(id: "second", service: .claude, label: "Account 2", providerIdentity: "opaque", isLegacy: false)]
        let view = VStack(alignment: .leading, spacing: 16) {
            Text("Account").font(.headline)
            ForEach(WidgetAccount.make(profiles), id: \.id) { account in
                VStack(alignment: .leading, spacing: 3) {
                    Text(account.pickerTitle).font(.body)
                    if !account.pickerDetail.isEmpty { Text(account.pickerDetail).font(.caption).foregroundStyle(.secondary) }
                }
            }
            Divider()
            HStack { Text("Use account names"); Spacer(); Image(systemName: "switch.2") }
                .font(.body)
        }.padding(20).frame(width: 300).foregroundStyle(.white).background(Color(white: 0.16))
        let renderer = ImageRenderer(content: view); renderer.scale = 3
        let attachment = XCTAttachment(image: try XCTUnwrap(renderer.uiImage)); attachment.name = "Readable account picker proposal"; attachment.lifetime = .keepAlways; add(attachment)
    }
}


extension WidgetAccountConfigurationTests {
    func testMissingSavedSelectionPreservesStableIdentifier() async throws {
        let identifier = "codex:removed-widget-account"
        let result = try await WidgetAccountQuery().entities(for: [identifier])
        XCTAssertEqual(result.first?.id, identifier)
        XCTAssertEqual(result.first?.profileID, "removed-widget-account")
        XCTAssertEqual(result.first?.pickerTitle, "Codex · Choose or reconnect")
        XCTAssertEqual(result.first?.pickerDetail, "Reconnect in AIQuota")
    }
}

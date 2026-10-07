import XCTest
import MobileAccessCore
@testable import AIQuota_iOS

private actor BackgroundCalls {
    var services: [QuotaService] = []
    func record(_ service: QuotaService) { services.append(service) }
    func count() -> Int { services.count }
}

@MainActor final class BackgroundRefreshTests: XCTestCase {
    func testRefreshesBothServicesAndReschedulesOnce() async {
        let calls = BackgroundCalls()
        var schedules = 0, reloads = 0, completions: [Bool] = []
        let done = expectation(description: "completed")
        let run = BackgroundRefreshRun(services: QuotaService.allCases, reschedule: { schedules += 1 },
            refresh: { await calls.record($0) }, reload: { reloads += 1 },
            complete: { completions.append($0); done.fulfill() })
        run.start(); run.start()
        await fulfillment(of: [done], timeout: 2)
        run.expire()
        let count = await calls.count()
        XCTAssertEqual(count, 2)
        XCTAssertEqual(schedules, 1); XCTAssertEqual(reloads, 1); XCTAssertEqual(completions, [true])
    }
    func testProviderFailureDoesNotPreventOtherProviderOrSavedStateReload() async {
        let calls = BackgroundCalls()
        var completions: [Bool] = [], reloads = 0, schedules = 0
        let done = expectation(description: "completed")
        let run = BackgroundRefreshRun(services: QuotaService.allCases, reschedule: { schedules += 1 },
            refresh: { service in
                await calls.record(service)
                if service == .claude { throw ClaudeAccessError.requestFailed(stage: "usage update", status: 429) }
            }, reload: { reloads += 1 }, complete: { completions.append($0); done.fulfill() })
        run.start()
        await fulfillment(of: [done], timeout: 2)
        let count = await calls.count()
        XCTAssertEqual(count, 2); XCTAssertEqual(schedules, 1)
        XCTAssertEqual(reloads, 1); XCTAssertEqual(completions, [false])
    }
    func testExpirationCancelsWorkAndCompletesOnlyOnceWithoutClaimingSuccess() async {
        let started = expectation(description: "request started")
        let cancelled = expectation(description: "request cancelled")
        var schedules = 0, reloads = 0, completions: [Bool] = []
        let run = BackgroundRefreshRun(services: [.claude], reschedule: { schedules += 1 },
            refresh: { _ in
                started.fulfill()
                do { try await Task.sleep(for: .seconds(10)) }
                catch { cancelled.fulfill(); throw error }
            }, reload: { reloads += 1 }, complete: { completions.append($0) })
        run.start()
        await fulfillment(of: [started], timeout: 2)
        run.expire(); run.expire(); run.start()
        await fulfillment(of: [cancelled], timeout: 2)
        XCTAssertEqual(schedules, 1); XCTAssertEqual(reloads, 0); XCTAssertEqual(completions, [false])
    }
    func testNoConnectedServicesDoesNotFetchOrReload() async {
        var reloads = 0
        let done = expectation(description: "completed")
        let run = BackgroundRefreshRun(services: [], reschedule: {}, refresh: { _ in XCTFail("Unexpected request") },
            reload: { reloads += 1 }, complete: { XCTAssertTrue($0); done.fulfill() })
        run.start()
        await fulfillment(of: [done], timeout: 2)
        XCTAssertEqual(reloads, 0)
    }
    func testOnlyAppHasBackgroundConfiguration() throws {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String], [MobileBackgroundRefresh.identifier])
        XCTAssertTrue((Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []).contains("fetch"))
    }
}

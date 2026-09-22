import XCTest
@testable import MobileAccessCore

final class CodexResetAnnouncementTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-09-22T12:00:00Z")!
    private func response(type: String = "regular", scheduled: String = "\"2026-09-23T06:59:00.000Z\"",
                          announced: String = "2026-09-22T04:31:32.000Z",
                          generated: String = "2026-09-22T11:59:00.000Z", status: String = "scheduled",
                          completed: String = "null", hasScheduled: Bool = true, watch: String = "null") throws -> CodexResetStatus {
        let event = """
        {"id":"announcement-1","status":"\(status)","reset_type":"\(type)","announced_at":"\(announced)",
        "scheduled_for":\(scheduled),"source":{"type":"x_post","author":"thsottiaux","url":"https://x.com/thsottiaux/status/1"}}
        """
        return try CodexResetStatus.decode(Data("""
        {"data":{"scheduled_reset":\(hasScheduled ? event : "null"),"latest_reset":\(completed),
        "active_watch":\(watch)},
        "meta":{"api_version":"v1","generated_at":"\(generated)"}}
        """.utf8))
    }
    func testUpcomingAnnouncementsAndEmptyStatus() throws {
        XCTAssertEqual(try response().announcement(at: now)?.title, "Codex usage reset announced")
        XCTAssertNil(try response(hasScheduled: false).announcement(at: now))
        XCTAssertNil(try response(status: "cancelled").announcement(at: now))
        XCTAssertNil(try response(type: "unknown").announcement(at: now))
    }
    func testBankedCreditIsNotDescribedAsAutomaticReset() throws {
        XCTAssertEqual(try response(type: "banked").announcement(at: now)?.title, "Codex reset credit announced")
    }
    func testExpiredMissingAndFarFutureDeadlinesAreBounded() throws {
        XCTAssertNil(try response(scheduled: "\"2026-09-22T12:00:00Z\"").announcement(at: now))
        XCTAssertNotNil(try response(scheduled: "null").announcement(at: now))
        XCTAssertNil(try response(scheduled: "null", announced: "2026-09-21T11:00:00Z").announcement(at: now))
        XCTAssertNil(try response(scheduled: "\"2026-10-01T00:00:00Z\"", announced: "2026-09-18T00:00:00Z").announcement(at: now))
    }
    func testStaleAndFutureResponsesAreHidden() throws {
        XCTAssertNil(try response(generated: "2026-09-22T11:29:00Z").announcement(at: now))
        XCTAssertNil(try response(generated: "2026-09-22T12:06:00Z").announcement(at: now))
        XCTAssertNil(try response(announced: "2026-09-22T13:00:00Z").announcement(at: now))
    }
    func testExecutedAnnouncementIsRemovedWithoutChangingAccountQuota() throws {
        let completed = """
        {"id":"execution-2","reset_type":"regular","announced_at":"2026-09-22T11:00:00Z"}
        """
        XCTAssertNil(try response(completed: completed).announcement(at: now))
        // An unrelated regular reset does not mean a new banked credit was granted.
        XCTAssertNotNil(try response(type: "banked", completed: completed).announcement(at: now))
    }
    func testDismissalAppliesOnlyToThatAnnouncement() throws {
        let status = try response()
        XCTAssertNil(status.announcement(at: now, dismissedID: "announcement-1"))
        XCTAssertNotNil(status.announcement(at: now, dismissedID: "previous-announcement"))
    }

    func testHintsRequireTiboPostAndExpire() throws {
        func hint(author: String = "thsottiaux", expiry: String = "2026-09-22T18:00:00Z") -> String {
            """
            {"level":"strong","observed_at":"2026-09-22T11:00:00Z","expires_at":"\(expiry)",
            "source":{"type":"x_post","author":"\(author)","url":"https://x.com/\(author)/status/123"}}
            """
        }
        let status = try response(hasScheduled: false, watch: hint())
        XCTAssertEqual(status.announcement(at: now)?.title, "Codex usage may reset soon")
        XCTAssertNil(status.announcement(at: now, dismissedID: "hint-https://x.com/thsottiaux/status/123"))
        XCTAssertNil(try response(hasScheduled: false, watch: hint(author: "someoneelse")).announcement(at: now))
        XCTAssertNil(try response(hasScheduled: false, watch: hint(expiry: "2026-09-22T12:00:00Z")).announcement(at: now))
        XCTAssertEqual(try response(watch: hint()).announcement(at: now)?.title, "Codex usage reset announced")
    }
    func testMalformedDateFailsClosed() {
        XCTAssertThrowsError(try response(generated: "not-a-date"))
    }
}

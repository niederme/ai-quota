import Testing
import Foundation
@testable import AIQuotaKit

@Suite("CodexUsage model")
struct CodexUsageModelTests {
    @Test("decodes WHAM usage with newer optional account fields")
    func decodesNewerWhamUsageShape() throws {
        let data = Data("""
        {
          "user_id": "user-1",
          "account_id": "account-1",
          "email": "person@example.com",
          "plan_type": "plus",
          "rate_limit": {
            "allowed": true,
            "limit_reached": false,
            "primary_window": {
              "used_percent": 4,
              "limit_window_seconds": 18000,
              "reset_after_seconds": 13070,
              "reset_at": 1779424096
            },
            "secondary_window": {
              "used_percent": 35,
              "limit_window_seconds": 604800,
              "reset_after_seconds": 511008,
              "reset_at": 1779922034
            }
          },
          "code_review_rate_limit": null,
          "additional_rate_limits": null,
          "credits": {
            "has_credits": true,
            "unlimited": false,
            "overage_limit_reached": false,
            "balance": "289.3924237500",
            "approx_local_messages": [72, 376],
            "approx_cloud_messages": [12, 72]
          },
          "spend_control": {
            "reached": false
          },
          "rate_limit_reset_credits": {
            "available_count": 0,
            "can_reset": false
          }
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let raw = try decoder.decode(WhamUsageResponse.self, from: data)
        let usage = CodexUsage(from: raw)

        #expect(usage.planType == "plus")
        #expect(usage.hourlyUsedPercent == 4)
        #expect(usage.weeklyUsedPercent == 35)
        #expect(usage.hourlyWindowSeconds == 18000)
        #expect(usage.creditBalance == 289.39242375)
        #expect(usage.approxLocalMessages == [72, 376])
        #expect(usage.approxCloudMessages == [12, 72])
    }

    @Test("keeps partial Codex data when rate windows are missing")
    func keepsPartialDataWhenWindowsMissing() throws {
        let data = Data("""
        {
          "plan_type": "pro",
          "rate_limit": {
            "allowed": true,
            "limit_reached": false,
            "primary_window": null,
            "secondary_window": null
          },
          "credits": {
            "has_credits": true,
            "unlimited": false,
            "balance": 42.5
          }
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let raw = try decoder.decode(WhamUsageResponse.self, from: data)
        let usage = CodexUsage(from: raw)

        #expect(usage.planType == "pro")
        #expect(usage.allowed)
        #expect(!usage.limitReached)
        #expect(usage.hourlyUsedPercent == 0)
        #expect(usage.weeklyUsedPercent == 0)
        #expect(usage.creditBalance == 42.5)
    }

    @Test("lossily decodes numeric Codex window fields")
    func lossilyDecodesNumericWindowFields() throws {
        let data = Data("""
        {
          "plan_type": "plus",
          "rate_limit": {
            "allowed": true,
            "limit_reached": false,
            "primary_window": {
              "used_percent": "7",
              "limit_window_seconds": "18000",
              "reset_after_seconds": "1200",
              "reset_at": "1779424096"
            },
            "secondary_window": null
          },
          "credits": null
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let raw = try decoder.decode(WhamUsageResponse.self, from: data)
        let usage = CodexUsage(from: raw)

        #expect(usage.hourlyUsedPercent == 7)
        #expect(usage.hourlyWindowSeconds == 18000)
        #expect(usage.hourlyResetAfterSeconds == 1200)
    }

    @Test("totals current-month Codex bonus credit events")
    func totalsCurrentMonthBonusCreditEvents() throws {
        let data = Data("""
        {
          "data": [
            {
              "date": "2026-06-26",
              "product_surface": "desktop_app",
              "credit_amount": 20.78305
            },
            {
              "date": "2026-06-01",
              "product_surface": "unknown",
              "credit_amount": 4.21695
            },
            {
              "date": "2026-05-31",
              "product_surface": "desktop_app",
              "credit_amount": 99
            }
          ]
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let raw = try decoder.decode(CodexCreditUsageEventsResponse.self, from: data)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let total = raw.monthToDateTotal(
            asOf: Date(timeIntervalSince1970: 1_781_899_200), // 2026-06-15 00:00:00 UTC
            calendar: calendar
        )

        #expect(total == 25)
    }
}

import Foundation

public enum DevinAccessError: Error, LocalizedError, Sendable {
    case invalidResponse
    case noWindows

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "Unexpected response from Devin."
        case .noWindows: "Devin reported no quota windows."
        }
    }
}

/// Wire surface for Devin's seat-management `GetUserStatus` call — the same
/// endpoint the Devin CLI and desktop app use to render daily/weekly quota.
/// Undocumented and subject to change; decode is deliberately tolerant of
/// absent fields and of numbers arriving as JSON strings.
public enum DevinAPI {
    /// Fallback when `credentials.toml` does not carry an `api_server_url`.
    public static let defaultAPIServerURL = URL(string: "https://server.codeium.com")!

    public static let getUserStatusPath = "/exa.seat_management_pb.SeatManagementService/GetUserStatus"

    /// Connect-RPC JSON POST used by the installed Devin clients.
    public static func userStatusRequest(apiServerURL: URL, apiKey: String) -> URLRequest {
        var request = URLRequest(url: apiServerURL.appendingPathComponent(getUserStatusPath))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        let body: [String: Any] = [
            "metadata": [
                "apiKey": apiKey,
                "ideName": "devin",
                "ideVersion": "1.108.2",
                "extensionName": "devin",
                "extensionVersion": "1.108.2",
                "locale": "en",
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Decodes a `GetUserStatus` response into a `DevinUsage`.
    /// Percentages arrive as *remaining* and are flipped to *used* here.
    public static func decodeUserStatus(_ data: Data, now: Date, source: DevinUsage.Source) throws -> DevinUsage {
        let raw = try JSONDecoder().decode(UserStatusResponse.self, from: data)
        guard let planStatus = raw.userStatus?.planStatus else { throw DevinAccessError.noWindows }

        func usedPercent(_ remaining: Double?) -> Double? {
            remaining.map { min(100, max(0, 100 - $0)) }
        }

        let daily = usedPercent(planStatus.dailyQuotaRemainingPercent?.value)
        let weekly = usedPercent(planStatus.weeklyQuotaRemainingPercent?.value)
        guard daily != nil || weekly != nil else { throw DevinAccessError.noWindows }

        let micros = planStatus.overageBalanceMicros?.value
        let overageUSD = micros.map { $0 / 1_000_000 }.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }

        return DevinUsage(
            dailyUsedPercent: daily,
            dailyResetsAt: planStatus.dailyQuotaResetAtUnix?.value.map { Date(timeIntervalSince1970: $0) },
            weeklyUsedPercent: weekly,
            weeklyResetsAt: planStatus.weeklyQuotaResetAtUnix?.value.map { Date(timeIntervalSince1970: $0) },
            planName: planStatus.planInfo?.planName,
            accountDisplayName: planStatus.planInfo?.devinInfo?.accountDisplayName,
            overageBalanceUSD: overageUSD,
            planStart: planStatus.planStart.flatMap(isoDate),
            planEnd: planStatus.planEnd.flatMap(isoDate),
            source: source,
            fetchedAt: now
        )
    }

    /// Maps a Devin reading onto the shared `QuotaReading` shape used by the
    /// analytics views: daily quota → shortTerm slot, weekly quota → weekly slot.
    public static func makeReading(from usage: DevinUsage) -> QuotaReading {
        var shortTerm: QuotaWindow?
        if let used = usage.dailyUsedPercent {
            shortTerm = QuotaWindow(usedPercent: used, durationSeconds: 86400, resetsAt: usage.dailyResetsAt)
        }
        var weekly: QuotaWindow?
        if let used = usage.weeklyUsedPercent {
            weekly = QuotaWindow(usedPercent: used, durationSeconds: 604800, resetsAt: usage.weeklyResetsAt)
        }
        let metadata = AccountMetadata(
            plan: usage.planName,
            balanceUSD: usage.overageBalanceUSD,
            usageSpent: nil,
            usageCurrency: usage.overageBalanceUSD != nil ? "USD" : nil
        )
        return QuotaReading(fetchedAt: usage.fetchedAt, shortTerm: shortTerm, weekly: weekly, metadata: metadata)
    }

    private static func isoDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

// MARK: - Wire types

private struct UserStatusResponse: Decodable {
    let userStatus: UserStatus?

    struct UserStatus: Decodable {
        let planStatus: PlanStatus?
    }

    struct PlanStatus: Decodable {
        let planInfo: PlanInfo?
        let planStart: String?
        let planEnd: String?
        let availablePromptCredits: MetadataNumber?
        let dailyQuotaRemainingPercent: MetadataNumber?
        let weeklyQuotaRemainingPercent: MetadataNumber?
        let overageBalanceMicros: MetadataNumber?
        let dailyQuotaResetAtUnix: MetadataNumber?
        let weeklyQuotaResetAtUnix: MetadataNumber?
    }

    struct PlanInfo: Decodable {
        let planName: String?
        let billingStrategy: String?
        let monthlyPromptCredits: MetadataNumber?
        let devinInfo: DevinInfo?
    }

    struct DevinInfo: Decodable {
        let orgId: String?
        let accountDisplayName: String?
        let webappHost: String?
        let apiUrl: String?
    }
}

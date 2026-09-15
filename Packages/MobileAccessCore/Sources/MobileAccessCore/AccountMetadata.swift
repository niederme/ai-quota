import Foundation

public struct AccountMetadata: Codable, Sendable, Equatable {
    public let plan: String?
    public var displayPlan: String? {
        plan.map { $0.lowercased() == "prolite" ? "Pro" : $0.capitalized }
    }
    public let balanceUSD: Double?
    public let usageSpent: Double?
    public let usageCurrency: String?
    public init(plan: String?, balanceUSD: Double?, usageSpent: Double?, usageCurrency: String?) {
        self.plan = plan?.isEmpty == false ? plan : nil
        self.balanceUSD = balanceUSD.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.usageSpent = usageSpent.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.usageCurrency = usageCurrency
    }
}

/// Optional provider metadata must not prevent otherwise valid quota readings.
struct MetadataNumber: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let number = (try? c.decode(Double.self)) ?? (try? c.decode(String.self)).flatMap(Double.init)
        value = number.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }
}

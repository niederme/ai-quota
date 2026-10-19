import Foundation

/// The Devin session credential used by mobile targets.
/// `apiServerURL` is stored as a string because `URL` is awkward inside
/// `QuotaCredentials`-style Codable payloads shared across processes.
public struct DevinTokens: Codable, Sendable, Equatable {
    public let apiKey: String
    public let apiServerURL: String

    public init(apiKey: String, apiServerURL: String = "https://server.codeium.com") {
        self.apiKey = apiKey
        self.apiServerURL = apiServerURL
    }

    public var serverURL: URL {
        URL(string: apiServerURL) ?? DevinAPI.defaultAPIServerURL
    }
}

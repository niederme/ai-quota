import Foundation

/// Fire-and-forget GA4 Measurement Protocol client.
/// All sends are silent no-ops when `enabled` is false or `Analytics.plist` is absent.
actor AnalyticsClient {
    static let shared = AnalyticsClient()

    private let firebaseAppID: String?
    private let apiSecret: String?
    private let instanceID: String

    private init() {
        if let url = Bundle.main.url(forResource: "Analytics", withExtension: "plist"),
           let plist = NSDictionary(contentsOf: url) {
            firebaseAppID = plist["FirebaseAppID"] as? String
            apiSecret = plist["APISecret"] as? String
        } else {
            firebaseAppID = nil
            apiSecret = nil
        }

        let key = "analytics.instanceId"
        if let existing = UserDefaults.standard.string(forKey: key) {
            instanceID = existing
        } else {
            let new = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            UserDefaults.standard.set(new, forKey: key)
            instanceID = new
        }
    }

    func send(_ eventName: String, params: [String: String] = [:], enabled: Bool) async {
        guard enabled,
              let appID = firebaseAppID,
              let secret = apiSecret else { return }

        var components = URLComponents(string: "https://www.google-analytics.com/mp/collect")!
        components.queryItems = [
            URLQueryItem(name: "firebase_app_id", value: appID),
            URLQueryItem(name: "api_secret", value: secret)
        ]
        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "app_instance_id": instanceID,
            "events": [["name": eventName, "params": params]]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        request.httpBody = data

        _ = try? await URLSession.shared.data(for: request)
    }
}

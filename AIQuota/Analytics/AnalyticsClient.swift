import Foundation
import OSLog
import FirebaseCore
import FirebaseAnalytics

/// Shared analytics facade.
///
/// If a local `GoogleService-Info.plist` is present in the app bundle, events are
/// routed through Firebase Analytics Core. Otherwise the app falls back to the
/// existing Measurement Protocol transport so current instrumentation keeps
/// working until the Firebase app config is added locally.
final class AnalyticsClient: @unchecked Sendable {
    static let shared = AnalyticsClient()

    private enum Backend {
        case undetermined
        case firebase
        case measurementProtocol
        case none
    }

    private let logger = Logger(subsystem: "com.niederme.AIQuota", category: "Analytics")
    private let fallbackTransport = MeasurementProtocolTransport()
    private let stateQueue = DispatchQueue(label: "com.niederme.AIQuota.analytics")

    private var backend: Backend = .undetermined
    private var collectionEnabled = false

    private init() {}

    func bootstrap(initialCollectionEnabled enabled: Bool) {
        stateQueue.sync {
            collectionEnabled = enabled
            configureIfNeededLocked()
            applyCollectionSettingLocked()
        }
    }

    func setCollectionEnabled(_ enabled: Bool) {
        stateQueue.sync {
            collectionEnabled = enabled
            configureIfNeededLocked()
            applyCollectionSettingLocked()
        }
    }

    func send(_ eventName: String, params: [String: String] = [:], enabled: Bool) async {
        let backend = stateQueue.sync { () -> Backend in
            collectionEnabled = enabled
            configureIfNeededLocked()
            applyCollectionSettingLocked()
            return enabled ? self.backend : .none
        }

        switch backend {
        case .firebase:
            let parameters = params.reduce(into: [String: Any]()) { partialResult, pair in
                partialResult[pair.key] = pair.value
            }
            Analytics.logEvent(eventName, parameters: parameters.isEmpty ? nil : parameters)
        case .measurementProtocol:
            await fallbackTransport.send(eventName, params: params, enabled: true)
        case .none, .undetermined:
            return
        }
    }

    private func configureIfNeededLocked() {
        guard backend == .undetermined else { return }

        if Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil {
            if FirebaseApp.app() == nil {
                FirebaseApp.configure()
            }
            backend = .firebase
            logger.notice("Analytics backend: Firebase")
            return
        }

        if fallbackTransport.isConfigured {
            backend = .measurementProtocol
            logger.notice("Analytics backend: Measurement Protocol fallback")
            return
        }

        backend = .none
        logger.notice("Analytics backend unavailable: no Firebase or fallback configuration")
    }

    private func applyCollectionSettingLocked() {
        guard backend == .firebase else { return }

        Analytics.setAnalyticsCollectionEnabled(collectionEnabled)
        Analytics.setUserProperty("NO", forName: AnalyticsUserPropertyAllowAdPersonalizationSignals)
    }
}

private final class MeasurementProtocolTransport {
    private let logger = Logger(subsystem: "com.niederme.AIQuota", category: "AnalyticsFallback")
    private let firebaseAppID: String?
    private let apiSecret: String?
    private let instanceID: String

    var isConfigured: Bool {
        firebaseAppID != nil && apiSecret != nil
    }

    init() {
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

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200 ..< 300).contains(httpResponse.statusCode) {
                logger.error("Measurement Protocol send failed for \(eventName, privacy: .public) with status \(httpResponse.statusCode)")
            }
        } catch {
            logger.error("Measurement Protocol send failed for \(eventName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

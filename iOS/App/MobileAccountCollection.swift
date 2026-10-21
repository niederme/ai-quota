import Foundation
import Observation
import WidgetKit

/// Keeps one model per local connection. The registry is shared with widgets, while
/// models and in-flight requests stay private to the app process.
@MainActor @Observable
final class MobileAccountCollection {
    private(set) var profiles: [AccountProfile] = []
    private var codexModels: [String: ProbeModel] = [:]
    private var claudeModels: [String: ClaudeProbeModel] = [:]
    let setupCodex: ProbeModel
    let setupClaude: ClaudeProbeModel
    private let fixtureMode: Bool

    init(fixtureProfiles: [AccountProfile]? = nil) {
        fixtureMode = fixtureProfiles != nil
        setupCodex = ProbeModel(isDemo: fixtureMode)
        setupClaude = ClaudeProbeModel(isDemo: fixtureMode)
        if let fixtureProfiles {
            profiles = fixtureProfiles
            for profile in fixtureProfiles {
                switch profile.service {
                case .codex:
                    codexModels[profile.id] = ProbeModel(isDemo: true, profile: profile)
                case .claude:
                    claudeModels[profile.id] = ClaudeProbeModel(isDemo: true, profile: profile)
                }
            }
        } else { reload() }
    }

    func reload() {
        guard !fixtureMode else { return }
        let current = AccountRegistry.all()
        for profile in current {
            switch profile.service {
            case .codex:
                if codexModels[profile.id] == nil {
                    codexModels[profile.id] = profile.isLegacy ? setupCodex : ProbeModel(profile: profile)
                }
            case .claude:
                if claudeModels[profile.id] == nil {
                    claudeModels[profile.id] = profile.isLegacy ? setupClaude : ClaudeProbeModel(profile: profile)
                }
            }
        }
        let codexIDs = Set(current.filter { $0.service == .codex }.map(\.id))
        let claudeIDs = Set(current.filter { $0.service == .claude }.map(\.id))
        codexModels = codexModels.filter { codexIDs.contains($0.key) }
        claudeModels = claudeModels.filter { claudeIDs.contains($0.key) }
        profiles = current
    }

    func all(_ service: QuotaService) -> [AccountProfile] {
        profiles.filter { $0.service == service }
    }

    func connected(_ service: QuotaService) -> [AccountProfile] {
        all(service).filter { profile in
            switch service {
            case .codex: codex(profile)?.connected == true
            case .claude: claude(profile)?.connected == true
            }
        }
    }

    var hasConnection: Bool {
        !connected(.codex).isEmpty || !connected(.claude).isEmpty
    }

    func codex(_ profile: AccountProfile) -> ProbeModel? { codexModels[profile.id] }
    func claude(_ profile: AccountProfile) -> ClaudeProbeModel? { claudeModels[profile.id] }

    @discardableResult func add(_ service: QuotaService) -> AccountProfile {
        if fixtureMode {
            let profile = AccountProfile(id: UUID().uuidString, service: service,
                                         label: "Account \(all(service).count + 1)", isLegacy: false)
            profiles.append(profile)
            if service == .codex { codexModels[profile.id] = ProbeModel(isDemo: true, profile: profile) }
            else { claudeModels[profile.id] = ClaudeProbeModel(isDemo: true, profile: profile) }
            return profile
        }
        let profile = AccountRegistry.add(service: service)
        reload()
        return profile
    }

    func rename(_ profile: AccountProfile, to label: String) {
        if fixtureMode {
            if let index = profiles.firstIndex(where: { $0.service == profile.service && $0.id == profile.id }) {
                profiles[index].label = label
            }
            return
        }
        AccountRegistry.rename(service: profile.service, id: profile.id, label: label)
        reload()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func setDefault(_ profile: AccountProfile) {
        guard !fixtureMode else { return }
        AccountRegistry.setDefault(service: profile.service, id: profile.id)
        reload()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func remove(_ profile: AccountProfile) async throws {
        if fixtureMode {
            profiles.removeAll { $0.service == profile.service && $0.id == profile.id }
            return
        }
        switch profile.service {
        case .codex: try await codex(profile)?.resetForNewUser()
        case .claude: try await claude(profile)?.resetForNewUser()
        }
        AccountRegistry.remove(service: profile.service, id: profile.id)
        reload()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func discardIfUnconnected(_ profile: AccountProfile) {
        guard !fixtureMode else { return }
        guard profile.id != "live" else { return }
        let connected = profile.service == .codex ? codex(profile)?.connected == true : claude(profile)?.connected == true
        guard !connected else { return }
        AccountRegistry.remove(service: profile.service, id: profile.id)
        reload()
    }

    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for profile in connected(.codex) {
                if let model = codex(profile) { group.addTask { await model.refreshAndWait() } }
            }
            for profile in connected(.claude) {
                if let model = claude(profile) { group.addTask { await model.refreshAndWait() } }
            }
        }
    }

    func refreshOnOpen() {
        for profile in connected(.codex) { codex(profile)?.refreshOnOpen() }
        for profile in connected(.claude) { claude(profile)?.refreshOnOpen() }
    }
}

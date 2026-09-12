#if APP_STORE
import Foundation

/// TestFlight and App Store builds receive updates through Apple.
@MainActor
@Observable
final class UpdaterViewModel {
    var availableUpdateVersion: String? { nil }
    func checkForUpdates() { }
}
#else
import Foundation
import Sparkle

/// Thin @Observable wrapper around SPUUpdater so SwiftUI views can
/// bind to updater state and trigger checks.
@MainActor
@Observable
final class UpdaterViewModel {
    private var updater: SPUUpdater?

    var canCheckForUpdates: Bool = false
    var availableUpdateVersion: String?

    init(updater: SPUUpdater? = nil) {
        self.updater = updater
        canCheckForUpdates = updater?.canCheckForUpdates ?? false
    }

    func connect(to updater: SPUUpdater) {
        self.updater = updater
        canCheckForUpdates = updater.canCheckForUpdates
    }

    func checkForUpdates() {
        updater?.checkForUpdates()
    }

    func noteAvailableUpdate(version: String) {
        availableUpdateVersion = version
    }

    func clearAvailableUpdate() {
        availableUpdateVersion = nil
    }

    var automaticallyChecksForUpdates: Bool {
        get { updater?.automaticallyChecksForUpdates ?? false }
        set { updater?.automaticallyChecksForUpdates = newValue }
    }
}

#endif

import Foundation
import Sparkle

/// Thin @Observable wrapper around SPUUpdater so SwiftUI views can
/// bind to updater state and trigger checks.
@MainActor
@Observable
final class UpdaterViewModel {
    private let updater: SPUUpdater

    var canCheckForUpdates: Bool = false

    init(updater: SPUUpdater) {
        self.updater = updater
        canCheckForUpdates = updater.canCheckForUpdates
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }
}

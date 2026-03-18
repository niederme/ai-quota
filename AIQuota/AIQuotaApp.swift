import SwiftUI
import Sparkle
import AIQuotaKit

@main
struct AIQuotaApp: App {
    @State private var viewModel = QuotaViewModel()

    // Sparkle updater — must be held at app scope for its lifetime
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(viewModel)
                .environment(UpdaterViewModel(updater: updaterController.updater))
        } label: {
            MenuBarIconView(usage: viewModel.usage, isLoading: viewModel.isLoading)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(viewModel)
                .environment(UpdaterViewModel(updater: updaterController.updater))
        }
    }
}

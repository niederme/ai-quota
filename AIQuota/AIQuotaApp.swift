import SwiftUI
import AIQuotaKit

@main
struct AIQuotaApp: App {
    @State private var viewModel = QuotaViewModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(viewModel)
        } label: {
            MenuBarIconView(usage: viewModel.usage, isLoading: viewModel.isLoading)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(viewModel)
        }
    }
}

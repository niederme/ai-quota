import SwiftUI
import AIQuotaKit

struct MenuBarStepView: View {
    @Environment(QuotaViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "menubar.rectangle")
                .font(.system(size: 38))
                .foregroundStyle(Color.brand)
            Text("Which accounts do you want in your menu bar?")
                .font(.title2.bold())
            Text("We selected up to two to start. You can choose more, or leave them all off to show the AIQuota icon.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(AccountRegistry.orderedAccounts()) { account in
                        Toggle(
                            "\(account.provider == .codex ? "Codex" : "Claude Code") · \(account.displayLabel)",
                            isOn: Binding(
                                get: { vm.settings.menuBarAccountIDs?.contains(account.id) ?? false },
                                set: { enabled in
                                    var ids = vm.settings.menuBarAccountIDs ?? []
                                    if enabled && !ids.contains(account.id) { ids.append(account.id) }
                                    if !enabled { ids.removeAll { $0 == account.id } }
                                    vm.settings.menuBarAccountIDs = ids
                                    vm.saveSettings()
                                }
                            )
                        )
                    }
                    if AccountRegistry.accounts().isEmpty {
                        Text("Connect an account first, or make this choice later in Settings.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
            .frame(maxHeight: 270)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            Text("You can change this anytime in Settings. Reordering cards in the panel will not change these choices.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 440, alignment: .leading)
        .padding(36)
    }
}

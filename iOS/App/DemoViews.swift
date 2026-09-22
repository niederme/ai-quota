import SwiftUI

private struct DemoActionKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable (Bool) -> Void = { DemoQuotaData.setEnabled($0) }
}
extension EnvironmentValues {
    var setDemoEnabled: @MainActor @Sendable (Bool) -> Void {
        get { self[DemoActionKey.self] }
        set { self[DemoActionKey.self] = newValue }
    }
}

struct DemoBanner: View {
    @Environment(\.setDemoEnabled) private var setDemoEnabled
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Demo", systemImage: "sparkles").font(.headline)
                Text("Sample usage for Codex and Claude.").font(.subheadline)
                    .foregroundStyle(OverviewStyle.secondary)
            }
            Spacer(minLength: 0)
            Button("Exit demo") { setDemoEnabled(false) }
                .buttonStyle(.bordered)
        }
        .padding(16)
        .background(OverviewStyle.track, in: RoundedRectangle(cornerRadius: OverviewStyle.radius))
    }
}

struct DemoAccountView: View {
    @Environment(\.setDemoEnabled) private var setDemoEnabled
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Sample account", systemImage: "person.crop.circle").font(.title2.bold())
            Text("This usage is generated for the demo. Exit demo to sign in or return to your saved accounts.")
                .foregroundStyle(OverviewStyle.secondary)
            Button("Exit demo") { setDemoEnabled(false) }
                .modifier(OnboardingPrimaryButtonStyle())
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { BrandSurfaceBackground().ignoresSafeArea() }
        .navigationTitle("Demo account")
    }
}

/// Session-only controls let reviewers explore notification settings without permission prompts.
struct DemoNotificationsView: View {
    var body: some View {
        ScrollView { DemoNotificationControls().padding(24) }
            .background { BrandSurfaceBackground().ignoresSafeArea() }
            .navigationTitle("Demo notifications")
            .tint(OverviewStyle.accent)
    }
}
struct DemoNotificationControls: View {
    @State private var enabled = true
    @State private var codex = true
    @State private var claude = true
    @State private var nearLimit = true
    @State private var threshold = 85.0
    @State private var reset = true
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Demo settings are temporary. No notifications will be sent.")
                    .foregroundStyle(OverviewStyle.secondary)
                Toggle("Enable notifications", isOn: $enabled)
            }
            if enabled {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Services").font(.headline)
                    Toggle("Codex", isOn: $codex)
                    Toggle("Claude Code", isOn: $claude)
                }
                VStack(alignment: .leading, spacing: 16) {
                    Text("Sample alerts").font(.headline)
                    Toggle("Approaching the limit", isOn: $nearLimit)
                    if nearLimit { Stepper("At least \(Int(threshold))% used", value: $threshold, in: 5...95, step: 5) }
                    Toggle("Reset reminders", isOn: $reset)
                }
            }
        }
        .tint(OverviewStyle.accent)
    }
}

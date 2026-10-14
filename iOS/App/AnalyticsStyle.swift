import SwiftUI

// Analytics cards are shared by the iOS sheet and Mac menu bar detail view.
#if os(iOS)
typealias AnalyticsStyle = OverviewStyle
#else
enum AnalyticsStyle {
    static let primary = Color.primary
    static let secondary = Color.secondary
    static let accent = Color.gaugeAccent
    static let warning = Color.warningAmber
    static let track = Color.secondary.opacity(0.12)
}

struct AnalyticsHoverButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverLabel(configuration: configuration)
    }

    private struct HoverLabel: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovered = false
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .frame(minWidth: 36, minHeight: 36)
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .background {
                    RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                        .foregroundStyle(.primary)
                        .opacity(enabled && (hovered || configuration.isPressed) ? 1 : 0)
                }
                .onHover { hovered = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
        }
    }
}
#endif

struct AnalyticsDetailSurface: ViewModifier {
    let title: String
    @Environment(\.dismiss) private var dismiss
    func body(content: Content) -> some View {
        #if os(iOS)
        content.background { BrandSurfaceBackground().ignoresSafeArea() }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        #else
        // MenuBarExtra has no standard window toolbar to host the native
        // navigation back control, so keep category navigation in the content.
        content.navigationTitle(title)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Button { dismiss() } label: {
                            Label("Back to analytics", systemImage: "chevron.left")
                        }.buttonStyle(AnalyticsHoverButtonStyle())
                        Spacer(minLength: 8)
                        Text(title).font(.headline).lineLimit(2)
                    }.padding(.horizontal, 16).padding(.vertical, 12)
                    Divider()
                }.background(.regularMaterial)
            }
        #endif
    }
}

func analyticsFreshnessLabel(_ fetchedAt: Date, at now: Date, saved: Bool) -> String {
    let elapsed = max(0, Int(now.timeIntervalSince(fetchedAt)))
    let relative = elapsed < 60 ? "just now" : elapsed < 3600 ? "\(elapsed / 60) minute\(elapsed / 60 == 1 ? "" : "s") ago" : "\(elapsed / 3600) hour\(elapsed / 3600 == 1 ? "" : "s") ago"
    if saved { return "Last updated \(relative)" }
    if elapsed >= 1800 { return "Older reading · \(relative)" }
    return "Updated \(relative)"
}

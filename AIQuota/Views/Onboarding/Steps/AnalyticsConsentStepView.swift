import SwiftUI
import ServiceManagement

struct AnalyticsConsentStepView: View {
    @Environment(QuotaViewModel.self) private var viewModel

    private let privacyPolicyURL = URL(string: "https://aiquota.app/privacy/")!

    var body: some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
            AnalyticsTrustIllustration()
                .frame(height: 164)
                .padding(.horizontal, 36)
                .padding(.top, 24)

            VStack(alignment: .leading, spacing: 0) {
                Text("Optional")
                    .font(.caption.weight(.bold))
                    .foregroundColor(Color.brand)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.brand.opacity(0.12))
                    .clipShape(Capsule())
                    .padding(.bottom, 12)

                Text("Help John improve AIQuota")
                    .font(.system(size: 29, weight: .bold))
                    .padding(.bottom, 6)

                Text("Share a few anonymous usage signals. No prompts or personal info.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.top, 18)

            consentCard(isEnabled: $vm.settings.analyticsEnabled)
                .padding(.horizontal, 36)
                .padding(.top, 20)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(trustPoints) { point in
                    TrustPointRow(point: point)
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 16)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: viewModel.settings) { viewModel.saveSettings() }
    }

    private func consentCard(isEnabled: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: isEnabled) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Help John improve AIQuota with anonymous usage analytics")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Installs, active use, and setup completion only.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.trailing, 16)
            }
            .toggleStyle(.switch)

            Divider()
                .overlay(Color.secondary.opacity(0.12))

            LaunchAtLoginToggle()

            Divider()
                .overlay(Color.secondary.opacity(0.12))

            Link(destination: privacyPolicyURL) {
                Label("Read the Privacy Policy", systemImage: "lock.shield")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(Color.brand)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private let trustPoints: [TrustPoint] = [
        TrustPoint(id: "anonymous", icon: "lock.shield.fill", title: "Anonymous only"),
        TrustPoint(id: "default-off", icon: "power.circle.fill", title: "Off by default"),
        TrustPoint(id: "settings", icon: "gearshape.fill", title: "Change anytime in Settings"),
    ]
}

private struct AnalyticsTrustIllustration: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.brand.opacity(0.16),
                            Color.brand.opacity(0.07),
                            Color.white.opacity(0.02),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .frame(width: 224, height: 108)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.white.opacity(0.44))
                                .frame(width: 6, height: 6)
                            Circle()
                                .fill(Color.white.opacity(0.24))
                                .frame(width: 6, height: 6)
                            Circle()
                                .fill(Color.white.opacity(0.14))
                                .frame(width: 6, height: 6)
                        }

                        AnalyticsLineShape()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.brand.opacity(0.95), Color.white.opacity(0.72)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                            )
                            .frame(width: 150, height: 46)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
                .offset(x: -18, y: 10)

            Circle()
                .strokeBorder(Color.brand.opacity(0.18), lineWidth: 10)
                .frame(width: 112, height: 112)
                .offset(x: 76, y: -8)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.brand.opacity(0.98), Color.brand.opacity(0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 78, height: 78)
                .shadow(color: Color.brand.opacity(0.2), radius: 18, y: 8)
                .overlay {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .offset(x: 76, y: -8)
        }
    }
}

private struct TrustPointRow: View {
    let point: TrustPoint

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: point.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.brand)
                .frame(width: 28, height: 28)
                .background(Color.brand.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(point.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary.opacity(0.92))

            Spacer(minLength: 0)
        }
    }
}

private struct TrustPoint: Identifiable {
    let id: String
    let icon: String
    let title: String
}

private struct AnalyticsLineShape: Shape {
    func path(in rect: CGRect) -> Path {
        let points = [
            CGPoint(x: rect.minX, y: rect.maxY * 0.78),
            CGPoint(x: rect.width * 0.24, y: rect.height * 0.58),
            CGPoint(x: rect.width * 0.42, y: rect.height * 0.68),
            CGPoint(x: rect.width * 0.62, y: rect.height * 0.36),
            CGPoint(x: rect.maxX, y: rect.height * 0.18),
        ]

        var path = Path()
        path.move(to: points[0])

        for index in 1..<points.count {
            path.addLine(to: points[index])
        }

        return path
    }
}

// AIQuota/Views/Onboarding/Steps/WidgetsStepView.swift
import SwiftUI

struct WidgetsStepView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Promo image
            Group {
                if let img = NSImage(named: "WidgetPromo") {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    WidgetImagePlaceholder()
                }
            }
            .frame(height: 180)
            .padding(.horizontal, 32)
            .padding(.top, 24)

            // Content block
            VStack(alignment: .leading, spacing: 0) {
                // "Bonus!" badge
                Text("Bonus!")
                    .font(.caption.weight(.bold))
                    .foregroundColor(Color.brand)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.brand.opacity(0.12))
                    .clipShape(Capsule())
                    .padding(.bottom, 8)

                // Title
                Text("Add the AIQuota widget")
                    .font(.title2).fontWeight(.bold)
                    .padding(.bottom, 4)

                // Subtitle
                Text("See your quota at a glance on your desktop.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 20)

                // Divider
                Divider()
                    .padding(.bottom, 16)

                // Steps
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(instructions, id: \.step) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text("\(item.step)")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.white)
                                .frame(width: 20, height: 20)
                                .background(Color.brand)
                                .clipShape(Circle())

                            Text((try? AttributedString(markdown: item.text)) ?? AttributedString(item.text))
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.top, 20)

            Spacer()
        }
    }

    private struct Instruction {
        let step: Int
        let text: String
    }

    private let instructions: [Instruction] = [
        Instruction(step: 1, text: "Right-click on your desktop and choose **Edit Widgets…**"),
        Instruction(step: 2, text: "Search for **AIQuota** in the widget gallery"),
        Instruction(step: 3, text: "Drag a widget onto your desktop and click **Done**"),
    ]
}

// MARK: - Placeholder

private struct WidgetImagePlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.secondary.opacity(0.08))
            .overlay(
                VStack(spacing: 10) {
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("Widget screenshot")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                }
            )
    }
}

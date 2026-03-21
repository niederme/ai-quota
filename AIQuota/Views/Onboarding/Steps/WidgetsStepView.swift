// AIQuota/Views/Onboarding/Steps/WidgetsStepView.swift
import SwiftUI

struct WidgetsStepView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Image: use asset "WidgetPromo" if available, else show placeholder
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
            .frame(height: 200)
            .padding(.horizontal, 36)
            .padding(.top, 28)

            Spacer().frame(height: 24)

            // Instructions
            VStack(alignment: .leading, spacing: 14) {
                // "Bonus!" badge + title
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bonus!")
                        .font(.caption.weight(.bold))
                        .foregroundColor(Color.brand)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Color.brand.opacity(0.12))
                        .clipShape(Capsule())

                    Text("Add the AIQuota widget")
                        .font(.title2).fontWeight(.bold)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("See your quota at a glance on your desktop.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Divider()
                    .padding(.vertical, 4)

                ForEach(instructions, id: \.step) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(item.step)")
                            .font(.footnote.weight(.bold))
                            .foregroundColor(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.brand)
                            .clipShape(Circle())

                        Text((try? AttributedString(markdown: item.text)) ?? AttributedString(item.text))
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 36)

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
            .fill(Color.secondary.opacity(0.1))
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("Widget screenshot")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            )
    }
}

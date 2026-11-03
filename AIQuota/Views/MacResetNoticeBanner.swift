import SwiftUI
import WebKit

/// Shared account surface for either one alert or the ordered announcement/forecast pair.
struct MacAlertGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.overviewGlass)
                    .overlay(alignment: .top) { Color.overviewGlassHighlight.frame(height: 1) }
                    .clipShape(RoundedRectangle(cornerRadius: 24))
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Alerts")
            .accessibilityRepresentation {
                List { content }.accessibilityLabel("Alerts")
            }
    }
}

struct MacAlertRow<Detail: View>: View {
    let title: String
    let announcement: Bool
    var indentsForecast = true
    let onDismiss: () -> Void
    @ViewBuilder let detail: Detail

    @ViewBuilder private var headline: some View {
        if announcement {
            Text(title)
        } else if indentsForecast {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("🧭").font(.system(size: 12)).frame(width: 14)
                Text(title)
            }
        } else {
            Text("\(Text("🧭").font(.system(size: 12))) \(title)")
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if announcement {
                Image(systemName: "info.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.overviewAccent)
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                headline.fontWeight(.semibold).foregroundStyle(Color.overviewPrimary)
                detail.foregroundStyle(Color.overviewSecondary)
                    .padding(.leading, !announcement && indentsForecast ? 18 : 0)
            }
            .font(.system(size: 13))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: 32, height: 16)
                .overlay(alignment: .top) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.overviewTertiary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .offset(y: -8)
                    .accessibilityLabel(announcement ? "Dismiss reset announcement" : "Dismiss limit forecast")
                }
        }
        .padding(.leading, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text(announcement ? "Dismiss reset announcement" : "Dismiss limit forecast"), onDismiss)
    }
}

struct MacResetNoticeBanner: View {
    let title: String
    let onReadMore: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        MacAlertRow(title: title, announcement: true, onDismiss: onDismiss) {
            Button(action: onReadMore) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("Read more on Codex Resets")
                    Image(systemName: "arrow.up.right").accessibilityHidden(true)
                }.foregroundStyle(Color.overviewAccent)
            }
            .buttonStyle(.plain)
        }
        .accessibilityAction { onReadMore() }
    }
}

/// Public announcement details stay in the app, without sharing provider sessions.
struct MacResetDetailsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Codex Resets").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding()
            Divider()
            Browser()
        }.frame(width: 600, height: 560)
    }

    private struct Browser: NSViewRepresentable {
        func makeNSView(context: Context) -> WKWebView {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let view = WKWebView(frame: .zero, configuration: configuration)
            view.load(URLRequest(url: URL(string: "https://codex-resets.com/")!))
            return view
        }
        func updateNSView(_ view: WKWebView, context: Context) {}
    }
}

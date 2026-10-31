import SwiftUI
import MobileAccessCore

@MainActor @Observable
final class CodexResetNotice {
    static let dismissalKey = "codexResetNotice.dismissedID"
    static let website = URL(string: "https://codex-resets.com/")!
    // Fixed sample shown independently of the live tracker and its expiry rules.
    static let demoAnnouncement: CodexResetAnnouncement = {
        let data = Data("""
        {"id":"demo-codex-reset","status":"scheduled","reset_type":"regular",
         "announced_at":"2026-01-01T12:00:00Z","scheduled_for":"2026-01-01T18:00:00Z",
         "source":{"type":"demo","author":null,"url":null}}
        """.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode(CodexResetAnnouncement.self, from: data)
    }()
    private(set) var status: CodexResetStatus?
    private var checkedAt = Date.now
    private var nextFetch = Date.distantPast
    private(set) var fetching = false
    private let session: URLSession

    init(session: URLSession? = nil, initialStatus: CodexResetStatus? = nil) {
        status = initialStatus
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.urlCredentialStorage = nil
            self.session = URLSession(configuration: configuration)
        }
    }

    func refresh(at now: Date = .now) async {
        checkedAt = now
        guard !fetching, now >= nextFetch else { return }
        fetching = true
        nextFetch = now.addingTimeInterval(15 * 60)
        defer { fetching = false }
        do {
            // Public data only. Never send provider credentials or account details.
            var request = URLRequest(url: URL(string: "https://codex-resets.com/api/v1/status")!,
                                     cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpShouldHandleCookies = false
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { status = nil; return }
            if response.statusCode == 429,
               let retry = response.value(forHTTPHeaderField: "Retry-After"),
               let seconds = TimeInterval(retry), seconds.isFinite, seconds > 0 {
                nextFetch = now.addingTimeInterval(max(15 * 60, seconds))
            }
            guard response.statusCode == 200 else { status = nil; return }
            let decoded = try CodexResetStatus.decode(data)
            try Task.checkCancellation()
            status = decoded
        } catch {
            // An unavailable tracker is not an account error. Hide quietly.
            status = nil
            if Task.isCancelled { nextFetch = .distantPast }
        }
    }

    func announcement(dismissedID: String) -> CodexResetAnnouncement? {
        status?.announcement(at: checkedAt, dismissedID: dismissedID)
    }
}

/// One flat account surface, with native trailing swipe actions for each alert.
struct OverviewAlerts: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    let announcement: CodexResetAnnouncement?
    var forecast: QuotaExhaustionForecast? = nil
    var accountLabel = ""
    var wide = false
    var loading = false
    let openDetails: () -> Void
    let dismissAnnouncement: () -> Void
    var dismissForecast: () -> Void = {}

    private var rowIDs: [String] {
        (announcement.map { ["announcement-" + $0.id] } ?? [])
            + (forecast.map { ["forecast-" + $0.scope.accountID + "-" + String($0.scope.resetAt.timeIntervalSince1970)] } ?? [])
    }

    var body: some View {
        if !rowIDs.isEmpty {
            // The noninteractive sizing copy gives this short, non-scrolling List
            // its intrinsic height inside the overview ScrollView, including at AX sizes.
            VStack(spacing: 0) {
                ForEach(rowIDs, id: \.self) { id in row(id) }
            }
            .hidden()
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            .overlay {
                List {
                    ForEach(rowIDs, id: \.self) { id in
                        row(id)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("Dismiss", systemImage: "xmark", role: .destructive) {
                                    dismiss(id)
                                }
                                .disabled(id.hasPrefix("announcement-") && loading)
                            }
                    }
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 0)
                .contentMargins(.all, 0, for: .scrollContent)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .accessibilityLabel("Alerts")
                .accessibilityIdentifier("overviewAlerts")
            }
            .background { OverviewAccountSurface() }
            .clipShape(RoundedRectangle(cornerRadius: OverviewStyle.accountRadius))
            .animation(reduceMotion ? nil : .default, value: rowIDs)
        }
    }

    @ViewBuilder private func row(_ id: String) -> some View {
        VStack(spacing: 0) {
            if id.hasPrefix("announcement-"), let announcement {
                OverviewAlertRow(title: announcement.title, detail: "Read more on Codex Resets",
                    announcement: true, wide: wide, loading: loading,
                    openDetails: openDetails, dismiss: { dismiss(id) })
            } else if let forecast {
                OverviewAlertRow(title: "\(accountLabel) may hit its \(forecast.scope.window.label) limit",
                    detail: QuotaForecastTextFormatter.detail(forecast),
                    announcement: false, wide: wide, dismiss: { dismiss(id) })
                    .accessibilityIdentifier("quotaPaceInsight")
            }
            if id != rowIDs.last {
                OverviewStyle.overviewTrack.frame(height: 1 / displayScale)
                    .padding(.leading, 50).accessibilityHidden(true)
            }
        }
    }

    private func dismiss(_ id: String) {
        withAnimation(reduceMotion ? nil : .default) {
            if id.hasPrefix("announcement-") { dismissAnnouncement() }
            else { dismissForecast() }
        }
    }
}

struct OverviewAlertRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var compactTitleLine = 20.0
    @ScaledMetric(relativeTo: .headline) private var wideTitleLine = 22.0
    let title: String
    let detail: String
    let announcement: Bool
    var wide = false
    var loading = false
    var openDetails: () -> Void = {}
    let dismiss: () -> Void

    private var isWide: Bool { wide && !typeSize.isAccessibilitySize }
    private var titleLine: CGFloat { isWide ? wideTitleLine : compactTitleLine }
    private var dismissalLabel: String { announcement ? "Dismiss reset announcement" : "Dismiss limit forecast" }

    @ViewBuilder var body: some View {
        if announcement {
            content.accessibilityAction { if !loading { openDetails() } }
        } else {
            content
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: announcement ? "info.circle" : "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundStyle(announcement ? OverviewStyle.accent : OverviewStyle.warning)
                .frame(width: 22, height: titleLine)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(isWide ? .headline : .subheadline.weight(.semibold))
                    .foregroundStyle(OverviewStyle.primary)
                if announcement {
                    Button(action: openDetails) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(detail)
                            Image(systemName: "arrow.up.right").accessibilityHidden(true)
                        }
                        .foregroundStyle(OverviewStyle.accent)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("resetAnnouncementDetails")
                } else {
                    Text(detail).foregroundStyle(OverviewStyle.secondary)
                }
            }
            .font(isWide ? .subheadline : .footnote)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Reserve a full target while centering the glyph on the first title line.
            Color.clear.frame(width: 44, height: titleLine)
                .overlay(alignment: .top) {
                    Button(action: dismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(OverviewStyle.tertiary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .offset(y: (titleLine - 44) / 2)
                    .accessibilityLabel(dismissalLabel)
                }
        }
        .padding(.leading, 16)
        .padding(.vertical, 11)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title + ". " + detail)
        .accessibilityAction(named: Text(dismissalLabel), dismiss)
        .modifier(UsageLoadingState(loading: loading, label: "Updating reset announcement"))
    }
}

/// Single-announcement entry point used by the demo and isolated previews.
struct CodexResetNoticeBanner: View {
    let announcement: CodexResetAnnouncement
    let openDetails: () -> Void
    let dismiss: () -> Void
    var loading = false
    var wide = false

    var body: some View {
        OverviewAlerts(announcement: announcement, wide: wide, loading: loading,
                       openDetails: openDetails, dismissAnnouncement: dismiss)
    }
}

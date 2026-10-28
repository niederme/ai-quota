import SwiftUI
import WidgetKit
import MobileAccessCore
import CoreText

/// Stable identity is an account, not a service: several dials may be Codex.
struct WidgetAccountContent: Identifiable, Sendable {
    let id: String
    let value: ProviderReading
    var label: String = ""
    var tokenHistory: CodexTokenHistory?
    var usageHistory: CodexUsageHistory?

    var name: String {
        let service = value.service.name
        guard !label.isEmpty else { return service }
        if label.caseInsensitiveCompare(service) == .orderedSame || label.lowercased().hasPrefix(service.lowercased() + " ") { return label }
        return "\(service) \(label)"
    }
    var url: URL {
        let prefix = value.service.rawValue + ":"
        guard id.hasPrefix(prefix) else { return value.service.url }
        let profileID = String(id.dropFirst(prefix.count))
        guard !profileID.isEmpty, profileID != "empty" else { return value.service.url }
        var components = URLComponents(url: value.service.url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "account", value: profileID)]
        return components.url ?? value.service.url
    }
    var worstPercent: Double? {
        let percentages = (value.reading?.windows.map(\.usedPercent) ?? []) + (value.reading?.monthlyBudget.map { [$0.usedPercent] } ?? [])
        return percentages.max()
    }
    func isSaved(at date: Date) -> Bool {
        WidgetReadingStatus.isSaved(value.reading, needsApp: value.needsApp, updateFailed: value.updateFailed, at: date)
    }
    func status(at date: Date, compact: Bool = false) -> String {
        if value.needsApp { return "Reconnect to update" }
        guard let reading = value.reading else { return "Not connected" }
        if reading.metadata?.plan == "Demo" { return "Sample usage" }
        if isSaved(at: date) { return WidgetCopy.olderReading(reading, at: date) }
        if (worstPercent ?? 0) >= 95 { return "Limit reached" }
        if let budget = reading.budgetOnly { return "Spent \(WidgetCopy.amount(budget.used, budget: budget)) of \(WidgetCopy.amount(budget.limit, budget: budget))" }
        guard let window = reading.windows.max(by: { $0.usedPercent < $1.usedPercent }) else { return "No reading yet" }
        return WidgetCopy.reset(window.resetsAt, at: date, compact: compact)
    }
    func accessibility(at date: Date) -> String {
        var parts = [name, value.reading?.accessibilitySummary ?? "Allowance unavailable", status(at: date)]
        if !value.needsApp, !isSaved(at: date) {
            for window in value.reading?.windows ?? [] {
                if let reset = window.resetsAt, reset > date {
                    parts.append("\(window.label) resets \(reset.formatted(date: .complete, time: .shortened))")
                }
            }
            if let reset = value.reading?.budgetOnly?.resetsAt, reset > date {
                parts.append("Monthly resets \(reset.formatted(date: .complete, time: .shortened))")
            }
        }
        return parts.joined(separator: ". ")
    }
}

enum WidgetAccountOrdering {
    static func closestFirst(_ accounts: [WidgetAccountContent]) -> [WidgetAccountContent] {
        accounts.enumerated().sorted {
            let lhs = $0.element.worstPercent ?? -1, rhs = $1.element.worstPercent ?? -1
            return lhs == rhs ? $0.offset < $1.offset : lhs > rhs
        }.map(\.element)
    }
}

enum WidgetCopy {
    static func amount(_ value: Double, budget: MonthlyBudget) -> String {
        if let code = budget.unit?.uppercased(), code.count == 3, code.allSatisfy({ $0 >= "A" && $0 <= "Z" }) {
            return value.formatted(.currency(code: code).precision(.fractionLength(0...2)))
        }
        return budget.amountText(value)
    }
    static func key(_ window: QuotaWindow?) -> String {
        guard let window else { return "" }
        return window.label == "Monthly" ? "31d" : window.compactLabel
    }
    static func metric(_ window: QuotaWindow?) -> String {
        guard let window else { return "N/A" }
        return "\(Int(window.usedPercent.rounded()))% \(key(window))"
    }
    static func reset(_ reset: Date?, at date: Date, compact: Bool = false,
                      calendar: Calendar = .autoupdatingCurrent) -> String {
        guard let reset, reset.timeIntervalSince1970.isFinite,
              reset.timeIntervalSince1970 < 253402300800 else { return "Reset unavailable" }
        guard reset > date else { return "Reset unconfirmed" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: reset)).day ?? 0
        if days >= 7 { formatter.dateFormat = "MMM d" }
        else if compact {
            formatter.dateFormat = (days == 0 ? "" : "EEE ") + (calendar.component(.minute, from: reset) == 0 ? "ha" : "h:mma")
            return formatter.string(from: reset).replacingOccurrences(of: "AM", with: "A").replacingOccurrences(of: "PM", with: "P")
        } else { formatter.dateFormat = (days == 0 ? "" : "EEE ") + "h:mm a" }
        return formatter.string(from: reset)
    }
    static func olderReading(_ reading: QuotaReading, at date: Date) -> String {
        let elapsed = date.timeIntervalSince(reading.fetchedAt)
        guard elapsed.isFinite else { return "Older reading" }
        let seconds = max(0, min(315360000, elapsed))
        let age: String
        if seconds < 60 { age = "just now" }
        else if seconds < 3600 { let n = Int(seconds / 60); age = "\(n) minute\(n == 1 ? "" : "s") ago" }
        else if seconds < 86400 { let n = Int(seconds / 3600); age = "\(n) hour\(n == 1 ? "" : "s") ago" }
        else { let n = Int(seconds / 86400); age = "\(n) day\(n == 1 ? "" : "s") ago" }
        return "Older reading · \(age)"
    }
}

/// Current overview tokens. Home widgets always use the dark plum surface;
/// vibrant/tinted appearances use primary ink and convey warnings with a glyph.
enum WidgetPalette {
    static let accent = Color(red: 191/255, green: 90/255, blue: 242/255)
    static let reset = Color(red: 215/255, green: 126/255, blue: 247/255)
    static let secondary = Color(red: 154/255, green: 152/255, blue: 162/255)
    static let track = Color(red: 118/255, green: 118/255, blue: 128/255).opacity(0.30)
    static let heat: [Color] = [Color(red: 82/255, green: 48/255, blue: 107/255), Color(red: 120/255, green: 69/255, blue: 156/255), Color(red: 163/255, green: 84/255, blue: 207/255), Color(red: 196/255, green: 107/255, blue: 240/255)]
    static func tint(_ account: WidgetAccountContent, at date: Date) -> Color {
        guard account.value.reading != nil, !account.isSaved(at: date) else { return secondary }
        let worst = account.worstPercent ?? 0
        return worst >= 95 ? Color(red: 1, green: 69/255, blue: 58/255) : worst >= 85 ? Color(red: 1, green: 159/255, blue: 10/255) : accent
    }
}

private final class WidgetResourceAnchor: NSObject {}

struct AccountWidgetDial: View {
    let account: WidgetAccountContent
    let date: Date
    let size: CGFloat
    var readings = true
    var compact = false
    var vibrant = false
    var curvedCaption = false
    private var reading: QuotaReading? { account.value.reading }
    private var two: Bool { reading == nil || reading?.shortTerm != nil || (reading?.windows.count ?? 0) > 1 }
    private var ink: Color { vibrant ? .primary : WidgetPalette.tint(account, at: date) }
    private var caption: String {
        guard !account.value.needsApp else { return "Reconnect" }
        guard let reading else { return "Not connected" }
        if account.isSaved(at: date) { return "Older reading" }
        guard let worst = reading.windows.max(by: { $0.usedPercent < $1.usedPercent }) ?? reading.primaryDisplayWindow else { return "N/A" }
        if two { return WidgetCopy.metric(worst) }
        guard let reset = worst.resetsAt, reset > date else { return WidgetCopy.metric(worst) }
        return "\(Int(worst.usedPercent.rounded()))% · \(WidgetCopy.key(worst)) \(WidgetCopy.reset(reset, at: date, compact: true))"
    }
    var body: some View {
        ZStack {
            ring(reading?.primaryDisplayWindow, radius: two ? 0.45 : (compact && size <= 60 ? 0.425 : 0.44), stroke: two ? 0.065 : 0.097)
            if two { ring(reading?.secondaryWindow, radius: 0.37, stroke: 0.065).opacity(vibrant ? 0.6 : 0.7) }
            if curvedCaption {
                CurvedWidgetText(text: caption, size: size, radius: size * (two ? 0.25 : 0.28))
                    .foregroundStyle(ink).accessibilityHidden(true)
            }
            VStack(spacing: size * 0.03) {
                glyph
                if readings && !account.value.needsApp {
                    VStack(spacing: 0) {
                        if two {
                            Text(reading?.primaryWindow.map(WidgetCopy.metric) ?? "N/A 5h")
                            Text(reading?.secondaryWindow.map(WidgetCopy.metric) ?? "N/A 7d").opacity(0.7)
                        } else {
                            Text(reading?.primaryDisplayWindow.map { "\(Int($0.usedPercent.rounded()))%" } ?? "N/A")
                            Text(WidgetCopy.key(reading?.primaryDisplayWindow)).opacity(0.7)
                        }
                    }
                    .font(.system(size: size * 0.121, weight: .medium)).monospacedDigit().lineLimit(1)
                }
            }
            .foregroundStyle(ink)
            .offset(y: readings ? -size * 0.035 : (curvedCaption ? size * 0.04 : 0))
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if account.isSaved(at: date) && !account.value.needsApp {
                Image(systemName: "clock.fill").font(.system(size: max(9, size * 0.10))).foregroundStyle(vibrant ? Color.primary.opacity(0.6) : WidgetPalette.secondary)
            }
        }
        .widgetAccentable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(account.accessibility(at: date))
    }
    @ViewBuilder private var glyph: some View {
        let glyphSize = size * (readings ? 0.145 : curvedCaption ? 0.24 : 0.30)
        if account.value.needsApp {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: glyphSize))
        } else if reading?.metadata?.plan == "Demo" {
            Text("Demo").font(.system(size: size * 0.13, weight: .medium))
        } else {
            Image(account.value.service.logo, bundle: Bundle(for: WidgetResourceAnchor.self)).renderingMode(.template).resizable().scaledToFit().frame(width: glyphSize, height: glyphSize)
        }
    }
    private func ring(_ window: QuotaWindow?, radius: CGFloat, stroke: CGFloat) -> some View {
        ZStack {
            Circle().trim(from: 0, to: 0.75)
                .stroke(vibrant ? Color.primary.opacity(0.20) : WidgetPalette.track, style: StrokeStyle(lineWidth: size * stroke, lineCap: .butt, dash: window == nil || account.value.needsApp ? [2, 3] : []))
            if let window, !account.value.needsApp {
                Circle().trim(from: 0, to: 0.75 * min(1, max(0, window.usedPercent / 100)))
                    .stroke(ink, style: StrokeStyle(lineWidth: size * stroke, lineCap: .butt))
            }
        }
        .rotationEffect(.degrees(135))
        .frame(width: size * radius * 2, height: size * radius * 2)
    }
}

/// Core Text shaping preserves SF kerning, then positions the shaped glyphs on
/// a top-centred arc. The entire run scales together to a maximum 160° sweep.
struct CurvedWidgetText: View {
    let text: String
    let size: CGFloat
    let radius: CGFloat
    var body: some View {
        Canvas { context, bounds in
            let font = CTFontCreateWithName(".AppleSystemUIFont" as CFString, size * 0.115, nil)
            let attributed = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                .kern: size * 0.115 * 0.08
            ])
            let line = CTLineCreateWithAttributedString(attributed)
            let length = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            guard length > 0 else { return }
            let scale = min(1, radius * .pi * 160 / 180 / length)
            context.withCGContext { cg in
                cg.setFillColor(Color.primary.resolve(in: context.environment).cgColor)
                for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                    let count = CTRunGetGlyphCount(run)
                    var glyphs = [CGGlyph](repeating: 0, count: count)
                    var positions = [CGPoint](repeating: .zero, count: count)
                    var advances = [CGSize](repeating: .zero, count: count)
                    CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                    CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
                    CTRunGetAdvances(run, CFRange(location: 0, length: 0), &advances)
                    let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
                    for index in 0..<count {
                        let mid = (positions[index].x + advances[index].width / 2 - length / 2) * scale
                        let angle = mid / radius
                        cg.saveGState()
                        cg.translateBy(x: bounds.width / 2 + sin(angle) * radius, y: bounds.height / 2 - cos(angle) * radius)
                        cg.rotate(by: angle)
                        cg.scaleBy(x: scale, y: -scale)
                        var glyph = glyphs[index]
                        var origin = CGPoint(x: -advances[index].width / 2, y: 0)
                        CTFontDrawGlyphs(runFont, &glyph, &origin, 1, cg)
                        cg.restoreGState()
                    }
                }
            }
        }.frame(width: size, height: size)
    }
}

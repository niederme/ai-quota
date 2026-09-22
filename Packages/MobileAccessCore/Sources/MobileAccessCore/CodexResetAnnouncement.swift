import Foundation

/// Public announcements are separate from the user's quota and personal reset times.
public struct CodexResetAnnouncement: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let status: String
    public let reset_type: String
    public let announced_at: Date
    public let scheduled_for: Date?
    public let source: Source

    public struct Source: Decodable, Sendable, Equatable {
        public let type: String
        public let author: String?
        public let url: String?

        var isTiboPost: Bool {
            guard type == "x_post", author == "thsottiaux", let url, let link = URL(string: url) else { return false }
            return link.scheme == "https" && ["x.com", "twitter.com"].contains(link.host)
                && link.path.hasPrefix("/thsottiaux/status/")
        }
    }

    public var title: String {
        if status == "hint" { return "Codex usage may reset soon" }
        return reset_type == "banked" ? "Codex reset credit announced" : "Codex usage reset announced"
    }

    public var expiresAt: Date {
        // A passed deadline is not completion evidence. Simply stop promoting it.
        min(scheduled_for ?? announced_at.addingTimeInterval(24 * 3600),
            announced_at.addingTimeInterval(72 * 3600))
    }
}

public struct CodexResetStatus: Decodable, Sendable {
    public struct Payload: Decodable, Sendable {
        public let scheduled_reset: CodexResetAnnouncement?
        public let latest_reset: CompletedReset?
        public let active_watch: Watch?
    }
    public struct Watch: Decodable, Sendable {
        public let level: String
        public let observed_at: Date
        public let expires_at: Date
        public let source: CodexResetAnnouncement.Source
    }
    public struct CompletedReset: Decodable, Sendable {
        public let id: String
        public let reset_type: String
        public let announced_at: Date
    }
    public struct Metadata: Decodable, Sendable {
        public let api_version: String
        public let generated_at: Date
    }
    public let data: Payload
    public let meta: Metadata

    public func announcement(at now: Date, dismissedID: String? = nil) -> CodexResetAnnouncement? {
        guard meta.api_version == "v1",
              now.timeIntervalSince(meta.generated_at) >= -300,
              now.timeIntervalSince(meta.generated_at) < 30 * 60 else { return nil }
        if let scheduled = data.scheduled_reset {
            guard scheduled.status == "scheduled",
              ["regular", "banked"].contains(scheduled.reset_type),
              scheduled.source.isTiboPost,
              !scheduled.id.isEmpty, scheduled.id != dismissedID,
              scheduled.announced_at <= now, now < scheduled.expiresAt else { return nil }
            if let completed = data.latest_reset,
               completed.id == scheduled.id || (completed.reset_type == scheduled.reset_type
                   && completed.announced_at >= scheduled.announced_at) { return nil }
            return scheduled
        }
        // A watch must cite an actual Tibo post. Never derive hints from statistics.
        guard let watch = data.active_watch, ["elevated", "strong"].contains(watch.level),
              watch.source.isTiboPost, let sourceURL = watch.source.url,
              watch.observed_at <= now, now < watch.expires_at else { return nil }
        let hint = CodexResetAnnouncement(id: "hint-" + sourceURL, status: "hint", reset_type: "unknown",
            announced_at: watch.observed_at, scheduled_for: watch.expires_at, source: watch.source)
        guard hint.id != dismissedID, now < hint.expiresAt else { return nil }
        if let completed = data.latest_reset, completed.announced_at >= watch.observed_at { return nil }
        return hint
    }

    public static func decode(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid reset timestamp")
        }
        return try decoder.decode(Self.self, from: data)
    }
}

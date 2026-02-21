import Foundation

enum JourneyFeedItemKind: String, Codable {
    case session
    case highlight
    case note
}

struct JourneyFeedItem: Identifiable, Hashable {
    let id: String
    let kind: JourneyFeedItemKind
    let title: String
    let subtitle: String?
    let date: Date
    let route: AppRoute?
    let sessionId: UUID?
    let recordId: UUID?
}


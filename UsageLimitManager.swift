import Foundation

enum UsageAction {
    case guidedStudyMessage
    case saveNote
    case saveHighlight
}

enum PaywallContext: Equatable {
    case guidedStudyLimit
    case noteLimit
    case highlightLimit
    case shareLimit
}

final class UsageLimitManager {
    static let shared = UsageLimitManager()

    private let defaults: UserDefaults
    private let notesKey = "seek_notes"
    private let highlightsKey = "seek_highlights"

    private let freeNotesLimit = 7
    private let freeHighlightsLimit = 7

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func canPerform(_ action: UsageAction) -> Bool {
        if EntitlementManager.shared.isPremium {
            return true
        }

        switch action {
        case .guidedStudyMessage:
            return StudyUsageTracker.shared.canSendMessage(isPremium: false)
        case .saveNote:
            return totalNotesCount() < freeNotesLimit
        case .saveHighlight:
            return totalHighlightsCount() < freeHighlightsLimit
        }
    }

    func paywallContext(for action: UsageAction) -> PaywallContext {
        switch action {
        case .guidedStudyMessage:
            return .guidedStudyLimit
        case .saveNote:
            return .noteLimit
        case .saveHighlight:
            return .highlightLimit
        }
    }

    func totalNotesCount() -> Int {
        let notes = defaults.dictionary(forKey: notesKey) as? [String: String] ?? [:]
        return notes.count
    }

    func totalHighlightsCount() -> Int {
        let highlights = defaults.array(forKey: highlightsKey) as? [String] ?? []
        return Set(highlights).count
    }
}

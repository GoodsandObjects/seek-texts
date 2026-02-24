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

enum PaywallReason: Equatable {
    case notesLimitReached
    case highlightsLimitReached
    case guidedStudyLimitReached
    case genericUpgrade

    var message: String {
        switch self {
        case .notesLimitReached:
            return "You've reached your note limit."
        case .highlightsLimitReached:
            return "You've reached your highlight limit."
        case .guidedStudyLimitReached:
            return "You've reached your Guided Study limit."
        case .genericUpgrade:
            return "Upgrade to unlock full access."
        }
    }
}

final class UsageLimitManager {
    static let shared = UsageLimitManager()
    static let freeNotesLimit = 7
    static let freeHighlightsLimit = 7

    private let defaults: UserDefaults
    private let notesKey = "seek_notes"
    private let highlightsKey = "seek_highlights"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func canPerform(_ action: UsageAction) -> Bool {
        #if DEBUG
        if debugIsForceLocked(action) {
            return false
        }
        #endif

        if EntitlementManager.shared.isPremium {
            return true
        }

        switch action {
        case .guidedStudyMessage:
            return StudyUsageTracker.shared.canSendMessage(isPremium: false)
        case .saveNote:
            return totalNotesCount() < Self.freeNotesLimit
        case .saveHighlight:
            return totalHighlightsCount() < Self.freeHighlightsLimit
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

    #if DEBUG
    static let debugForceNotesLockedKey = "DEBUG_FORCE_NOTES_LOCKED"
    static let debugForceHighlightsLockedKey = "DEBUG_FORCE_HIGHLIGHTS_LOCKED"
    static let debugForceGuidedStudyLockedKey = "DEBUG_FORCE_GUIDED_STUDY_LOCKED"

    func resetNotesLimit() {
        defaults.removeObject(forKey: notesKey)
    }

    func resetHighlightsLimit() {
        defaults.removeObject(forKey: highlightsKey)
    }

    func resetGuidedStudyLimit() {
        StudyUsageTracker.shared.reset()
    }

    func resetAllLimits() {
        resetNotesLimit()
        resetHighlightsLimit()
        resetGuidedStudyLimit()
    }

    func setDebugForceNotesLocked(_ locked: Bool) {
        defaults.set(locked, forKey: Self.debugForceNotesLockedKey)
    }

    func setDebugForceHighlightsLocked(_ locked: Bool) {
        defaults.set(locked, forKey: Self.debugForceHighlightsLockedKey)
    }

    func setDebugForceGuidedStudyLocked(_ locked: Bool) {
        defaults.set(locked, forKey: Self.debugForceGuidedStudyLockedKey)
    }

    func isDebugForceNotesLocked() -> Bool {
        defaults.bool(forKey: Self.debugForceNotesLockedKey)
    }

    func isDebugForceHighlightsLocked() -> Bool {
        defaults.bool(forKey: Self.debugForceHighlightsLockedKey)
    }

    func isDebugForceGuidedStudyLocked() -> Bool {
        defaults.bool(forKey: Self.debugForceGuidedStudyLockedKey)
    }

    private func debugIsForceLocked(_ action: UsageAction) -> Bool {
        switch action {
        case .saveNote:
            return isDebugForceNotesLocked()
        case .saveHighlight:
            return isDebugForceHighlightsLocked()
        case .guidedStudyMessage:
            return isDebugForceGuidedStudyLocked()
        }
    }
    #endif
}

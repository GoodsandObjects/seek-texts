import SwiftUI
import Combine

// MARK: - Journey Record Model

enum JourneyRecordType: String, Codable {
    case highlight
    case note
}

struct JourneyRecord: Identifiable, Codable {
    let id: UUID
    let createdAt: Date
    let verseId: String
    let religion: String
    let textName: String
    let reference: String
    let verseText: String
    var noteText: String?
    let type: JourneyRecordType

    init(verseId: String, religion: String, textName: String, reference: String, verseText: String, noteText: String? = nil, type: JourneyRecordType) {
        self.id = UUID()
        self.createdAt = Date()
        self.verseId = verseId
        self.religion = religion
        self.textName = textName
        self.reference = reference
        self.verseText = verseText
        self.noteText = noteText
        self.type = type
    }
}

// MARK: - Selected Passage Model

struct SelectedPassage: Equatable {
    let reference: String
    let verseText: String
    let scriptureId: String
    let book: String
    let chapter: Int
    let verseNumber: Int?
    var verseRange: ClosedRange<Int>?
}

// MARK: - Last Reading State

struct LastReadingState: Codable, Equatable, Identifiable {
    let scriptureId: String?
    let bookId: String
    let chapter: Int
    let verseStart: Int?
    let verseEnd: Int?
    let timestamp: Date

    var id: String {
        "\(scriptureId ?? "unknown")-\(bookId)-\(chapter)-\(verseStart ?? 0)-\(verseEnd ?? 0)"
    }
}

struct ReaderDestination: Hashable, Codable {
    let scriptureId: String
    let bookId: String
    let chapter: Int
    let bookName: String
    let verseStart: Int?
    let verseEnd: Int?

    init(
        scriptureId: String,
        bookId: String,
        chapter: Int,
        bookName: String,
        verseStart: Int? = nil,
        verseEnd: Int? = nil
    ) {
        self.scriptureId = scriptureId
        self.bookId = bookId
        self.chapter = chapter
        self.bookName = bookName
        self.verseStart = verseStart
        self.verseEnd = verseEnd
    }
}

enum AppRoute: Hashable {
    case reader(ReaderDestination)
    case guidedStudy(conversationId: UUID)
    case error(title: String, message: String)
}

enum LastReadingStore {
    private static let key = "seek_last_reading_state_v1"

    static func saveLastReadingState(_ state: LastReadingState) {
        guard let encoded = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(encoded, forKey: key)
    }

    static func loadLastReadingState() -> LastReadingState? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(LastReadingState.self, from: data)
    }
}

// MARK: - Guided Session Models

struct GuidedSessionMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: MessageRole
    let text: String
    let timestamp: Date

    enum MessageRole: String, Codable {
        case user
        case assistant
    }

    init(role: MessageRole, text: String) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.timestamp = Date()
    }
}

enum GuidedSessionScope: String, Codable {
    case chapter
    case range
    case selected
}

struct GuidedSession: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date
    var updatedAt: Date
    var title: String
    let reference: String
    let scope: GuidedSessionScope
    let scriptureId: String
    let book: String
    let chapter: Int
    var verseRange: ClosedRange<Int>?
    var messages: [GuidedSessionMessage]

    init(reference: String, scope: GuidedSessionScope, scriptureId: String, book: String, chapter: Int, verseRange: ClosedRange<Int>? = nil, messages: [GuidedSessionMessage] = []) {
        self.id = UUID()
        self.createdAt = Date()
        self.updatedAt = Date()
        self.reference = reference
        self.scope = scope
        self.scriptureId = scriptureId
        self.book = book
        self.chapter = chapter
        self.verseRange = verseRange
        self.messages = messages

        // Auto-generate title from reference and first user message
        self.title = reference
    }

    mutating func updateTitle(from firstUserMessage: String?) {
        if let msg = firstUserMessage, !msg.isEmpty {
            let preview = String(msg.prefix(30))
            title = "\(reference) - \(preview)\(msg.count > 30 ? "..." : "")"
        } else {
            title = reference
        }
    }
}

// MARK: - Guided Passage Selection

struct GuidedPassageSelectionRef: Equatable {
    let traditionId: String
    let traditionName: String
    let scriptureId: String
    let scriptureName: String
    let bookId: String
    let bookName: String
    let chapterNumber: Int
}

// MARK: - Guided Study Context

struct GuidedStudyContext: Identifiable {
    let id = UUID()
    let chapterRef: ChapterRef
    let verses: [LoadedVerse]
    let selectedVerseIds: Set<String>
    let textName: String
    let traditionId: String
    let traditionName: String
    private let singleUnitScriptures = Set(["quran", "bhagavad-gita", "heart-sutra", "upanishads"])

    private var showUnitNumberInReference: Bool {
        !(singleUnitScriptures.contains(chapterRef.scriptureId) && chapterRef.chapterNumber == 1)
    }

    private var baseReference: String {
        showUnitNumberInReference
            ? "\(chapterRef.bookName) \(chapterRef.chapterNumber)"
            : chapterRef.bookName
    }

    /// Build passage for the given scope
    func buildPassage(scope: GuidedSessionScope, verseRange: ClosedRange<Int>? = nil) -> (reference: String, verseText: String, verseIds: [String]) {
        switch scope {
        case .chapter:
            let reference = baseReference
            let text = verses.map { $0.text }.joined(separator: " ")
            let ids = verses.map { $0.id }
            return (reference, text, ids)

        case .range:
            guard let range = verseRange else {
                return buildPassage(scope: .chapter)
            }
            let filtered = verses.filter { range.contains($0.number) }.sorted { $0.number < $1.number }
            guard let first = filtered.first, let last = filtered.last else {
                return buildPassage(scope: .chapter)
            }
            let reference = first.number == last.number
                ? "\(baseReference):\(first.number)"
                : "\(baseReference):\(first.number)–\(last.number)"
            let text = filtered.map { $0.text }.joined(separator: " ")
            let ids = filtered.map { $0.id }
            return (reference, text, ids)

        case .selected:
            let filtered = verses.filter { selectedVerseIds.contains($0.id) }.sorted { $0.number < $1.number }
            guard let first = filtered.first, let last = filtered.last else {
                return buildPassage(scope: .chapter)
            }
            let reference = first.number == last.number
                ? "\(baseReference):\(first.number)"
                : "\(baseReference):\(first.number)–\(last.number)"
            let text = filtered.map { $0.text }.joined(separator: " ")
            let ids = filtered.map { $0.id }
            return (reference, text, ids)
        }
    }
}

// MARK: - App State

class AppState: ObservableObject {
    @Published var highlights: Set<String> = []
    @Published var notes: [String: String] = [:]
    @Published var journeyRecords: [JourneyRecord] = []
    @Published var guidedSessions: [GuidedSession] = []
    @Published var isSeekGuided: Bool = false
    @Published var guidedStudyLastUsedDate: String = ""
    @Published var guidedSandboxMode: Bool = false
    @Published var selectedPassage: SelectedPassage?
    @Published var isPaywallPresented: Bool = false
    @Published var paywallContext: PaywallContext? = nil

    private var paywallUnlockAction: (() -> Void)?

    private let highlightsKey = "seek_highlights"
    private let notesKey = "seek_notes"
    private let journeyRecordsKey = "seek_journey_records"
    private let guidedSessionsKey = "seek_guided_sessions"
    private let seekGuidedKey = "seek_is_guided"
    private let guidedDateKey = "seek_guided_date"
    private let sandboxKey = "seek_guided_sandbox"

    static let maxHighlightsFree = 18
    static let maxNotesFree = 7
    static let maxGuidedStudyFree = 3

    init() {
        loadPersistedData()
    }

    private func loadPersistedData() {
        if let saved = UserDefaults.standard.array(forKey: highlightsKey) as? [String] {
            highlights = Set(saved)
        }
        if let saved = UserDefaults.standard.dictionary(forKey: notesKey) as? [String: String] {
            notes = saved
        }
        if let data = UserDefaults.standard.data(forKey: journeyRecordsKey),
           let records = try? JSONDecoder().decode([JourneyRecord].self, from: data) {
            journeyRecords = records
        }
        if let data = UserDefaults.standard.data(forKey: guidedSessionsKey),
           let sessions = try? JSONDecoder().decode([GuidedSession].self, from: data) {
            guidedSessions = sessions
        }
        isSeekGuided = UserDefaults.standard.bool(forKey: seekGuidedKey)
        guidedStudyLastUsedDate = UserDefaults.standard.string(forKey: guidedDateKey) ?? ""
        guidedSandboxMode = UserDefaults.standard.bool(forKey: sandboxKey)
    }

    private func persistHighlights() {
        UserDefaults.standard.set(Array(highlights), forKey: highlightsKey)
    }

    private func persistNotes() {
        UserDefaults.standard.set(notes, forKey: notesKey)
    }

    private func persistJourneyRecords() {
        if let data = try? JSONEncoder().encode(journeyRecords) {
            UserDefaults.standard.set(data, forKey: journeyRecordsKey)
        }
    }

    private func persistGuidedSessions() {
        if let data = try? JSONEncoder().encode(guidedSessions) {
            UserDefaults.standard.set(data, forKey: guidedSessionsKey)
        }
    }

    func setSandboxMode(_ enabled: Bool) {
        guidedSandboxMode = enabled
        UserDefaults.standard.set(enabled, forKey: sandboxKey)
        EntitlementManager.shared.applySandboxOverrideIfNeeded()
    }

    var effectivelyGuided: Bool {
        isSeekGuided || guidedSandboxMode
    }

    // MARK: - Selected Passage

    func setSelectedPassage(reference: String, verseText: String, scriptureId: String, book: String, chapter: Int, verseNumber: Int?) {
        selectedPassage = SelectedPassage(
            reference: reference,
            verseText: verseText,
            scriptureId: scriptureId,
            book: book,
            chapter: chapter,
            verseNumber: verseNumber
        )
    }

    func setSelectedPassageForChapter(book: String, chapter: Int, scriptureId: String, allVersesText: String?) {
        selectedPassage = SelectedPassage(
            reference: "\(book) \(chapter)",
            verseText: allVersesText ?? "",
            scriptureId: scriptureId,
            book: book,
            chapter: chapter,
            verseNumber: nil
        )
    }

    func clearSelectedPassage() {
        selectedPassage = nil
    }

    // MARK: - Guided Sessions

    func saveGuidedSession(_ session: GuidedSession) {
        if let index = guidedSessions.firstIndex(where: { $0.id == session.id }) {
            guidedSessions[index] = session
        } else {
            guidedSessions.append(session)
        }
        persistGuidedSessions()
    }

    func updateGuidedSession(_ session: GuidedSession) {
        var updated = session
        updated.updatedAt = Date()
        saveGuidedSession(updated)
    }

    func deleteGuidedSession(_ sessionId: UUID) {
        guidedSessions.removeAll { $0.id == sessionId }
        persistGuidedSessions()
    }

    func getGuidedSession(by id: UUID) -> GuidedSession? {
        guidedSessions.first { $0.id == id }
    }

    var sortedGuidedSessions: [GuidedSession] {
        guidedSessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Highlights & Notes

    func toggleHighlight(_ id: String, reference: String? = nil, verseText: String? = nil, religion: String = "", textName: String = "") {
        if highlights.contains(id) {
            highlights.remove(id)
            journeyRecords.removeAll { $0.verseId == id && $0.type == .highlight }
        } else {
            highlights.insert(id)
            StreakManager.shared.recordHighlightCreation()
            if let ref = reference, let text = verseText {
                let record = JourneyRecord(
                    verseId: id,
                    religion: religion,
                    textName: textName,
                    reference: ref,
                    verseText: text,
                    type: .highlight
                )
                journeyRecords.append(record)
            }
        }
        persistHighlights()
        persistJourneyRecords()
    }

    func setNote(_ id: String, _ text: String, reference: String? = nil, verseText: String? = nil, religion: String = "", textName: String = "") {
        if text.isEmpty {
            notes.removeValue(forKey: id)
            journeyRecords.removeAll { $0.verseId == id && $0.type == .note }
        } else {
            if notes[id] == nil {
                StreakManager.shared.recordNoteCreation()
            }
            notes[id] = text
            if let existingIndex = journeyRecords.firstIndex(where: { $0.verseId == id && $0.type == .note }) {
                journeyRecords[existingIndex].noteText = text
            } else if let ref = reference, let vText = verseText {
                let record = JourneyRecord(
                    verseId: id,
                    religion: religion,
                    textName: textName,
                    reference: ref,
                    verseText: vText,
                    noteText: text,
                    type: .note
                )
                journeyRecords.append(record)
            }
        }
        persistNotes()
        persistJourneyRecords()
    }

    func removeHighlightByVerseId(_ verseId: String) {
        highlights.remove(verseId)
        journeyRecords.removeAll { $0.verseId == verseId && $0.type == .highlight }
        persistHighlights()
        persistJourneyRecords()
    }

    func removeNoteByVerseId(_ verseId: String) {
        notes.removeValue(forKey: verseId)
        journeyRecords.removeAll { $0.verseId == verseId && $0.type == .note }
        persistNotes()
        persistJourneyRecords()
    }

    func updateNoteText(for verseId: String, newText: String) {
        if newText.isEmpty {
            removeNoteByVerseId(verseId)
        } else {
            notes[verseId] = newText
            if let idx = journeyRecords.firstIndex(where: { $0.verseId == verseId && $0.type == .note }) {
                journeyRecords[idx].noteText = newText
            }
            persistNotes()
            persistJourneyRecords()
        }
    }

    func canAddHighlight() -> Bool {
        UsageLimitManager.shared.canPerform(.saveHighlight)
    }

    func canAddNote() -> Bool {
        UsageLimitManager.shared.canPerform(.saveNote)
    }

    func canUseGuidedStudy() -> Bool {
        if effectivelyGuided { return true }
        let today = Self.todayString()
        return guidedStudyLastUsedDate != today
    }

    func recordGuidedStudyUsage() {
        guidedStudyLastUsedDate = Self.todayString()
        UserDefaults.standard.set(guidedStudyLastUsedDate, forKey: guidedDateKey)
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    func presentPaywall(_ context: PaywallContext, onUnlock: (() -> Void)? = nil) {
        guard !EntitlementManager.shared.isPremium else {
            onUnlock?()
            return
        }
        paywallContext = context
        paywallUnlockAction = onUnlock
        isPaywallPresented = true
    }

    func handlePaywallUnlocked() {
        paywallUnlockAction?()
        paywallUnlockAction = nil
        isPaywallPresented = false
    }

    func dismissPaywall() {
        paywallUnlockAction = nil
        isPaywallPresented = false
    }
}

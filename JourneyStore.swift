//
//  JourneyStore.swift
//  Seek
//
//  Unified data layer for Journey items. Adapts existing storage (highlights, notes, sessions)
//  into a cohesive model for the Journey UI while maintaining backward compatibility.
//

import Foundation
import Combine

// MARK: - Journey Item Type

enum JourneyItemType: String, Codable, CaseIterable {
    case highlight
    case note
    case guidedSession
    case guidedInsight
    case bookmark

    var displayName: String {
        switch self {
        case .highlight: return "Highlights"
        case .note: return "Notes"
        case .guidedSession: return "Sessions"
        case .guidedInsight: return "Insights"
        case .bookmark: return "Bookmarks"
        }
    }

    var icon: String {
        switch self {
        case .highlight: return "highlighter"
        case .note: return "note.text"
        case .guidedSession: return "sparkles"
        case .guidedInsight: return "lightbulb.fill"
        case .bookmark: return "bookmark.fill"
        }
    }
}

// MARK: - Scripture Reference

struct ScriptureRef: Codable, Equatable, Hashable {
    let scriptureId: String
    let bookId: String
    let chapter: Int
    let verseStart: Int?
    let verseEnd: Int?
    let display: String // Human-readable display string (e.g., "Genesis 4:1-3")

    init(scriptureId: String, bookId: String, chapter: Int, verseStart: Int? = nil, verseEnd: Int? = nil, display: String) {
        self.scriptureId = scriptureId
        self.bookId = bookId
        self.chapter = chapter
        self.verseStart = verseStart
        self.verseEnd = verseEnd
        self.display = display
    }

    /// Create from a verse ID string (format: "scriptureId-bookId-chapter-verse")
    static func fromVerseId(_ verseId: String, display: String) -> ScriptureRef? {
        let parts = verseId.split(separator: "-")
        guard parts.count >= 4,
              let chapter = Int(parts[2]),
              let verse = Int(parts[3]) else {
            return nil
        }
        return ScriptureRef(
            scriptureId: String(parts[0]),
            bookId: String(parts[1]),
            chapter: chapter,
            verseStart: verse,
            verseEnd: verse,
            display: display
        )
    }

    /// Create from a GuidedSession
    static func fromSession(_ session: GuidedSession) -> ScriptureRef {
        var verseStart: Int? = nil
        var verseEnd: Int? = nil

        if let range = session.verseRange {
            verseStart = range.lowerBound
            verseEnd = range.upperBound
        }

        return ScriptureRef(
            scriptureId: session.scriptureId,
            bookId: session.book.lowercased().replacingOccurrences(of: " ", with: "-"),
            chapter: session.chapter,
            verseStart: verseStart,
            verseEnd: verseEnd,
            display: session.reference
        )
    }
}

// MARK: - Journey Item

struct JourneyItem: Identifiable, Codable, Equatable {
    let id: UUID
    let type: JourneyItemType
    let ref: ScriptureRef
    var title: String?
    var body: String?
    var quote: String?          // The verse text (for highlights/notes)
    var tags: [String]?
    let createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    var sourceSessionId: UUID?  // For guided insights linked to a session
    var textName: String?       // Scripture name (e.g., "King James Bible")

    init(
        id: UUID = UUID(),
        type: JourneyItemType,
        ref: ScriptureRef,
        title: String? = nil,
        body: String? = nil,
        quote: String? = nil,
        tags: [String]? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isPinned: Bool = false,
        sourceSessionId: UUID? = nil,
        textName: String? = nil
    ) {
        self.id = id
        self.type = type
        self.ref = ref
        self.title = title
        self.body = body
        self.quote = quote
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.sourceSessionId = sourceSessionId
        self.textName = textName
    }
}

// MARK: - Time Group

enum JourneyTimeGroup: String, CaseIterable {
    case today = "Today"
    case thisWeek = "This Week"
    case earlier = "Earlier"

    static func group(for date: Date) -> JourneyTimeGroup {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(date) {
            return .today
        } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now),
                  date >= weekAgo {
            return .thisWeek
        } else {
            return .earlier
        }
    }
}

// MARK: - Sort Option

enum JourneySortOption: String, CaseIterable {
    case recent = "Recent"
    case oldest = "Oldest"
    case pinned = "Pinned First"

    var icon: String {
        switch self {
        case .recent: return "arrow.down"
        case .oldest: return "arrow.up"
        case .pinned: return "pin.fill"
        }
    }
}

// MARK: - Journey Store

@MainActor
class JourneyStore: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var items: [JourneyItem] = []
    @Published private(set) var guidedInsights: [JourneyItem] = []

    // Filter state
    @Published var searchText: String = ""
    @Published var selectedTypes: Set<JourneyItemType> = []
    @Published var selectedScriptureIds: Set<String> = []
    @Published var selectedBookIds: Set<String> = []
    @Published var sortOption: JourneySortOption = .recent
    @Published var showPinnedOnly: Bool = false

    // MARK: - Private Properties

    private weak var appState: AppState?
    private var cancellables = Set<AnyCancellable>()
    private let insightsKey = "journey_insights_v1"

    // MARK: - Initialization

    init(appState: AppState) {
        self.appState = appState
        loadInsights()
        buildItemsFromAppState()

        // Subscribe to changes in appState
        appState.$journeyRecords
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.buildItemsFromAppState()
            }
            .store(in: &cancellables)

        appState.$guidedSessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.buildItemsFromAppState()
            }
            .store(in: &cancellables)
    }

    // MARK: - Computed Properties

    /// All items filtered and sorted based on current settings
    var filteredItems: [JourneyItem] {
        var result = items

        // Filter by search text
        if !searchText.isEmpty {
            let lowercasedSearch = searchText.lowercased()
            result = result.filter { item in
                item.ref.display.lowercased().contains(lowercasedSearch) ||
                (item.title?.lowercased().contains(lowercasedSearch) ?? false) ||
                (item.body?.lowercased().contains(lowercasedSearch) ?? false) ||
                (item.quote?.lowercased().contains(lowercasedSearch) ?? false) ||
                (item.textName?.lowercased().contains(lowercasedSearch) ?? false)
            }
        }

        // Filter by selected types
        if !selectedTypes.isEmpty {
            result = result.filter { selectedTypes.contains($0.type) }
        }

        // Filter by scripture
        if !selectedScriptureIds.isEmpty {
            result = result.filter { selectedScriptureIds.contains($0.ref.scriptureId) }
        }

        // Filter by book
        if !selectedBookIds.isEmpty {
            result = result.filter { selectedBookIds.contains($0.ref.bookId) }
        }

        // Filter pinned only
        if showPinnedOnly {
            result = result.filter { $0.isPinned }
        }

        // Sort
        switch sortOption {
        case .recent:
            result.sort { $0.updatedAt > $1.updatedAt }
        case .oldest:
            result.sort { $0.updatedAt < $1.updatedAt }
        case .pinned:
            result.sort { ($0.isPinned ? 0 : 1, $0.updatedAt) < ($1.isPinned ? 0 : 1, $1.updatedAt) }
        }

        return result
    }

    /// Items grouped by time
    var groupedByTime: [(group: JourneyTimeGroup, items: [JourneyItem])] {
        let filtered = filteredItems
        var grouped: [JourneyTimeGroup: [JourneyItem]] = [:]

        for item in filtered {
            let group = JourneyTimeGroup.group(for: item.updatedAt)
            grouped[group, default: []].append(item)
        }

        // Return in order: Today, This Week, Earlier
        return JourneyTimeGroup.allCases.compactMap { group in
            guard let items = grouped[group], !items.isEmpty else { return nil }
            return (group: group, items: items)
        }
    }

    /// Get unique scripture IDs from all items
    var availableScriptureIds: Set<String> {
        Set(items.map { $0.ref.scriptureId })
    }

    /// Get unique book IDs from all items (optionally filtered by scripture)
    func availableBookIds(forScripture scriptureId: String? = nil) -> Set<String> {
        let filtered = scriptureId != nil
            ? items.filter { $0.ref.scriptureId == scriptureId }
            : items
        return Set(filtered.map { $0.ref.bookId })
    }

    /// Check if any filters are active
    var hasActiveFilters: Bool {
        !selectedTypes.isEmpty || !selectedScriptureIds.isEmpty || !selectedBookIds.isEmpty || showPinnedOnly || sortOption != .recent
    }

    /// Count of active filters
    var activeFilterCount: Int {
        var count = 0
        if !selectedTypes.isEmpty { count += 1 }
        if !selectedScriptureIds.isEmpty { count += 1 }
        if !selectedBookIds.isEmpty { count += 1 }
        if showPinnedOnly { count += 1 }
        if sortOption != .recent { count += 1 }
        return count
    }

    // MARK: - Build Items from AppState

    private func buildItemsFromAppState() {
        guard let appState = appState else { return }

        var allItems: [JourneyItem] = []

        // Convert JourneyRecords (highlights and notes)
        for record in appState.journeyRecords {
            if let ref = ScriptureRef.fromVerseId(record.verseId, display: record.reference) {
                let item = JourneyItem(
                    id: record.id,
                    type: record.type == .highlight ? .highlight : .note,
                    ref: ref,
                    title: nil,
                    body: record.noteText,
                    quote: record.verseText,
                    tags: nil,
                    createdAt: record.createdAt,
                    updatedAt: record.createdAt,
                    isPinned: false,
                    sourceSessionId: nil,
                    textName: record.textName
                )
                allItems.append(item)
            }
        }

        // Convert GuidedSessions
        for session in appState.guidedSessions {
            let ref = ScriptureRef.fromSession(session)
            let item = JourneyItem(
                id: session.id,
                type: .guidedSession,
                ref: ref,
                title: session.title,
                body: session.messages.first(where: { $0.role == .user })?.text,
                quote: nil,
                tags: nil,
                createdAt: session.createdAt,
                updatedAt: session.updatedAt,
                isPinned: false,
                sourceSessionId: nil,
                textName: nil
            )
            allItems.append(item)
        }

        // Add guided insights
        allItems.append(contentsOf: guidedInsights)

        self.items = allItems
    }

    // MARK: - Insights Persistence

    private func loadInsights() {
        guard let data = UserDefaults.standard.data(forKey: insightsKey),
              let insights = try? JSONDecoder().decode([JourneyItem].self, from: data) else {
            guidedInsights = []
            return
        }
        guidedInsights = insights
    }

    private func persistInsights() {
        if let data = try? JSONEncoder().encode(guidedInsights) {
            UserDefaults.standard.set(data, forKey: insightsKey)
        }
    }

    // MARK: - Public Methods

    /// Save a guided insight from a session
    func saveInsight(
        title: String?,
        body: String,
        quote: String?,
        sessionId: UUID,
        ref: ScriptureRef
    ) {
        let insight = JourneyItem(
            type: .guidedInsight,
            ref: ref,
            title: title ?? "Insight from \(ref.display)",
            body: body,
            quote: quote,
            createdAt: Date(),
            updatedAt: Date(),
            isPinned: false,
            sourceSessionId: sessionId
        )

        guidedInsights.append(insight)
        persistInsights()
        buildItemsFromAppState()
    }

    /// Toggle pin status
    func togglePin(for itemId: UUID) {
        // Check if it's an insight
        if let index = guidedInsights.firstIndex(where: { $0.id == itemId }) {
            guidedInsights[index].isPinned.toggle()
            guidedInsights[index].updatedAt = Date()
            persistInsights()
            buildItemsFromAppState()
        }
        // For other types, we'd need to update the original source
        // This is a future enhancement - for now we only support pinning insights
    }

    /// Delete an insight
    func deleteInsight(_ itemId: UUID) {
        guidedInsights.removeAll { $0.id == itemId }
        persistInsights()
        buildItemsFromAppState()
    }

    /// Update an insight's body text
    func updateInsightBody(_ itemId: UUID, newBody: String) {
        if let index = guidedInsights.firstIndex(where: { $0.id == itemId }) {
            guidedInsights[index].body = newBody
            guidedInsights[index].updatedAt = Date()
            persistInsights()
            buildItemsFromAppState()
        }
    }

    /// Get item by ID
    func item(by id: UUID) -> JourneyItem? {
        items.first { $0.id == id }
    }

    /// Get guided session for an item (if type is guidedSession)
    func guidedSession(for item: JourneyItem) -> GuidedSession? {
        guard item.type == .guidedSession else { return nil }
        return appState?.getGuidedSession(by: item.id)
    }

    /// Clear all filters
    func clearFilters() {
        searchText = ""
        selectedTypes = []
        selectedScriptureIds = []
        selectedBookIds = []
        sortOption = .recent
        showPinnedOnly = false
    }

    // MARK: - Statistics

    var highlightCount: Int {
        items.filter { $0.type == .highlight }.count
    }

    var noteCount: Int {
        items.filter { $0.type == .note }.count
    }

    var sessionCount: Int {
        items.filter { $0.type == .guidedSession }.count
    }

    var insightCount: Int {
        items.filter { $0.type == .guidedInsight }.count
    }

    var totalCount: Int {
        items.count
    }
}

// MARK: - Preview Helper

extension JourneyStore {
    static var preview: JourneyStore {
        JourneyStore(appState: AppState())
    }
}

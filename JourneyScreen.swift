//
//  JourneyScreen.swift
//  Seek
//
//  Journey screen with time-based grouping, search, and advanced filters.
//

import SwiftUI

// MARK: - Journey Filter Type

enum JourneyFilter: String, CaseIterable {
    case all = "All"
    case sessions = "Sessions"
    case highlights = "Highlights"
    case notes = "Notes"

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .sessions: return "sparkles"
        case .highlights: return "highlighter"
        case .notes: return "note.text"
        }
    }
}

// MARK: - Journey Screen

struct JourneyScreen: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var journeyStore: JourneyStore
    @State private var searchText = ""
    @State private var selectedFilter: JourneyFilter = .all
    @State private var showFilterSheet = false
    @State private var selectedNoteRecord: JourneyRecord?
    @State private var selectedHighlightRecord: JourneyRecord?
    @State private var selectedSession: GuidedSession?
    @State private var showSessionDetail: Bool = false

    init() {
        // Initialize with a temporary AppState; the real one is injected via environment
        _journeyStore = StateObject(wrappedValue: JourneyStore(appState: AppState()))
    }

    private var hasAnyContent: Bool {
        !appState.journeyRecords.isEmpty || !appState.guidedSessions.isEmpty
    }

    private var filteredRecordsByType: [JourneyRecord] {
        var records = appState.journeyRecords

        switch selectedFilter {
        case .all:
            break
        case .sessions:
            return []
        case .highlights:
            records = records.filter { $0.type == .highlight }
        case .notes:
            records = records.filter { $0.type == .note }
        }

        if !searchText.isEmpty {
            records = records.filter {
                $0.reference.localizedCaseInsensitiveContains(searchText) ||
                $0.verseText.localizedCaseInsensitiveContains(searchText) ||
                ($0.noteText?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                $0.textName.localizedCaseInsensitiveContains(searchText)
            }
        }

        return records.sorted { $0.createdAt > $1.createdAt }
    }

    private var filteredSessions: [GuidedSession] {
        var sessions = appState.sortedGuidedSessions

        if !searchText.isEmpty {
            sessions = sessions.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.reference.localizedCaseInsensitiveContains(searchText) ||
                $0.messages.contains { $0.text.localizedCaseInsensitiveContains(searchText) }
            }
        }

        return sessions
    }

    private var showSessionsSection: Bool {
        selectedFilter == .all || selectedFilter == .sessions
    }

    private var showRecordsSection: Bool {
        selectedFilter == .all || selectedFilter == .highlights || selectedFilter == .notes
    }

    // Group records by time period
    private var groupedByTime: [(group: String, records: [JourneyRecord], sessions: [GuidedSession])] {
        var result: [(group: String, records: [JourneyRecord], sessions: [GuidedSession])] = []

        let calendar = Calendar.current
        let now = Date()

        // Combine records and sessions with their dates
        struct TimedItem {
            let date: Date
            let record: JourneyRecord?
            let session: GuidedSession?
        }

        var allItems: [TimedItem] = []

        if showRecordsSection {
            allItems.append(contentsOf: filteredRecordsByType.map { TimedItem(date: $0.createdAt, record: $0, session: nil) })
        }

        if showSessionsSection {
            allItems.append(contentsOf: filteredSessions.map { TimedItem(date: $0.updatedAt, record: nil, session: $0) })
        }

        // Group items by time period
        var todayRecords: [JourneyRecord] = []
        var todaySessions: [GuidedSession] = []
        var weekRecords: [JourneyRecord] = []
        var weekSessions: [GuidedSession] = []
        var earlierRecords: [JourneyRecord] = []
        var earlierSessions: [GuidedSession] = []

        for item in allItems {
            if calendar.isDateInToday(item.date) {
                if let record = item.record { todayRecords.append(record) }
                if let session = item.session { todaySessions.append(session) }
            } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now), item.date >= weekAgo {
                if let record = item.record { weekRecords.append(record) }
                if let session = item.session { weekSessions.append(session) }
            } else {
                if let record = item.record { earlierRecords.append(record) }
                if let session = item.session { earlierSessions.append(session) }
            }
        }

        // Sort each group
        todayRecords.sort { $0.createdAt > $1.createdAt }
        todaySessions.sort { $0.updatedAt > $1.updatedAt }
        weekRecords.sort { $0.createdAt > $1.createdAt }
        weekSessions.sort { $0.updatedAt > $1.updatedAt }
        earlierRecords.sort { $0.createdAt > $1.createdAt }
        earlierSessions.sort { $0.updatedAt > $1.updatedAt }

        if !todayRecords.isEmpty || !todaySessions.isEmpty {
            result.append((group: "Today", records: todayRecords, sessions: todaySessions))
        }
        if !weekRecords.isEmpty || !weekSessions.isEmpty {
            result.append((group: "This Week", records: weekRecords, sessions: weekSessions))
        }
        if !earlierRecords.isEmpty || !earlierSessions.isEmpty {
            result.append((group: "Earlier", records: earlierRecords, sessions: earlierSessions))
        }

        return result
    }

    var body: some View {
        Group {
            if !hasAnyContent {
                emptyStateView
            } else {
                contentView
            }
        }
        .navigationTitle("My Journey")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showFilterSheet = true
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 17))
                        .foregroundColor(SeekTheme.maroonAccent)
                }
            }
        }
        .sheet(item: $selectedNoteRecord) { record in
            JourneyNoteDetailSheet(record: record)
                .environmentObject(appState)
        }
        .sheet(item: $selectedHighlightRecord) { record in
            JourneyHighlightDetailSheet(record: record)
                .environmentObject(appState)
        }
        .sheet(isPresented: $showFilterSheet) {
            JourneyFilterSheet(
                selectedFilter: $selectedFilter,
                sortOption: .constant(.recent),
                showPinnedOnly: .constant(false)
            )
        }
        .fullScreenCover(isPresented: $showSessionDetail) {
            if let session = selectedSession {
                GuidedSessionDetailScreen(session: session)
                    .environmentObject(appState)
            }
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(SeekTheme.maroonAccent.opacity(0.08))
                    .frame(width: 88, height: 88)

                Image(systemName: "heart")
                    .font(.system(size: 36, weight: .light))
                    .foregroundColor(SeekTheme.maroonAccent.opacity(0.6))
            }

            VStack(spacing: 8) {
                Text("Your journey begins here")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(SeekTheme.textPrimary)

                Text("Sessions, highlights, and notes appear here")
                    .font(.system(size: 14))
                    .foregroundColor(SeekTheme.textSecondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .themedScreenBackground()
    }

    // MARK: - Content View

    private var contentView: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Search bar
                searchBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                // Filter chips
                filterChips
                    .padding(.top, 12)

                // Time-grouped content
                LazyVStack(spacing: 0) {
                    ForEach(groupedByTime, id: \.group) { group in
                        timeGroupSection(group: group.group, records: group.records, sessions: group.sessions)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .themedScreenBackground()
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundColor(SeekTheme.textSecondary)

            TextField("Search sessions, highlights & notes", text: $searchText)
                .font(.system(size: 15))
                .foregroundColor(SeekTheme.textPrimary)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(SeekTheme.textSecondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(SeekTheme.cardBackground)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(JourneyFilter.allCases, id: \.self) { filter in
                    JourneyFilterChip(
                        title: filter.rawValue,
                        icon: filter.icon,
                        isSelected: selectedFilter == filter,
                        count: countForFilter(filter)
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedFilter = filter
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Time Group Section

    private func timeGroupSection(group: String, records: [JourneyRecord], sessions: [GuidedSession]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Group header
            Text(group)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(SeekTheme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 20)
                .padding(.top, 20)

            // Sessions in this group
            if !sessions.isEmpty && showSessionsSection {
                ForEach(sessions) { session in
                    GuidedSessionRow(session: session)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedSession = session
                            showSessionDetail = true
                        }
                        .padding(.horizontal, 20)
                }
            }

            // Records in this group with context menus
            if !records.isEmpty && showRecordsSection {
                ForEach(records) { record in
                    JourneyRecordRow(record: record)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if record.type == .note {
                                selectedNoteRecord = record
                            } else {
                                selectedHighlightRecord = record
                            }
                        }
                        .contextMenu {
                            // Share action - branded card
                            Button {
                                ShareImageGenerator.shared.shareJourneyRecord(record)
                            } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }

                            // Copy action - plain text
                            Button {
                                CopyUtility.copyJourneyRecord(record)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }

                            Divider()

                            // Delete action
                            Button(role: .destructive) {
                                if record.type == .note {
                                    appState.removeNoteByVerseId(record.verseId)
                                } else {
                                    appState.removeHighlightByVerseId(record.verseId)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .padding(.horizontal, 20)
                }
            }
        }
    }

    private func countForFilter(_ filter: JourneyFilter) -> Int? {
        switch filter {
        case .all:
            return nil
        case .sessions:
            return appState.guidedSessions.count > 0 ? appState.guidedSessions.count : nil
        case .highlights:
            let count = appState.journeyRecords.filter { $0.type == .highlight }.count
            return count > 0 ? count : nil
        case .notes:
            let count = appState.journeyRecords.filter { $0.type == .note }.count
            return count > 0 ? count : nil
        }
    }
}

// MARK: - Journey Filter Chip

private struct JourneyFilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    var count: Int? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))

                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))

                if let count = count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : SeekTheme.textSecondary)
                }
            }
            .foregroundColor(isSelected ? .white : SeekTheme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? SeekTheme.maroonAccent : SeekTheme.cardBackground)
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(isSelected ? 0 : 0.03), radius: 4, x: 0, y: 2)
        }
    }
}

// MARK: - Guided Session Row

private struct GuidedSessionRow: View {
    let session: GuidedSession

    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: session.updatedAt, relativeTo: Date())
    }

    private var messageCount: Int {
        session.messages.filter { $0.role == .user }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .foregroundColor(SeekTheme.maroonAccent)
                    Text(session.reference)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(SeekTheme.maroonAccent)
                }

                Spacer()

                Text(timeAgo)
                    .font(.system(size: 11))
                    .foregroundColor(SeekTheme.textSecondary)
            }

            Text(session.title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(SeekTheme.textPrimary)
                .lineLimit(2)

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 10))
                    Text("\(messageCount) messages")
                        .font(.system(size: 11))
                }
                .foregroundColor(SeekTheme.textSecondary)

                Text(scopeLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(SeekTheme.maroonAccent.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(SeekTheme.maroonAccent.opacity(0.1))
                    .cornerRadius(8)
            }
        }
        .padding(16)
        .background(SeekTheme.cardBackground)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
    }

    private var scopeLabel: String {
        switch session.scope {
        case .chapter:
            return "Full Chapter"
        case .range:
            if let range = session.verseRange {
                return "Verses \(range.lowerBound)-\(range.upperBound)"
            }
            return "Verse Range"
        case .selected:
            return "Selected Verses"
        }
    }
}

// MARK: - Journey Record Row

private struct JourneyRecordRow: View {
    let record: JourneyRecord
    private let highlightYellow = Color(red: 1.0, green: 0.95, blue: 0.75)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(record.reference)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(SeekTheme.maroonAccent)

                Spacer()

                Image(systemName: record.type == .highlight ? "highlighter" : "note.text")
                    .font(.system(size: 11))
                    .foregroundColor(SeekTheme.maroonAccent.opacity(0.5))
            }

            Text(record.verseText)
                .font(.custom("Georgia", size: 15))
                .lineSpacing(4)
                .lineLimit(2)
                .foregroundColor(SeekTheme.textPrimary)

            if let note = record.noteText, !note.isEmpty {
                Text(note)
                    .font(.system(size: 13))
                    .foregroundColor(SeekTheme.textSecondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 1.0, green: 0.96, blue: 0.90))
                    .cornerRadius(10)
            }
        }
        .padding(16)
        .background(record.type == .highlight ? highlightYellow : SeekTheme.cardBackground)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Journey Filter Sheet

struct JourneyFilterSheet: View {
    @Binding var selectedFilter: JourneyFilter
    @Binding var sortOption: JourneySortOption
    @Binding var showPinnedOnly: Bool
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Sort options
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sort by")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(SeekTheme.textSecondary)
                            .textCase(.uppercase)
                            .tracking(0.5)

                        VStack(spacing: 8) {
                            ForEach(JourneySortOption.allCases, id: \.self) { option in
                                Button {
                                    sortOption = option
                                } label: {
                                    HStack {
                                        Image(systemName: option.icon)
                                            .font(.system(size: 14))
                                            .foregroundColor(SeekTheme.maroonAccent)
                                            .frame(width: 24)

                                        Text(option.rawValue)
                                            .font(.system(size: 15))
                                            .foregroundColor(SeekTheme.textPrimary)

                                        Spacer()

                                        if sortOption == option {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(SeekTheme.maroonAccent)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .background(sortOption == option ? SeekTheme.maroonAccent.opacity(0.08) : SeekTheme.cardBackground)
                                    .cornerRadius(12)
                                }
                            }
                        }
                    }

                    // Show pinned only toggle
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Display")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(SeekTheme.textSecondary)
                            .textCase(.uppercase)
                            .tracking(0.5)

                        Toggle(isOn: $showPinnedOnly) {
                            HStack(spacing: 10) {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(SeekTheme.maroonAccent)

                                Text("Show pinned only")
                                    .font(.system(size: 15))
                                    .foregroundColor(SeekTheme.textPrimary)
                            }
                        }
                        .tint(SeekTheme.maroonAccent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(SeekTheme.cardBackground)
                        .cornerRadius(12)
                    }

                    // Reset button
                    Button {
                        sortOption = .recent
                        showPinnedOnly = false
                    } label: {
                        Text("Reset Filters")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(SeekTheme.maroonAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(SeekTheme.maroonAccent.opacity(0.1))
                            .cornerRadius(12)
                    }
                }
                .padding(20)
            }
            .themedScreenBackground()
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(SeekTheme.maroonAccent)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Journey Note Detail Sheet

struct JourneyNoteDetailSheet: View {
    let record: JourneyRecord
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var editedNoteText: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(record.reference)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(SeekTheme.maroonAccent)

                        Text(record.textName)
                            .font(.system(size: 13))
                            .foregroundColor(SeekTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(SeekTheme.cardBackground)
                    .cornerRadius(14)

                    // Verse
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Verse")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(SeekTheme.textSecondary)
                            .textCase(.uppercase)
                            .tracking(0.5)

                        Text(record.verseText)
                            .font(.custom("Georgia", size: 16))
                            .lineSpacing(6)
                            .foregroundColor(SeekTheme.textPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(SeekTheme.cardBackground)
                    .cornerRadius(14)

                    // Note editor
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your Note")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(SeekTheme.textSecondary)
                            .textCase(.uppercase)
                            .tracking(0.5)

                        TextEditor(text: $editedNoteText)
                            .frame(minHeight: 120)
                            .font(.system(size: 15))
                            .scrollContentBackground(.hidden)
                            .padding(12)
                            .background(Color(red: 1.0, green: 0.96, blue: 0.90))
                            .cornerRadius(10)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(SeekTheme.cardBackground)
                    .cornerRadius(14)

                    // Actions
                    VStack(spacing: 12) {
                        Button {
                            appState.updateNoteText(for: record.verseId, newText: editedNoteText)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.down")
                                Text("Save")
                            }
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(SeekTheme.maroonAccent)
                            .cornerRadius(12)
                        }

                        HStack(spacing: 12) {
                            // Copy button - plain text only
                            Button {
                                CopyUtility.copyNote(
                                    reference: record.reference,
                                    verseText: record.verseText,
                                    scriptureName: record.textName,
                                    noteText: editedNoteText
                                )
                            } label: {
                                HStack {
                                    Image(systemName: "doc.on.doc")
                                    Text("Copy")
                                }
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(SeekTheme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(SeekTheme.cardBackground)
                                .cornerRadius(12)
                            }

                            Button {
                                appState.removeNoteByVerseId(record.verseId)
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "trash")
                                    Text("Delete")
                                }
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(SeekTheme.cardBackground)
                                .cornerRadius(12)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .themedScreenBackground()
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(SeekTheme.maroonAccent)
                }
                ToolbarItem(placement: .primaryAction) {
                    // Share button in toolbar - branded card
                    Button {
                        ShareImageGenerator.shared.shareNote(
                            reference: record.reference,
                            verseText: record.verseText,
                            scriptureName: record.textName,
                            noteText: editedNoteText
                        )
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16))
                            .foregroundColor(SeekTheme.maroonAccent)
                    }
                }
            }
            .onAppear {
                editedNoteText = record.noteText ?? ""
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Journey Highlight Detail Sheet

struct JourneyHighlightDetailSheet: View {
    let record: JourneyRecord
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    private let highlightYellow = Color(red: 1.0, green: 0.95, blue: 0.75)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header with highlight background
                    VStack(alignment: .leading, spacing: 8) {
                        Text(record.reference)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(SeekTheme.maroonAccent)

                        Text(record.textName)
                            .font(.system(size: 13))
                            .foregroundColor(SeekTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(highlightYellow)
                    .cornerRadius(14)

                    // Verse
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Verse")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(SeekTheme.textSecondary)
                            .textCase(.uppercase)
                            .tracking(0.5)

                        Text(record.verseText)
                            .font(.custom("Georgia", size: 16))
                            .lineSpacing(6)
                            .foregroundColor(SeekTheme.textPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(highlightYellow)
                    .cornerRadius(14)

                    // Actions
                    VStack(spacing: 12) {
                        // Copy button - plain text only
                        Button {
                            CopyUtility.copyHighlight(
                                reference: record.reference,
                                verseText: record.verseText,
                                scriptureName: record.textName
                            )
                        } label: {
                            HStack {
                                Image(systemName: "doc.on.doc")
                                Text("Copy")
                            }
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(SeekTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(SeekTheme.cardBackground)
                            .cornerRadius(12)
                        }

                        Button {
                            appState.removeHighlightByVerseId(record.verseId)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "highlighter")
                                Text("Remove Highlight")
                            }
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(SeekTheme.cardBackground)
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(20)
            }
            .themedScreenBackground()
            .navigationTitle("Highlight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(SeekTheme.maroonAccent)
                }
                ToolbarItem(placement: .primaryAction) {
                    // Share button in toolbar - branded card
                    Button {
                        ShareImageGenerator.shared.shareHighlight(
                            reference: record.reference,
                            verseText: record.verseText,
                            scriptureName: record.textName
                        )
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16))
                            .foregroundColor(SeekTheme.maroonAccent)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Guided Session Detail Screen

struct GuidedSessionDetailScreen: View {
    let session: GuidedSession
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var showResumeSheet = false
    @State private var showDeleteConfirmation = false

    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: session.updatedAt, relativeTo: Date())
    }

    private var scopeLabel: String {
        switch session.scope {
        case .chapter:
            return "Full Chapter"
        case .range:
            if let range = session.verseRange {
                return "Verses \(range.lowerBound)-\(range.upperBound)"
            }
            return "Verse Range"
        case .selected:
            return "Selected Verses"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Session Header
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(SeekTheme.maroonAccent)
                                Text(session.reference)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(SeekTheme.maroonAccent)
                            }

                            Spacer()

                            Text(scopeLabel)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(SeekTheme.maroonAccent.opacity(0.8))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(SeekTheme.maroonAccent.opacity(0.1))
                                .cornerRadius(8)
                        }

                        Text(session.title)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(SeekTheme.textPrimary)

                        Text("Last updated \(timeAgo)")
                            .font(.system(size: 13))
                            .foregroundColor(SeekTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(SeekTheme.cardBackground)
                    .cornerRadius(14)

                    // Action Buttons
                    HStack(spacing: 12) {
                        Button {
                            showResumeSheet = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 14))
                                Text("Resume Session")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(SeekTheme.maroonAccent)
                            .cornerRadius(12)
                        }

                        Button {
                            showDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.red)
                                .frame(width: 48, height: 48)
                                .background(SeekTheme.cardBackground)
                                .cornerRadius(12)
                        }
                    }

                    // Conversation Transcript
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Conversation")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(SeekTheme.textSecondary)
                            .textCase(.uppercase)
                            .tracking(0.5)

                        if session.messages.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 32, weight: .light))
                                    .foregroundColor(SeekTheme.textSecondary.opacity(0.5))
                                Text("No messages yet")
                                    .font(.system(size: 14))
                                    .foregroundColor(SeekTheme.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            VStack(spacing: 16) {
                                ForEach(session.messages) { message in
                                    SessionMessageBubble(message: message)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(SeekTheme.cardBackground)
                    .cornerRadius(14)
                }
                .padding(20)
            }
            .themedScreenBackground()
            .navigationTitle("Session Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(SeekTheme.maroonAccent)
                }
            }
            .alert("Delete Session", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    appState.deleteGuidedSession(session.id)
                    dismiss()
                }
            } message: {
                Text("Are you sure you want to delete this session? This action cannot be undone.")
            }
            .fullScreenCover(isPresented: $showResumeSheet) {
                ResumeSessionView(session: session)
                    .environmentObject(appState)
            }
        }
    }
}

// MARK: - Session Message Bubble

private struct SessionMessageBubble: View {
    let message: GuidedSessionMessage

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: message.timestamp)
    }

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
            HStack {
                if message.role == .user { Spacer(minLength: 40) }

                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundColor(message.role == .user ? .white : SeekTheme.textPrimary)
                    .lineSpacing(4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(message.role == .user ? SeekTheme.maroonAccent : SeekTheme.creamBackground)
                    .cornerRadius(16)

                if message.role == .assistant { Spacer(minLength: 40) }
            }

            Text(timeString)
                .font(.system(size: 10))
                .foregroundColor(SeekTheme.textSecondary.opacity(0.7))
                .padding(.horizontal, 4)
        }
    }
}

// MARK: - Resume Session View

private struct ResumeSessionView: View {
    let session: GuidedSession
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var context: GuidedStudyContext?
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: SeekTheme.maroonAccent))
                    Text("Loading session...")
                        .font(.system(size: 14))
                        .foregroundColor(SeekTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .themedScreenBackground()
            } else if let error = loadError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(SeekTheme.maroonAccent)
                    Text(error)
                        .font(.system(size: 14))
                        .foregroundColor(SeekTheme.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("Close") { dismiss() }
                        .foregroundColor(SeekTheme.maroonAccent)
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .themedScreenBackground()
            } else if let ctx = context {
                GuidedStudyScreen(context: ctx, appState: appState, existingSession: session)
                    .environmentObject(appState)
            }
        }
        .onAppear {
            loadContext()
        }
    }

    private func loadContext() {
        let verses = VerseLoader.shared.load(
            scriptureId: session.scriptureId,
            bookId: session.book.lowercased().replacingOccurrences(of: " ", with: "-"),
            chapter: session.chapter
        )

        if verses.isEmpty {
            loadError = "Could not load verses for this session. The scripture data may have changed."
            isLoading = false
            return
        }

        let chapterRef = ChapterRef(
            scriptureId: session.scriptureId,
            bookId: session.book.lowercased().replacingOccurrences(of: " ", with: "-"),
            chapterNumber: session.chapter,
            bookName: session.book
        )

        var selectedIds: Set<String> = []
        if session.scope == .selected || session.scope == .range, let range = session.verseRange {
            selectedIds = Set(verses.filter { range.contains($0.number) }.map { $0.id })
        }

        context = GuidedStudyContext(
            chapterRef: chapterRef,
            verses: verses,
            selectedVerseIds: selectedIds,
            textName: "",
            traditionId: "",
            traditionName: ""
        )

        isLoading = false
    }
}

#Preview {
    NavigationStack {
        JourneyScreen()
            .environmentObject(AppState())
    }
}

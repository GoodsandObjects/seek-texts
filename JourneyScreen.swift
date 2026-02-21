//
//  JourneyScreen.swift
//  Seek
//
//  Journey screen with time-based grouping, search, and advanced filters.
//

import SwiftUI
import UIKit

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
    @ObservedObject private var streakManager = StreakManager.shared
    @StateObject private var journeyStore: JourneyStore
    @StateObject private var studyStore = StudyStore.shared
    @State private var searchText = ""
    @State private var selectedFilter: JourneyFilter = .all
    @State private var selectedNoteRecord: JourneyRecord?
    @State private var selectedHighlightRecord: JourneyRecord?
    @State private var expandedDaySections: Set<String> = []
    @State private var hasInitializedDisclosureState = false
    @State private var showFirstDayModal = false

    init() {
        // Initialize with a temporary AppState; the real one is injected via environment
        _journeyStore = StateObject(wrappedValue: JourneyStore(appState: AppState()))
    }

    private var hasAnyContent: Bool {
        !appState.journeyRecords.isEmpty || !studyStore.conversations.isEmpty
    }

    private var journeyItems: [JourneyFeedItem] {
        var items: [JourneyFeedItem] = []

        if selectedFilter == .all || selectedFilter == .sessions {
            items.append(contentsOf: sessionItems)
        }

        if selectedFilter == .all || selectedFilter == .highlights || selectedFilter == .notes {
            items.append(contentsOf: recordItems)
        }

        return items
    }

    private var sessionItems: [JourneyFeedItem] {
        let sessions = studyStore.conversations.sorted { $0.updatedAt > $1.updatedAt }
        return sessions.compactMap { session in
            guard matchesSearch(session: session) else { return nil }
            return JourneyFeedItem(
                id: "session-\(session.id.uuidString)",
                kind: .session,
                title: displaySessionTitle(for: session),
                subtitle: conversationReference(session),
                date: session.updatedAt,
                route: sessionRoute(session),
                sessionId: session.id,
                recordId: nil
            )
        }
    }

    private var recordItems: [JourneyFeedItem] {
        let records = appState.journeyRecords.sorted { $0.createdAt > $1.createdAt }
        return records.compactMap { record in
            guard matchesFilter(record: record), matchesSearch(record: record) else { return nil }
            return JourneyFeedItem(
                id: "\(record.type.rawValue)-\(record.id.uuidString)",
                kind: record.type == .highlight ? .highlight : .note,
                title: record.reference,
                subtitle: record.textName,
                date: record.createdAt,
                route: nil,
                sessionId: nil,
                recordId: record.id
            )
        }
    }

    private var dayGroups: [JourneyDaySection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: journeyItems) { item in
            calendar.startOfDay(for: item.date)
        }

        return grouped
            .map { day, items in
                JourneyDaySection(
                    day: day,
                    items: items.sorted { $0.date > $1.date }
                )
            }
            .sorted { $0.day > $1.day }
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
        .sheet(item: $selectedNoteRecord) { record in
            JourneyNoteDetailSheet(record: record)
                .environmentObject(appState)
        }
        .sheet(item: $selectedHighlightRecord) { record in
            JourneyHighlightDetailSheet(record: record)
                .environmentObject(appState)
        }
        .alert("Day 1 recorded.", isPresented: $showFirstDayModal) {
            Button("Continue", role: .cancel) { }
        } message: {
            Text("Consistency builds clarity. Your Journey tracks days you return with intention.")
        }
        .onAppear {
            syncExpandedDaySections()
            checkAndPresentFirstDayModalIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .streakDidUpdate)) { _ in
            checkAndPresentFirstDayModalIfNeeded()
        }
        .onChange(of: dayGroups.map(\.id)) { _, _ in
            syncExpandedDaySections()
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            JourneyStreakBarView(
                currentStreak: streakManager.currentStreak,
                isQualifiedToday: streakManager.isQualifiedToday,
                milestoneCopy: streakManager.milestoneCopyText,
                onShareTap: shareStreakCard
            )
                .padding(.horizontal, 20)
                .padding(.top, 8)

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
                JourneyStreakBarView(
                    currentStreak: streakManager.currentStreak,
                    isQualifiedToday: streakManager.isQualifiedToday,
                    milestoneCopy: streakManager.milestoneCopyText,
                    onShareTap: shareStreakCard
                )
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)

                // Search bar
                searchBar
                    .padding(.horizontal, 20)
                    .padding(.top, 0)

                filterSegmentedControl
                    .padding(.top, 12)
                    .padding(.horizontal, 20)

                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(dayGroups) { group in
                        dayGroupDisclosure(group)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .themedScreenBackground()
    }

    private func checkAndPresentFirstDayModalIfNeeded() {
        guard StreakManager.shared.consumeFirstQualificationModalFlag() else { return }
        showFirstDayModal = true
    }

    private func shareStreakCard() {
        ShareManager.shared.shareStreak(
            currentStreak: streakManager.currentStreak,
            isQualifiedToday: streakManager.isQualifiedToday,
            milestoneCopy: streakManager.milestoneCopyText
        )
    }

    private func presentInsightsPaywall() {
        guard !EntitlementManager.shared.isPremium else { return }
        guard let presenter = topViewController() else { return }

        let paywall = PaywallView(
            context: .shareLimit,
            streakDays: streakManager.currentStreak,
            customSubtitle: "Unlock Insights to see your consistency."
        ) { }
        let host = UIHostingController(rootView: paywall)
        host.modalPresentationStyle = .fullScreen
        presenter.present(host, animated: true)
    }

    private func topViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return nil
        }

        var topController = window.rootViewController
        while let presented = topController?.presentedViewController {
            topController = presented
        }
        return topController
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
        .shadow(color: Color.black.opacity(0.02), radius: 3, x: 0, y: 1)
    }

    // MARK: - Filters

    private var filterSegmentedControl: some View {
        Picker("Journey Filter", selection: $selectedFilter) {
            ForEach(JourneyFilter.allCases, id: \.self) { filter in
                Text(filter.rawValue).tag(filter)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Grouped Sections

    private func dayGroupDisclosure(_ group: JourneyDaySection) -> some View {
        DisclosureGroup(isExpanded: disclosureBinding(for: group.id)) {
            LazyVStack(spacing: 8) {
                ForEach(group.items) { item in
                    dayItemRow(item)
                }
            }
            .padding(.top, 4)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(dayTitle(for: group.day))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(SeekTheme.textSecondary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 2)
        }
        .disclosureGroupStyle(MinimalDisclosureGroupStyle())
    }

    private func disclosureBinding(for groupID: String) -> Binding<Bool> {
        Binding(
            get: { expandedDaySections.contains(groupID) },
            set: { isExpanded in
                if isExpanded {
                    expandedDaySections.insert(groupID)
                } else {
                    expandedDaySections.remove(groupID)
                }
            }
        )
    }

    @ViewBuilder
    private func dayItemRow(_ item: JourneyFeedItem) -> some View {
        switch item.kind {
        case .session:
            let route = item.route ?? .error(
                title: "Invalid Session",
                message: "This session can't be opened. It may have been created with an older version."
            )
            NavigationLink {
                routeDestinationView(route)
            } label: {
                if let session = session(for: item) {
                    GuidedSessionRow(
                        session: session,
                        displayTitle: displaySessionTitle(for: session),
                        referenceText: conversationReference(session)
                    )
                        .contentShape(Rectangle())
                } else {
                    MissingSessionRow(title: item.title, subtitle: item.subtitle)
                        .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)

        case .highlight, .note:
            if let record = record(for: item) {
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
                        Button {
                            ShareImageGenerator.shared.shareJourneyRecord(record)
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            CopyUtility.copyJourneyRecord(record)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }

                        Divider()

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

    private func countForFilter(_ filter: JourneyFilter) -> Int? {
        switch filter {
        case .all:
            return nil
        case .sessions:
            return studyStore.conversations.count > 0 ? studyStore.conversations.count : nil
        case .highlights:
            let count = appState.journeyRecords.filter { $0.type == .highlight }.count
            return count > 0 ? count : nil
        case .notes:
            let count = appState.journeyRecords.filter { $0.type == .note }.count
            return count > 0 ? count : nil
        }
    }

    private func matchesFilter(record: JourneyRecord) -> Bool {
        switch selectedFilter {
        case .all:
            return true
        case .sessions:
            return false
        case .highlights:
            return record.type == .highlight
        case .notes:
            return record.type == .note
        }
    }

    private func matchesSearch(record: JourneyRecord) -> Bool {
        guard !searchText.isEmpty else { return true }
        return record.reference.localizedCaseInsensitiveContains(searchText) ||
            record.verseText.localizedCaseInsensitiveContains(searchText) ||
            (record.noteText?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            record.textName.localizedCaseInsensitiveContains(searchText)
    }

    private func matchesSearch(session: StudyConversation) -> Bool {
        guard !searchText.isEmpty else { return true }
        return displaySessionTitle(for: session).localizedCaseInsensitiveContains(searchText) ||
            conversationReference(session).localizedCaseInsensitiveContains(searchText) ||
            StudyStore.shared.loadMessages(conversationId: session.id).contains { $0.content.localizedCaseInsensitiveContains(searchText) }
    }

    private func session(for item: JourneyFeedItem) -> StudyConversation? {
        guard let sessionId = item.sessionId else { return nil }
        return studyStore.conversations.first(where: { $0.id == sessionId })
    }

    private func record(for item: JourneyFeedItem) -> JourneyRecord? {
        guard let recordId = item.recordId else { return nil }
        return appState.journeyRecords.first(where: { $0.id == recordId })
    }

    private func dayTitle(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) {
            return "Today"
        }
        if calendar.isDateInYesterday(day) {
            return "Yesterday"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: day)
    }

    private func syncExpandedDaySections() {
        let availableIDs = Set(dayGroups.map(\.id))
        expandedDaySections = expandedDaySections.intersection(availableIDs)

        guard !hasInitializedDisclosureState else { return }
        hasInitializedDisclosureState = true

        let todayID = todayGroupID()
        if availableIDs.contains(todayID) {
            expandedDaySections.insert(todayID)
        }
    }

    private func todayGroupID() -> String {
        let today = Calendar.current.startOfDay(for: Date())
        return JourneyDaySection(day: today, items: []).id
    }

    private func conversationReference(_ conversation: StudyConversation) -> String {
        if case .general = conversation.context {
            return "General Conversation"
        }
        let bookName = normalizedBookName(for: conversation)
        if let start = conversation.verseStart, let end = conversation.verseEnd {
            return start == end
                ? "\(bookName) \(conversation.chapter):\(start)"
                : "\(bookName) \(conversation.chapter):\(start)-\(end)"
        }
        return "\(bookName) \(conversation.chapter)"
    }

    private func displaySessionTitle(for session: StudyConversation) -> String {
        let trimmedTitle = session.title.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedTitle.isEmpty && !isPlaceholderTitle(trimmedTitle) {
            return trimmedTitle
        }

        return conversationReference(session)
    }

    private func isPlaceholderTitle(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "test" || normalized == "untitled" || normalized == "new session"
    }

    private func normalizedBookName(for session: StudyConversation) -> String {
        if case .general = session.context {
            return "General Conversation"
        }
        let fallback = session.bookId
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")

        guard let scripture = LibraryData.shared.getScripture(by: session.scriptureId) else {
            return fallback
        }

        if let matched = scripture.books.first(where: { normalizeBookId($0.id) == normalizeBookId(session.bookId) }) {
            return matched.name
        }

        return fallback
    }

    private func sessionRoute(_ session: StudyConversation) -> AppRoute {
        if case .general = session.context {
            return .guidedStudy(conversationId: session.id)
        }

        guard !session.scriptureId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !session.bookId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              session.chapter > 0 else {
            return .error(
                title: "Invalid Session",
                message: "This session can't be opened. It may have been created with an older version."
            )
        }

        let hasConversation = studyStore.conversations.contains(where: { $0.id == session.id })
        guard hasConversation else {
            return .error(
                title: "Session Not Found",
                message: "This session is no longer available on this device."
            )
        }

        return .guidedStudy(conversationId: session.id)
    }

    @ViewBuilder
    private func routeDestinationView(_ route: AppRoute) -> some View {
        switch route {
        case .guidedStudy(let conversationId):
            ResumeConversationView(conversationId: conversationId)
                .environmentObject(appState)
        case .reader(let destination):
            RoutedReaderDestinationView(destination: destination)
                .environmentObject(appState)
        case .error(let title, let message):
            RouteLoadFailureView(title: title, message: message)
        }
    }

    @ViewBuilder
    private func sessionDestinationView(for session: StudyConversation) -> some View {
        routeDestinationView(sessionRoute(session))
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

private struct MinimalDisclosureGroupStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                configuration.label
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Group {
                if configuration.isExpanded {
                    configuration.content
                }
            }
            .animation(.easeInOut(duration: 0.2), value: configuration.isExpanded)
        }
    }
}

// MARK: - Guided Session Row

private struct GuidedSessionRow: View {
    let session: StudyConversation
    let displayTitle: String
    let referenceText: String

    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: session.updatedAt, relativeTo: Date())
    }

    private var messageCount: Int {
        StudyStore.shared.loadMessages(conversationId: session.id).filter { $0.role == "user" }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(referenceText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(SeekTheme.maroonAccent)

                Spacer()

                Text(timeAgo)
                    .font(.system(size: 11))
                    .foregroundColor(SeekTheme.textSecondary)
            }

            Text(displayTitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(SeekTheme.textPrimary)
                .lineLimit(2)

            HStack(spacing: 8) {
                Text("\(messageCount) messages")
                    .font(.system(size: 11))
                .foregroundColor(SeekTheme.textSecondary)
            }
        }
        .padding(15)
        .background(SeekTheme.cardBackground)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.02), radius: 4, x: 0, y: 1)
        .contentShape(Rectangle())
    }

}

private struct MissingSessionRow: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(subtitle ?? "Unavailable session")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(SeekTheme.textSecondary)

            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(SeekTheme.textPrimary)
                .lineLimit(2)
        }
        .padding(16)
        .background(SeekTheme.cardBackground)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Journey Record Row

private struct JourneyRecordRow: View {
    let record: JourneyRecord
    private let highlightYellow = Color(red: 1.0, green: 0.95, blue: 0.75)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(record.reference)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(SeekTheme.maroonAccent)
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
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 1.0, green: 0.96, blue: 0.90))
                    .cornerRadius(10)
            }
        }
        .padding(15)
        .background(record.type == .highlight ? highlightYellow : SeekTheme.cardBackground)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.02), radius: 4, x: 0, y: 1)
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
        let chapterLabel = ScriptureTerminology.chapterLabel(for: session.scriptureId)
        let verseLabel = ScriptureTerminology.verseLabel(for: session.scriptureId)
        let verseLabelPlural = ScriptureTerminology.verseLabelLowercased(for: session.scriptureId, plural: true).capitalized

        switch session.scope {
        case .chapter:
            return "Read Entire \(chapterLabel)"
        case .range:
            if let range = session.verseRange {
                return "\(verseLabelPlural) \(range.lowerBound)-\(range.upperBound)"
            }
            return "\(verseLabel) Range"
        case .selected:
            return "Selected \(verseLabelPlural)"
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
                ResumeConversationView(conversationId: session.id)
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

// MARK: - Resume Conversation View

struct ResumeConversationView: View {
    let conversationId: UUID
    @EnvironmentObject var appState: AppState

    @StateObject private var studyStore = StudyStore.shared
    @State private var conversation: StudyConversation?
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
                RouteLoadFailureView(title: "Unable to Open Session", message: error)
            } else if let ctx = context, let convo = conversation {
                GuidedStudyScreen(context: ctx, appState: appState, existingConversation: convo)
                    .environmentObject(appState)
            } else {
                RouteLoadFailureView(
                    title: "Unable to Open Session",
                    message: "This session can't be opened. It may have been created with an older version."
                )
            }
        }
        .onAppear {
            Task { await loadContext() }
        }
    }

    private func loadContext() async {
        if conversation == nil {
            studyStore.loadAllConversations()
            conversation = studyStore.conversations.first(where: { $0.id == conversationId })
        }

        guard let conversation else {
            loadError = "This session can't be opened. It may have been created with an older version."
            isLoading = false
            return
        }

        if case .general = conversation.context {
            context = GuidedStudyContext(
                chapterRef: ChapterRef(
                    scriptureId: "guided-study",
                    bookId: "general",
                    chapterNumber: 1,
                    bookName: "General Conversation"
                ),
                verses: [],
                selectedVerseIds: [],
                textName: "",
                traditionId: "",
                traditionName: ""
            )
            isLoading = false
            return
        }

        do {
            let verses = try await RemoteDataService.shared.loadChapter(
                scriptureId: conversation.scriptureId,
                bookId: conversation.bookId,
                chapter: conversation.chapter
            )

            if verses.isEmpty {
                loadError = "Could not load verses for this conversation. Please try again."
                isLoading = false
                return
            }

            let libraryData = LibraryData.shared
            let bookName = libraryData.traditions
                .flatMap(\.texts)
                .first(where: { $0.id == conversation.scriptureId })?
                .books.first(where: { normalizeBookId($0.id) == normalizeBookId(conversation.bookId) })?.name ?? conversation.bookId

            let chapterRef = ChapterRef(
                scriptureId: conversation.scriptureId,
                bookId: conversation.bookId,
                chapterNumber: conversation.chapter,
                bookName: bookName
            )

            var selectedIds: Set<String> = []
            if let start = conversation.verseStart, let end = conversation.verseEnd {
                selectedIds = Set(verses.filter { ($0.number >= start) && ($0.number <= end) }.map(\.id))
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
        } catch {
            loadError = "This session can't be opened. It may have been created with an older version."
            isLoading = false
        }
    }
}

#Preview {
    NavigationStack {
        JourneyScreen()
            .environmentObject(AppState())
    }
}

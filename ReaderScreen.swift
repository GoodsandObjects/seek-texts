//
//  ReaderScreen.swift
//  Seek
//
//  Scripture reader with continuous flowing layout.
//  Supports highlighting, notes, copy/share, multi-verse selection, and Guided Study.
//  Loads chapter content from remote with cache fallback.
//

import SwiftUI

// MARK: - Reader Load State

enum ReaderLoadState: Equatable {
    case loading
    case loaded
    case error(String)
    case offline
}

// MARK: - Reader Screen

struct ReaderScreen: View {
    let chapterRef: ChapterRef
    var book: Book? = nil
    var sacredText: SacredText? = nil
    var tradition: Tradition? = nil
    var initialVerseNumber: Int? = nil

    @EnvironmentObject var appState: AppState
    @Environment(\.openURL) private var openURL
    @ObservedObject private var streakManager = StreakManager.shared
    @State private var verses: [LoadedVerse] = []
    @State private var loadState: ReaderLoadState = .loading
    @State private var selectedVerses: Set<String> = []
    @State private var isMultiSelectMode: Bool = false
    @State private var guidedStudyContext: GuidedStudyContext?
    @State private var lastVisibleVerseNumber: Int = 1
    @State private var hasRestoredScrollPosition = false

    private let highlightYellow = Color(red: 1.0, green: 0.95, blue: 0.75)

    private var chapterLabel: String {
        ScriptureTerminology.chapterLabel(for: chapterRef.scriptureId)
    }

    private var verseLabelPluralLowercased: String {
        ScriptureTerminology.verseLabelLowercased(for: chapterRef.scriptureId, plural: true)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    VStack(alignment: .center, spacing: 10) {
                        Text(chapterRef.bookName.uppercased())
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)

                        Text("\(chapterRef.chapterNumber)")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                    .background(SeekTheme.cardBackground.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.bottom, 24)

                    switch loadState {
                    case .loading:
                        loadingView
                    case .loaded where verses.isEmpty:
                        emptyStateView
                    case .loaded:
                        continuousVersesView
                    case .error(let message):
                        errorView(message: message)
                    case .offline:
                        offlineView
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .onAppear {
                hasRestoredScrollPosition = false
                saveLastReadingState(verseStart: initialVerseNumber, verseEnd: nil)
                if let saved = preferredVerseNumber {
                    lastVisibleVerseNumber = saved
                }
                streakManager.readerDidAppear()
            }
            .onChange(of: loadState) { _, state in
                guard state == .loaded, !hasRestoredScrollPosition else { return }
                guard let targetVerse = verseForSavedPosition else { return }
                hasRestoredScrollPosition = true
                DispatchQueue.main.async {
                    withAnimation(.none) {
                        proxy.scrollTo(targetVerse.id, anchor: .top)
                    }
                }
            }
            .onChange(of: loadState) { _, _ in
                streakManager.setReaderContentVisible(loadState == .loaded && !verses.isEmpty)
            }
            .onDisappear {
                streakManager.readerDidDisappear()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: loadState)
        .animation(.easeInOut(duration: 0.2), value: verses.count)
        .animation(.easeInOut(duration: 0.2), value: isMultiSelectMode)
        .themedScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(SeekTheme.creamBackground, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if !isMultiSelectMode {
                    Button(action: { startGuidedStudy() }) {
                        Image(systemName: "sparkles")
                    }
                    .foregroundColor(SeekTheme.maroonAccent)
                    .disabled(loadState != .loaded || verses.isEmpty)
                }
            }
        }
        .overlay(alignment: .top) {
            if isMultiSelectMode {
                multiSelectToolbar
                    .padding(.top, 8)
            }
        }
        .task {
            await loadVerses()
        }
        .fullScreenCover(item: $guidedStudyContext) { context in
            GuidedStudyScreen(context: context, appState: appState)
                .environmentObject(appState)
        }
    }

    private var scrollMemoryKey: String {
        "reader.scroll.\(chapterRef.scriptureId).\(chapterRef.bookId).\(chapterRef.chapterNumber)"
    }

    private var savedVerseNumber: Int? {
        let value = UserDefaults.standard.integer(forKey: scrollMemoryKey)
        return value > 0 ? value : nil
    }

    private var preferredVerseNumber: Int? {
        initialVerseNumber ?? savedVerseNumber
    }

    private var verseForSavedPosition: LoadedVerse? {
        guard let verseNumber = preferredVerseNumber else { return nil }
        return verses.first(where: { $0.number == verseNumber }) ?? verses.first
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 14) {
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 8)
                    .fill(SeekTheme.cardBackground)
                    .frame(height: 18)
                    .redacted(reason: .placeholder)
            }

            Text("Loading \(verseLabelPluralLowercased)...")
                .font(.system(size: 14))
                .foregroundColor(SeekTheme.textSecondary)
        }
        .padding(.horizontal, SeekTheme.screenHorizontalPadding)
        .padding(.vertical, 28)
    }

    // MARK: - Failure Actions

    private var failureActions: some View {
        HStack(spacing: 12) {
            Button {
                Task { await loadVerses() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(SeekTheme.maroonAccent)
                .cornerRadius(10)
            }

            Button {
                reportIssue()
            } label: {
                Text("Report issue")
                .font(.system(size: 15))
                .foregroundColor(SeekTheme.maroonAccent)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(SeekTheme.maroonAccent.opacity(0.1))
                .cornerRadius(10)
            }
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(SeekTheme.maroonAccent.opacity(0.08))
                    .frame(width: 80, height: 80)

                Image(systemName: "text.page")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(SeekTheme.maroonAccent)
            }

            Text("Content not available")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(SeekTheme.textPrimary)

            Text("This \(chapterLabel.lowercased()) could not be loaded from local or remote data.")
                .font(.system(size: 14))
                .foregroundColor(SeekTheme.textSecondary)
                .multilineTextAlignment(.center)

            failureActions
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, SeekTheme.screenHorizontalPadding)
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.08))
                    .frame(width: 80, height: 80)

                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(.red.opacity(0.8))
            }

            Text("Unable to load chapter")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(SeekTheme.textPrimary)

            Text("Unable to load this \(chapterLabel.lowercased()). Please retry or report the issue.")
                .font(.system(size: 14))
                .foregroundColor(SeekTheme.textSecondary)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.system(size: 12))
                .foregroundColor(SeekTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            failureActions
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, SeekTheme.screenHorizontalPadding)
    }

    // MARK: - Offline View

    private var offlineView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(SeekTheme.maroonAccent.opacity(0.08))
                    .frame(width: 80, height: 80)

                Image(systemName: "wifi.slash")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(SeekTheme.maroonAccent)
            }

            Text("You're offline")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(SeekTheme.textPrimary)

            Text("Connect to the internet to load this \(chapterLabel.lowercased()). Previously read \(chapterLabel.lowercased())s are available offline.")
                .font(.system(size: 14))
                .foregroundColor(SeekTheme.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await loadVerses() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(SeekTheme.maroonAccent)
                .cornerRadius(10)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, SeekTheme.screenHorizontalPadding)
    }

    // MARK: - Continuous Verses View (Premium Reading Experience)

    private var continuousVersesView: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(verses, id: \.id) { verse in
                ContinuousVerseRow(
                    verse: verse,
                    chapterRef: chapterRef,
                    traditionName: tradition?.name ?? "",
                    textName: sacredText?.name ?? "",
                    isSelected: selectedVerses.contains(verse.id),
                    isMultiSelectMode: isMultiSelectMode,
                    onTap: {
                        if isMultiSelectMode {
                            toggleVerseSelection(verse.id)
                        }
                    },
                    onSelectMultiple: {
                        if !isMultiSelectMode {
                            isMultiSelectMode = true
                        }
                        selectedVerses.insert(verse.id)
                    },
                    onStartGuidedStudy: {
                        startGuidedStudyForVerse(verse)
                    },
                    onReaderInteraction: {
                        streakManager.recordReaderInteraction()
                    },
                    onVerseIntent: {
                        streakManager.recordVerseInteraction(verseId: verse.id)
                    }
                )
                .id(verse.id)
                .onAppear {
                    lastVisibleVerseNumber = verse.number
                    UserDefaults.standard.set(verse.number, forKey: scrollMemoryKey)
                    saveLastReadingState(verseStart: verse.number, verseEnd: nil)
                    streakManager.recordVerseBecameVisible(verseId: verse.id)
                }
                .onDisappear {
                    streakManager.recordVerseNoLongerVisible(verseId: verse.id)
                }
                .padding(.bottom, verse.number % 5 == 0 ? 6 : 0)
            }
        }
    }

    // MARK: - Load Verses

    private func loadVerses() async {
        loadState = .loading

        #if DEBUG
        print("[ReaderScreen] Loading: \(chapterRef.scriptureId)/\(chapterRef.bookId)/\(chapterRef.chapterNumber)")
        #endif

        do {
            let loadedVerses = try await RemoteDataService.shared.loadChapter(
                scriptureId: chapterRef.scriptureId,
                bookId: chapterRef.bookId,
                chapter: chapterRef.chapterNumber
            )
            verses = loadedVerses
            loadState = .loaded

            #if DEBUG
            print("[ReaderScreen] Loaded \(verses.count) verses")
            #endif
        } catch {
            #if DEBUG
            print("[ReaderScreen] Failed to load: \(error.localizedDescription)")
            #endif

            if shouldUseConnectivityFallback(error), let cached = RemoteDataService.shared.getCachedChapter(
                scriptureId: chapterRef.scriptureId,
                bookId: chapterRef.bookId,
                chapter: chapterRef.chapterNumber
            ), !cached.isEmpty {
                verses = cached
                loadState = .loaded
            } else {
                loadState = .error(error.localizedDescription)
            }
        }
    }

    private func shouldUseConnectivityFallback(_ error: Error) -> Bool {
        guard let remoteError = error as? RemoteDataError else {
            return false
        }
        switch remoteError {
        case .offline, .networkError, .allURLsFailed:
            return true
        default:
            return false
        }
    }

    private func saveLastReadingState(verseStart: Int?, verseEnd: Int?) {
        LastReadingStore.saveLastReadingState(
            LastReadingState(
                scriptureId: chapterRef.scriptureId,
                bookId: chapterRef.bookId,
                chapter: chapterRef.chapterNumber,
                verseStart: verseStart,
                verseEnd: verseEnd,
                timestamp: Date()
            )
        )
    }

    private func reportIssue() {
        let subject = "Seek content issue: \(chapterRef.scriptureId) \(chapterRef.bookId) \(chapterRef.chapterNumber)"
        let body = """
        I ran into a loading issue.

        Scripture: \(chapterRef.scriptureId)
        Book: \(chapterRef.bookId)
        \(chapterLabel): \(chapterRef.chapterNumber)
        """
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:support@seek.app?subject=\(encodedSubject)&body=\(encodedBody)") {
            openURL(url)
        }
    }

    // MARK: - Multi-Verse Actions

    private func toggleVerseSelection(_ verseId: String) {
        if selectedVerses.contains(verseId) {
            selectedVerses.remove(verseId)
            if selectedVerses.isEmpty {
                isMultiSelectMode = false
            }
        } else {
            selectedVerses.insert(verseId)
        }
    }

    private func copySelectedVerses() {
        let selectedTexts = verses
            .filter { selectedVerses.contains($0.id) }
            .sorted { $0.number < $1.number }
            .map { verse in
                "\(chapterRef.bookName) \(chapterRef.chapterNumber):\(verse.number)\n\(verse.text)"
            }
            .joined(separator: "\n\n")

        let textToCopy = "\(selectedTexts)\n— \(sacredText?.name ?? "")"
        UIPasteboard.general.string = textToCopy

        selectedVerses.removeAll()
        isMultiSelectMode = false
    }

    private func shareSelectedVerses() {
        let selectedList = verses
            .filter { selectedVerses.contains($0.id) }
            .sorted { $0.number < $1.number }
            .map { (number: $0.number, text: $0.text) }

        guard !selectedList.isEmpty else { return }

        Task { @MainActor in
            ShareImageGenerator.shared.shareMultipleVerses(
                bookName: chapterRef.bookName,
                chapterNumber: chapterRef.chapterNumber,
                verses: selectedList,
                scriptureName: sacredText?.name ?? ""
            )
        }

        selectedVerses.removeAll()
        isMultiSelectMode = false
    }

    private func highlightSelectedVerses() {
        for verseId in selectedVerses {
            if let verse = verses.first(where: { $0.id == verseId }) {
                let reference = "\(chapterRef.bookName) \(chapterRef.chapterNumber):\(verse.number)"
                if appState.highlights.contains(verseId) {
                    continue
                }

                guard UsageLimitManager.shared.canPerform(.saveHighlight) else {
                    appState.presentPaywall(.highlightLimit)
                    break
                }

                appState.toggleHighlight(
                    verseId,
                    reference: reference,
                    verseText: verse.text,
                    religion: tradition?.name ?? "",
                    textName: sacredText?.name ?? ""
                )
            }
        }

        selectedVerses.removeAll()
        isMultiSelectMode = false
    }

    private func startGuidedStudyForSelection() {
        guard !selectedVerses.isEmpty else { return }
        startGuidedStudy()
    }

    @ViewBuilder
    private var multiSelectToolbar: some View {
        HStack(spacing: 8) {
            Button {
                startGuidedStudyForSelection()
            } label: {
                multiSelectToolbarItem(title: "Study", systemImage: "sparkles")
            }
            .disabled(selectedVerses.isEmpty)
            .frame(maxWidth: .infinity)
            .buttonStyle(.plain)

            Button {
                highlightSelectedVerses()
            } label: {
                multiSelectToolbarItem(title: "Highlight", systemImage: "highlighter")
            }
            .disabled(selectedVerses.isEmpty)
            .frame(maxWidth: .infinity)
            .buttonStyle(.plain)

            Button {
                shareSelectedVerses()
            } label: {
                multiSelectToolbarItem(title: "Share", systemImage: "square.and.arrow.up")
            }
            .disabled(selectedVerses.isEmpty)
            .frame(maxWidth: .infinity)
            .buttonStyle(.plain)

            Button {
                selectedVerses.removeAll()
                isMultiSelectMode = false
            } label: {
                multiSelectToolbarItem(title: "Cancel", systemImage: "xmark")
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .buttonStyle(.plain)
        }
        .foregroundColor(SeekTheme.maroonAccent)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(SeekTheme.textSecondary.opacity(0.12), lineWidth: 0.8)
        )
        .shadow(color: SeekTheme.cardShadow.opacity(1.1), radius: 8, x: 0, y: 2)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func multiSelectToolbarItem(title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .lineLimit(1)
        }
            .font(.system(size: 12, weight: .semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
    }

    // MARK: - Guided Study Actions

    /// Opens Guided Study with context based on current selection state.
    /// - If verses are selected: defaults to selected verses scope
    /// - Otherwise: defaults to whole chapter scope
    private func startGuidedStudy() {
        // Guard: Don't open Guided Study if verses haven't loaded yet
        guard !verses.isEmpty else {
            #if DEBUG
            print("[GuidedStudy] Cannot start: verses not loaded yet")
            print("[GuidedStudy]   scriptureId: \(chapterRef.scriptureId)")
            print("[GuidedStudy]   bookId: \(chapterRef.bookId)")
            print("[GuidedStudy]   chapter: \(chapterRef.chapterNumber)")
            #endif
            return
        }

        // Capture selected verses before clearing
        let capturedSelectedVerses = selectedVerses

        // Clear selection after capturing
        if !selectedVerses.isEmpty {
            selectedVerses.removeAll()
            isMultiSelectMode = false
        }

        // Create context - this automatically opens the fullScreenCover via item binding
        let context = GuidedStudyContext(
            chapterRef: chapterRef,
            verses: verses,
            selectedVerseIds: capturedSelectedVerses,
            textName: sacredText?.name ?? "",
            traditionId: tradition?.id ?? "",
            traditionName: tradition?.name ?? ""
        )

        #if DEBUG
        let passage = context.buildPassage(scope: capturedSelectedVerses.isEmpty ? .chapter : .selected)
        print("[GuidedStudy] Starting Guided Study:")
        print("[GuidedStudy]   scriptureId: \(chapterRef.scriptureId)")
        print("[GuidedStudy]   bookId: \(chapterRef.bookId)")
        print("[GuidedStudy]   chapter: \(chapterRef.chapterNumber)")
        print("[GuidedStudy]   verses loaded: \(verses.count)")
        print("[GuidedStudy]   selected verse IDs: \(capturedSelectedVerses.count)")
        print("[GuidedStudy]   passage reference: \(passage.reference)")
        print("[GuidedStudy]   passage text length: \(passage.verseText.count) chars")
        #endif

        guidedStudyContext = context
    }

    /// Opens Guided Study scoped to a single verse (from context menu).
    private func startGuidedStudyForVerse(_ verse: LoadedVerse) {
        let context = GuidedStudyContext(
            chapterRef: chapterRef,
            verses: verses,
            selectedVerseIds: Set([verse.id]),
            textName: sacredText?.name ?? "",
            traditionId: tradition?.id ?? "",
            traditionName: tradition?.name ?? ""
        )

        #if DEBUG
        let passage = context.buildPassage(scope: .selected)
        print("[GuidedStudy] Starting for single verse:")
        print("[GuidedStudy]   verse: \(verse.number)")
        print("[GuidedStudy]   reference: \(passage.reference)")
        print("[GuidedStudy]   text length: \(passage.verseText.count) chars")
        #endif

        guidedStudyContext = context
    }
}

// MARK: - Continuous Verse Row (Clean Reading Layout)

struct ContinuousVerseRow: View {
    let verse: LoadedVerse
    let chapterRef: ChapterRef
    let traditionName: String
    let textName: String
    let isSelected: Bool
    let isMultiSelectMode: Bool
    let onTap: () -> Void
    let onSelectMultiple: () -> Void
    let onStartGuidedStudy: () -> Void
    let onReaderInteraction: () -> Void
    let onVerseIntent: () -> Void

    @EnvironmentObject var appState: AppState
    @State private var showNoteSheet = false
    @State private var noteText = ""
    @State private var showContextMenu = false

    private var verseId: String { verse.id }

    private var reference: String {
        "\(chapterRef.bookName) \(chapterRef.chapterNumber):\(verse.number)"
    }

    private var isHighlighted: Bool {
        appState.highlights.contains(verseId)
    }

    private var hasNote: Bool {
        appState.notes[verseId] != nil
    }

    private let highlightYellow = Color(red: 1.0, green: 0.95, blue: 0.75)
    private let selectionBlue = Color.blue.opacity(0.1)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Main verse content in a horizontal flow
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                // Verse number (small, muted)
                Text("\(verse.number)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .baselineOffset(2)
                    .frame(width: 26, alignment: .trailing)
                    .padding(.trailing, 4)

                // Verse text
                VStack(alignment: .leading, spacing: 3) {
                    Text(verse.text)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(SeekTheme.textPrimary)
                        .lineSpacing(7)
                        .frame(maxWidth: 680, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)

                    // Inline indicators
                    HStack(spacing: 6) {
                        if isHighlighted {
                            Image(systemName: "highlighter")
                                .font(.system(size: 10))
                                .foregroundColor(SeekTheme.maroonAccent.opacity(0.6))
                        }
                        if hasNote {
                            Image(systemName: "note.text")
                                .font(.system(size: 10))
                                .foregroundColor(SeekTheme.maroonAccent.opacity(0.6))
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

            // Display note if exists (compact)
            if let note = appState.notes[verseId], !note.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(SeekTheme.maroonAccent.opacity(0.5))
                        .frame(width: 3)
                    Text(note)
                        .font(.system(size: 13))
                        .foregroundColor(SeekTheme.textSecondary)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(SeekTheme.cardBackground.opacity(0.55))
                .cornerRadius(6)
                .padding(.leading, 32)
            }
        }
        .padding(.vertical, 8)
        .padding(.bottom, 8)
        .background(
            Group {
                if isSelected {
                    selectionBlue
                } else if isHighlighted {
                    highlightYellow
                } else {
                    Color.clear
                }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onReaderInteraction()
            if isMultiSelectMode {
                onVerseIntent()
                onTap()
            }
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            onVerseIntent()
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            showContextMenu = true
        }
        .confirmationDialog("\(ScriptureTerminology.verseLabel(for: chapterRef.scriptureId)) \(verse.number)", isPresented: $showContextMenu, titleVisibility: .visible) {
            Button("Share verse") {
                onVerseIntent()
                shareVerse()
            }

            Button(isHighlighted ? "Remove Highlight" : "Highlight") {
                onReaderInteraction()
                if isHighlighted {
                    // Always allow removing highlights
                    appState.toggleHighlight(
                        verseId,
                        reference: reference,
                        verseText: verse.text,
                        religion: traditionName,
                        textName: textName
                    )
                } else if appState.canAddHighlight() {
                    appState.toggleHighlight(
                        verseId,
                        reference: reference,
                        verseText: verse.text,
                        religion: traditionName,
                        textName: textName
                    )
                } else {
                    appState.presentPaywall(.highlightLimit)
                }
            }

            Button(hasNote ? "Edit Note" : "Add Note") {
                onReaderInteraction()
                if hasNote || UsageLimitManager.shared.canPerform(.saveNote) {
                    noteText = appState.notes[verseId] ?? ""
                    showNoteSheet = true
                } else {
                    appState.presentPaywall(.noteLimit)
                }
            }

            Button("Study this verse") {
                onVerseIntent()
                onStartGuidedStudy()
            }

            Button("Select multiple") {
                onReaderInteraction()
                onSelectMultiple()
            }

            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $showNoteSheet) {
            NoteEditorSheet(
                verseId: verseId,
                scriptureId: chapterRef.scriptureId,
                reference: reference,
                verseText: verse.text,
                religion: traditionName,
                textName: textName,
                noteText: $noteText
            )
        }
    }

    private func shareVerse() {
        let noteForShare = appState.notes[verseId]

        Task { @MainActor in
            ShareImageGenerator.shared.shareSingleVerse(
                reference: reference,
                verseText: verse.text,
                scriptureName: textName,
                noteText: noteForShare
            )
        }
    }
}

// MARK: - Note Editor Sheet

struct NoteEditorSheet: View {
    let verseId: String
    let scriptureId: String
    let reference: String
    let verseText: String
    let religion: String
    let textName: String
    @Binding var noteText: String

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    private var verseLabel: String {
        ScriptureTerminology.verseLabel(for: scriptureId)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Reference header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(reference)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(SeekTheme.maroonAccent)

                        Text(textName)
                            .font(.system(size: 13))
                            .foregroundColor(SeekTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(SeekTheme.cardBackground)
                    .cornerRadius(14)

                    // Verse text
                    VStack(alignment: .leading, spacing: 10) {
                        Text(verseLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(SeekTheme.textSecondary)
                            .textCase(.uppercase)
                            .tracking(0.5)

                        Text(verseText)
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

                        TextEditor(text: $noteText)
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

                    // Save button
                    Button {
                        if appState.notes[verseId] != nil || UsageLimitManager.shared.canPerform(.saveNote) {
                            appState.setNote(
                                verseId,
                                noteText,
                                reference: reference,
                                verseText: verseText,
                                religion: religion,
                                textName: textName
                            )
                        } else {
                            appState.presentPaywall(.noteLimit)
                            return
                        }
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("Save Note")
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(SeekTheme.maroonAccent)
                        .cornerRadius(12)
                    }

                    // Delete note button (only if note exists)
                    if appState.notes[verseId] != nil {
                        Button {
                            appState.removeNoteByVerseId(verseId)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Note")
                            }
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(SeekTheme.maroonAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(SeekTheme.maroonAccent.opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(20)
            }
            .themedScreenBackground()
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(SeekTheme.maroonAccent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ReaderScreen(chapterRef: ChapterRef(
            scriptureId: "bible-kjv",
            bookId: "genesis",
            chapterNumber: 1,
            bookName: "Genesis"
        ))
    }
    .environmentObject(AppState())
}

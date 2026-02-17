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

    @EnvironmentObject var appState: AppState
    @Environment(\.openURL) private var openURL
    @State private var verses: [LoadedVerse] = []
    @State private var loadState: ReaderLoadState = .loading
    @State private var selectedVerses: Set<String> = []
    @State private var isMultiSelectMode: Bool = false
    @State private var guidedStudyContext: GuidedStudyContext?

    private let highlightYellow = Color(red: 1.0, green: 0.95, blue: 0.75)

    private var chapterLabel: String {
        ScriptureTerminology.chapterLabel(for: chapterRef.scriptureId)
    }

    private var verseLabelPluralLowercased: String {
        ScriptureTerminology.verseLabelLowercased(for: chapterRef.scriptureId, plural: true)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text(chapterRef.bookName)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(SeekTheme.textPrimary)

                    Text("\(chapterLabel) \(chapterRef.chapterNumber)")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(SeekTheme.maroonAccent)
                }
                .padding(.horizontal, SeekTheme.screenHorizontalPadding)
                .padding(.top, 16)
                .padding(.bottom, 20)

                Rectangle()
                    .fill(SeekTheme.maroonAccent.opacity(0.15))
                    .frame(height: 1)
                    .padding(.horizontal, SeekTheme.screenHorizontalPadding)

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
        }
        .themedScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(SeekTheme.creamBackground, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if !selectedVerses.isEmpty {
                    // Multi-verse actions when in selection mode
                    Button(action: copySelectedVerses) {
                        Image(systemName: "doc.on.doc")
                    }
                    .foregroundColor(SeekTheme.maroonAccent)

                    Button(action: shareSelectedVerses) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .foregroundColor(SeekTheme.maroonAccent)

                    Button(action: highlightSelectedVerses) {
                        Image(systemName: "highlighter")
                    }
                    .foregroundColor(SeekTheme.maroonAccent)

                    Button(action: { startGuidedStudy() }) {
                        Image(systemName: "sparkles")
                    }
                    .foregroundColor(SeekTheme.maroonAccent)

                    Button("Clear") {
                        selectedVerses.removeAll()
                        isMultiSelectMode = false
                    }
                    .foregroundColor(SeekTheme.maroonAccent)
                } else {
                    // Default toolbar: Guided Study button opens directly
                    Button(action: { startGuidedStudy() }) {
                        Image(systemName: "sparkles")
                    }
                    .foregroundColor(SeekTheme.maroonAccent)
                    .disabled(loadState != .loaded || verses.isEmpty)
                }
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

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: SeekTheme.maroonAccent))
                .scaleEffect(1.2)

            Text("Loading \(verseLabelPluralLowercased)...")
                .font(.system(size: 15))
                .foregroundColor(SeekTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
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
            ForEach(Array(verses.enumerated()), id: \.element.id) { index, verse in
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
                    onLongPress: {
                        isMultiSelectMode = true
                        selectedVerses.insert(verse.id)
                    },
                    onStartGuidedStudy: {
                        startGuidedStudyForVerse(verse)
                    }
                )

                // Subtle divider between verses (not after last)
                if index < verses.count - 1 {
                    Rectangle()
                        .fill(SeekTheme.maroonAccent.opacity(0.08))
                        .frame(height: 1)
                        .padding(.horizontal, SeekTheme.screenHorizontalPadding)
                        .padding(.vertical, 4)
                }
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 40)
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
                if appState.canAddHighlight() || appState.highlights.contains(verseId) {
                    if !appState.highlights.contains(verseId) {
                        appState.toggleHighlight(
                            verseId,
                            reference: reference,
                            verseText: verse.text,
                            religion: tradition?.name ?? "",
                            textName: sacredText?.name ?? ""
                        )
                    }
                }
            }
        }

        selectedVerses.removeAll()
        isMultiSelectMode = false
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
    let onLongPress: () -> Void
    let onStartGuidedStudy: () -> Void

    @EnvironmentObject var appState: AppState
    @State private var showNoteSheet = false
    @State private var noteText = ""
    @State private var showContextMenu = false
    @State private var showHighlightPaywall = false
    @State private var showNotePaywall = false

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
        VStack(alignment: .leading, spacing: 6) {
            // Main verse content in a horizontal flow
            HStack(alignment: .top, spacing: 8) {
                // Verse number (small, muted)
                Text("\(verse.number)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(SeekTheme.maroonAccent.opacity(0.7))
                    .frame(width: 24, alignment: .trailing)

                // Verse text
                VStack(alignment: .leading, spacing: 4) {
                    Text(verse.text)
                        .font(.custom("Georgia", size: 17))
                        .foregroundColor(SeekTheme.textPrimary)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)

                    // Inline indicators for note/highlight
                    if hasNote || isHighlighted {
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
                        }
                    }
                }
            }

            // Display note if exists (compact)
            if let note = appState.notes[verseId], !note.isEmpty {
                Text(note)
                    .font(.system(size: 13))
                    .foregroundColor(SeekTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 1.0, green: 0.96, blue: 0.90))
                    .cornerRadius(8)
                    .padding(.leading, 32)
            }
        }
        .padding(.horizontal, SeekTheme.screenHorizontalPadding)
        .padding(.vertical, 10)
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
            if isMultiSelectMode {
                onTap()
            }
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            showContextMenu = true
        }
        .confirmationDialog("\(ScriptureTerminology.verseLabel(for: chapterRef.scriptureId)) \(verse.number)", isPresented: $showContextMenu, titleVisibility: .visible) {
            Button(isHighlighted ? "Remove Highlight" : "Highlight") {
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
                    showHighlightPaywall = true
                }
            }

            Button(hasNote ? "Edit Note" : "Add Note") {
                if hasNote || appState.canAddNote() {
                    noteText = appState.notes[verseId] ?? ""
                    showNoteSheet = true
                } else {
                    showNotePaywall = true
                }
            }

            Button("Copy") {
                let textToCopy = "\(reference)\n\(verse.text)\n— \(textName)"
                UIPasteboard.general.string = textToCopy
            }

            Button("Share") {
                shareVerse()
            }

            Button("Guided Study") {
                onStartGuidedStudy()
            }

            Button("Select Multiple") {
                onLongPress()
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
        .sheet(isPresented: $showHighlightPaywall) {
            PaywallView(triggerType: .highlight)
                .environmentObject(appState)
        }
        .sheet(isPresented: $showNotePaywall) {
            PaywallView(triggerType: .note)
                .environmentObject(appState)
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
                        if appState.canAddNote() || appState.notes[verseId] != nil {
                            appState.setNote(
                                verseId,
                                noteText,
                                reference: reference,
                                verseText: verseText,
                                religion: religion,
                                textName: textName
                            )
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

import SwiftUI

struct StudyHomeScreen: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var libraryData = LibraryData.shared
    @StateObject private var studyStore = StudyStore.shared

    @State private var activeLaunch: GuidedStudyLaunch?
    @State private var isPreparingLaunch = false
    @State private var lastReadingState: LastReadingState?
    @State private var inlineChatText = ""
    @State private var recentConversationLastUserPreview = ""

    private let universalStarterPrompts = [
        "Help me get started",
        "What should I explore next?",
        "Explain a core idea simply",
        "How do I begin a daily reading habit?"
    ]

    private let passageStarterPrompts = [
        "What is happening here?",
        "Clarify key ideas",
        "What should I notice?",
        "How is this understood in its tradition?"
    ]

    private let continuationPrompts = [
        "Continue from where we left off",
        "Summarize what we've covered",
        "Ask me a question to deepen this",
        "Give me one takeaway and one next question"
    ]
    
    private var recentConversation: StudyConversation? {
        studyStore.conversations.first
    }

    private enum PromptSuggestionMode {
        case startHere
        case passageStart
        case continueSession
    }

    private var promptSuggestionMode: PromptSuggestionMode {
        if appState.selectedPassage != nil {
            return .passageStart
        }
        if recentConversation != nil {
            return .continueSession
        }
        return .startHere
    }

    private var promptSuggestions: [String] {
        switch promptSuggestionMode {
        case .startHere:
            return universalStarterPrompts
        case .passageStart:
            return passageStarterPrompts
        case .continueSession:
            return continuationPrompts
        }
    }

    private var promptsSectionTitle: String {
        switch promptSuggestionMode {
        case .startHere:
            return "Start here"
        case .passageStart:
            return "From this passage"
        case .continueSession:
            return "Continue your study"
        }
    }

    private var chipsHeaderFont: Font {
        .system(size: recentConversation == nil ? 15 : 13, weight: .semibold)
    }

    private var chipsSectionSpacing: CGFloat {
        recentConversation == nil ? 10 : 8
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Study")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(SeekTheme.textPrimary)

                    Text("A guided companion for focused study and learning.")
                        .font(.system(size: 16))
                        .foregroundColor(SeekTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.92)
                }
                .padding(.top, 12)

                if let conversation = recentConversation {
                    resumeStudyCard(conversation)
                }

                inlineChatComposer

                VStack(alignment: .leading, spacing: chipsSectionSpacing) {
                    Text(promptsSectionTitle)
                        .font(chipsHeaderFont)
                        .foregroundColor(SeekTheme.textSecondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(promptSuggestions, id: \.self) { prompt in
                            Button {
                                handlePromptSelection(prompt)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Image(systemName: "quote.bubble")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(Brand.primaryAccent.opacity(0.85))

                                    Text(prompt)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(SeekTheme.textPrimary)
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                                .background(SeekTheme.cardBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Brand.borderSubtle.opacity(0.36), lineWidth: 1)
                                )
                                .cornerRadius(10)
                            }
                            .disabled(isPreparingLaunch)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button {
                        choosePassage()
                    } label: {
                        Label("Choose passage", systemImage: "book")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(SeekTheme.textSecondary)
                    }
                    .disabled(isPreparingLaunch)
                }

                if libraryData.loadState != .loaded {
                    libraryStatusBanner
                }

            }
            .padding(.horizontal, SeekTheme.screenHorizontalPadding)
            .padding(.bottom, 24)
        }
        .background(Brand.backgroundPrimary.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $activeLaunch) { launch in
            GuidedStudyScreen(
                context: launch.context,
                appState: appState,
                existingConversation: launch.existingConversation,
                initialPrompt: launch.initialPrompt,
                initialInputText: launch.initialInputText,
                showPassagePickerOnAppear: launch.showPassagePickerOnAppear,
                autoFocusInputOnAppear: launch.autoFocusInputOnAppear
            )
            .environmentObject(appState)
        }
        .onAppear {
            refreshLastReadingState()
            refreshLastUserMessagePreview()
        }
        .task {
            if libraryData.traditions.isEmpty {
                await libraryData.bootstrapIfNeeded()
            }
            await GuidedSearchManager.shared.warmIndex(with: libraryData.traditions)
            refreshLastReadingState()
            refreshLastUserMessagePreview()
        }
        .onChange(of: recentConversation?.id) { _, _ in
            refreshLastUserMessagePreview()
        }
    }

    @ViewBuilder
    private var libraryStatusBanner: some View {
        switch libraryData.loadState {
        case .loading, .idle:
            HStack(spacing: 10) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: SeekTheme.maroonAccent))
                Text("Loading study library…")
                    .font(.system(size: 13))
                    .foregroundColor(SeekTheme.textSecondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SeekTheme.cardBackground)
            .cornerRadius(10)
        case .offline:
            HStack(spacing: 10) {
                Text("You’re offline. Guided Study may be limited.")
                    .font(.system(size: 13))
                    .foregroundColor(SeekTheme.textSecondary)
                Spacer()
                Button("Retry") {
                    Task { await libraryData.retry() }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(SeekTheme.maroonAccent)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SeekTheme.cardBackground)
            .cornerRadius(10)
        case .error(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text("Library error")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(SeekTheme.textPrimary)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(SeekTheme.textSecondary)
                Button("Retry") {
                    Task { await libraryData.retry() }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(SeekTheme.maroonAccent)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SeekTheme.cardBackground)
            .cornerRadius(10)
        case .loaded:
            EmptyView()
        }
    }

    private func resumeStudyCard(_ conversation: StudyConversation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(continueCardTitle(for: conversation))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(SeekTheme.textPrimary)
                    .lineLimit(1)

                Spacer()

                Text("Updated \(relativeTimeString(since: conversation.updatedAt))")
                    .font(.system(size: 12))
                    .foregroundColor(SeekTheme.textSecondary)
            }

            Text("Last: \(continueCardLastPromptPreview(for: conversation))")
                .font(.system(size: 14))
                .foregroundColor(SeekTheme.textSecondary)
                .lineLimit(1)

            Button {
                continueConversation(conversation)
            } label: {
                Text("Continue Study")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(SeekTheme.onAccentText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(SeekTheme.maroonAccent)
                    .cornerRadius(10)
            }
            .disabled(isPreparingLaunch)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            continueConversation(conversation)
        }
        .padding(16)
        .background(SeekTheme.cardBackground)
        .cornerRadius(14)
    }

    private var inlineChatComposer: some View {
        HStack(alignment: .center, spacing: 10) {
            TextField(
                "",
                text: $inlineChatText,
                prompt: Text("Ask a question").foregroundColor(SeekTheme.textSecondary),
                axis: .vertical
            )
                .font(.system(size: 15))
                .foregroundColor(SeekTheme.textPrimary)
                .lineLimit(1...2)
                .submitLabel(.send)
                .onSubmit {
                    sendInlineChatEntry()
                }
                .frame(minHeight: 40, alignment: .center)

            Button {
                sendInlineChatEntry()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .foregroundColor(
                        inlineChatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPreparingLaunch
                        ? SeekTheme.textSecondary.opacity(0.55)
                        : SeekTheme.textPrimary.opacity(0.78)
                    )
                    .background(
                        (inlineChatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPreparingLaunch
                         ? Brand.surfaceSecondary.opacity(0.55)
                         : Brand.surfaceSecondary)
                    )
                    .clipShape(Circle())
            }
            .disabled(inlineChatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPreparingLaunch)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Brand.surfacePrimary)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .cornerRadius(14)
    }

    private func sendInlineChatEntry(prefilledText: String? = nil) {
        let sourceText = prefilledText ?? inlineChatText
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let targetConversation = createNewInlineConversation()
        #if DEBUG
        print("[StudyHome] New chat created: \(targetConversation.id.uuidString)")
        #endif

        Task {
            await prepareLaunch(
                existingConversation: targetConversation,
                initialPrompt: trimmed,
                initialInputText: nil,
                showPassagePickerOnAppear: false,
                autoFocusInputOnAppear: true,
                avoidScriptureFallback: true
            )
            await MainActor.run {
                inlineChatText = ""
            }
        }
    }

    private func choosePassage() {
        Task {
            await prepareLaunch(
                existingConversation: nil,
                initialPrompt: nil,
                initialInputText: nil,
                showPassagePickerOnAppear: true,
                autoFocusInputOnAppear: false,
                avoidScriptureFallback: false
            )
        }
    }

    private func continueConversation(_ conversation: StudyConversation) {
        Task {
            await prepareLaunch(
                existingConversation: conversation,
                initialPrompt: nil,
                initialInputText: nil,
                showPassagePickerOnAppear: false,
                autoFocusInputOnAppear: false,
                avoidScriptureFallback: true
            )
        }
    }

    private func continueConversation(_ conversation: StudyConversation, with prompt: String) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            continueConversation(conversation)
            return
        }

        Task {
            await prepareLaunch(
                existingConversation: conversation,
                initialPrompt: trimmedPrompt,
                initialInputText: nil,
                showPassagePickerOnAppear: false,
                autoFocusInputOnAppear: true,
                avoidScriptureFallback: true
            )
        }
    }

    private func handlePromptSelection(_ prompt: String) {
        switch promptSuggestionMode {
        case .continueSession:
            if let conversation = recentConversation {
                continueConversation(conversation, with: prompt)
            } else {
                sendInlineChatEntry(prefilledText: prompt)
            }
        case .startHere, .passageStart:
            sendInlineChatEntry(prefilledText: prompt)
        }
    }

    private func createNewInlineConversation() -> StudyConversation {
        guard let selectedPassage = appState.selectedPassage else {
            return studyStore.createGeneralConversation()
        }

        let verseStart = selectedPassage.verseRange?.lowerBound ?? selectedPassage.verseNumber
        let verseEnd = selectedPassage.verseRange?.upperBound ?? selectedPassage.verseNumber
        let fallbackTitle = selectedPassage.reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "\(selectedPassage.book) \(selectedPassage.chapter)"
            : selectedPassage.reference

        return studyStore.createConversation(
            StudyPassageRef(
                scriptureId: selectedPassage.scriptureId,
                bookId: normalizeBookId(selectedPassage.book),
                chapter: selectedPassage.chapter,
                verseStart: verseStart,
                verseEnd: verseEnd,
                fallbackTitle: fallbackTitle
            )
        )
    }

    private func refreshLastReadingState() {
        lastReadingState = LastReadingStore.loadLastReadingState()
    }

    private func refreshLastUserMessagePreview() {
        guard let conversation = recentConversation else {
            recentConversationLastUserPreview = ""
            return
        }

        let messages = studyStore.loadMessages(conversationId: conversation.id)
        if let lastUserMessage = messages.reversed().first(where: { $0.role == "user" })?.content {
            recentConversationLastUserPreview = normalizedPreview(lastUserMessage)
        } else {
            recentConversationLastUserPreview = "No question yet"
        }
    }

    private func continueCardTitle(for conversation: StudyConversation) -> String {
        if case .passage(let scriptureRef) = conversation.context {
            let display = scriptureRef.display.trimmingCharacters(in: .whitespacesAndNewlines)
            if !display.isEmpty {
                return display
            }
        }

        guard !conversation.bookId.isEmpty, conversation.chapter > 0 else {
            return "Guided Study"
        }

        let bookName: String
        if !conversation.scriptureId.isEmpty,
           let book = libraryData.getBook(scriptureId: conversation.scriptureId, bookId: conversation.bookId) {
            bookName = book.name
        } else {
            bookName = conversation.bookId
                .split(separator: "-")
                .map { $0.capitalized }
                .joined(separator: " ")
        }

        return "\(bookName) \(conversation.chapter)"
    }

    private func continueCardLastPromptPreview(for conversation: StudyConversation) -> String {
        if recentConversation?.id == conversation.id, !recentConversationLastUserPreview.isEmpty {
            return recentConversationLastUserPreview
        }
        return "No question yet"
    }

    private func normalizedPreview(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            return "No question yet"
        }

        let limit = 72
        if normalized.count <= limit {
            return normalized
        }

        let endIndex = normalized.index(normalized.startIndex, offsetBy: limit)
        return "\(normalized[..<endIndex])…"
    }

    private func relativeTimeString(since date: Date) -> String {
        let elapsed = max(0, Int(Date().timeIntervalSince(date)))
        if elapsed < 60 {
            return "just now"
        }
        if elapsed < 3600 {
            let minutes = elapsed / 60
            return "\(minutes) \(minutes == 1 ? "minute" : "minutes") ago"
        }
        if elapsed < 86_400 {
            let hours = elapsed / 3600
            return "\(hours) \(hours == 1 ? "hour" : "hours") ago"
        }
        let days = elapsed / 86_400
        return "\(days) \(days == 1 ? "day" : "days") ago"
    }

    private func prepareLaunch(
        existingConversation: StudyConversation?,
        initialPrompt: String?,
        initialInputText: String?,
        showPassagePickerOnAppear: Bool,
        autoFocusInputOnAppear: Bool,
        avoidScriptureFallback: Bool
    ) async {
        guard !isPreparingLaunch else { return }

        isPreparingLaunch = true
        defer { isPreparingLaunch = false }

        let context = await resolveContext(
            preferredSession: existingConversation,
            avoidScriptureFallback: avoidScriptureFallback
        )
        activeLaunch = GuidedStudyLaunch(
            context: context,
            existingConversation: existingConversation,
            initialPrompt: initialPrompt,
            initialInputText: initialInputText,
            showPassagePickerOnAppear: showPassagePickerOnAppear,
            autoFocusInputOnAppear: autoFocusInputOnAppear
        )
    }

    private func resolveContext(
        preferredSession: StudyConversation?,
        avoidScriptureFallback: Bool
    ) async -> GuidedStudyContext {
        if avoidScriptureFallback {
            if let session = preferredSession {
                if case .general = session.context {
                    return GuidedStudyContext(
                        chapterRef: StartCandidate.placeholder.chapterRef,
                        verses: [],
                        selectedVerseIds: [],
                        textName: "",
                        traditionId: "",
                        traditionName: ""
                    )
                }
                do {
                    let verses = try await RemoteDataService.shared.loadChapter(
                        scriptureId: session.scriptureId,
                        bookId: session.bookId,
                        chapter: session.chapter
                    )
                    return GuidedStudyContext(
                        chapterRef: ChapterRef(
                            scriptureId: session.scriptureId,
                            bookId: session.bookId,
                            chapterNumber: session.chapter,
                            bookName: session.bookId
                        ),
                        verses: verses,
                        selectedVerseIds: [],
                        textName: "",
                        traditionId: "",
                        traditionName: ""
                    )
                } catch {
                    return GuidedStudyContext(
                        chapterRef: StartCandidate.placeholder.chapterRef,
                        verses: [],
                        selectedVerseIds: [],
                        textName: "",
                        traditionId: "",
                        traditionName: ""
                    )
                }
            }

            return GuidedStudyContext(
                chapterRef: StartCandidate.placeholder.chapterRef,
                verses: [],
                selectedVerseIds: [],
                textName: "",
                traditionId: "",
                traditionName: ""
            )
        }

        var candidates: [StartCandidate] = []

        if let session = preferredSession {
            candidates.append(StartCandidate.from(session: session))
        }

        if let selected = appState.selectedPassage {
            candidates.append(
                StartCandidate(
                    chapterRef: ChapterRef(
                        scriptureId: selected.scriptureId,
                        bookId: normalizeBookId(selected.book),
                        chapterNumber: selected.chapter,
                        bookName: selected.book
                    ),
                    textName: "",
                    traditionId: "",
                    traditionName: ""
                )
            )
        }

        if let recentSession = studyStore.conversations.first,
           recentSession.id != preferredSession?.id {
            candidates.append(StartCandidate.from(session: recentSession))
        }

        if let readingState = lastReadingState {
            candidates.append(StartCandidate.from(lastReadingState: readingState))
        }

        var uniqueCandidates: [StartCandidate] = []
        var seenIDs = Set<String>()

        for candidate in candidates where seenIDs.insert(candidate.chapterRef.id).inserted {
            uniqueCandidates.append(candidate)
        }

        let fallback = uniqueCandidates.first ?? .placeholder

        for candidate in uniqueCandidates {
            do {
                let verses = try await RemoteDataService.shared.loadChapter(
                    scriptureId: candidate.chapterRef.scriptureId,
                    bookId: candidate.chapterRef.bookId,
                    chapter: candidate.chapterRef.chapterNumber
                )

                if !verses.isEmpty {
                    return GuidedStudyContext(
                        chapterRef: candidate.chapterRef,
                        verses: verses,
                        selectedVerseIds: [],
                        textName: candidate.textName,
                        traditionId: candidate.traditionId,
                        traditionName: candidate.traditionName
                    )
                }
            } catch {
                continue
            }
        }

        return GuidedStudyContext(
            chapterRef: fallback.chapterRef,
            verses: [],
            selectedVerseIds: [],
            textName: fallback.textName,
            traditionId: fallback.traditionId,
            traditionName: fallback.traditionName
        )
    }
}

private struct StartCandidate {
    let chapterRef: ChapterRef
    let textName: String
    let traditionId: String
    let traditionName: String

    static func from(session: StudyConversation) -> StartCandidate {
        StartCandidate(
            chapterRef: ChapterRef(
                scriptureId: session.scriptureId,
                bookId: session.bookId,
                chapterNumber: session.chapter,
                bookName: session.bookId
            ),
            textName: "",
            traditionId: "",
            traditionName: ""
        )
    }

    static func from(lastReadingState: LastReadingState) -> StartCandidate {
        StartCandidate(
            chapterRef: ChapterRef(
                scriptureId: lastReadingState.scriptureId ?? "guided-study",
                bookId: lastReadingState.bookId,
                chapterNumber: lastReadingState.chapter,
                bookName: lastReadingState.bookId
            ),
            textName: "",
            traditionId: "",
            traditionName: ""
        )
    }

    static var placeholder: StartCandidate {
        StartCandidate(
            chapterRef: ChapterRef(
                scriptureId: "guided-study",
                bookId: "passage",
                chapterNumber: 1,
                bookName: "Passage"
            ),
            textName: "",
            traditionId: "",
            traditionName: ""
        )
    }
}

private struct GuidedStudyLaunch: Identifiable {
    let id = UUID()
    let context: GuidedStudyContext
    let existingConversation: StudyConversation?
    let initialPrompt: String?
    let initialInputText: String?
    let showPassagePickerOnAppear: Bool
    let autoFocusInputOnAppear: Bool
}

#Preview {
    NavigationStack {
        StudyHomeScreen()
            .environmentObject(AppState())
    }
}

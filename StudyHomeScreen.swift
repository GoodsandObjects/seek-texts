import SwiftUI

struct StudyHomeScreen: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var libraryData = LibraryData.shared
    @StateObject private var studyStore = StudyStore.shared

    @State private var activeLaunch: GuidedStudyLaunch?
    @State private var isPreparingLaunch = false
    @State private var lastReadingState: LastReadingState?
    @State private var inlineChatText = ""

    private let promptSuggestions = [
        "Explore the context of this passage",
        "Summarize what is happening here",
        "Help me reflect on this",
        "Identify themes in this passage"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Study")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(SeekTheme.textPrimary)

                    Text("A guided companion for reflection and learning.")
                        .font(.system(size: 16))
                        .foregroundColor(SeekTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.92)
                }
                .padding(.top, 12)

                if let state = lastReadingState {
                    continueReadingCard(state: state)
                }

                VStack(spacing: 10) {
                    Button {
                        startGuidedStudy()
                    } label: {
                        HStack(spacing: 10) {
                            if isPreparingLaunch {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text("Start Guided Study")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(SeekTheme.maroonAccent)
                        .cornerRadius(12)
                    }
                    .disabled(isPreparingLaunch)
                }

                inlineChatComposer

                VStack(alignment: .leading, spacing: 10) {
                    Text("Try a prompt")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(SeekTheme.textPrimary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(promptSuggestions, id: \.self) { prompt in
                            Button {
                                startGuidedStudy(prompt: prompt)
                            } label: {
                                Text(prompt)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(SeekTheme.maroonAccent)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 12)
                                    .background(SeekTheme.maroonAccent.opacity(0.08))
                                    .cornerRadius(10)
                            }
                            .disabled(isPreparingLaunch)
                        }
                    }
                }

                Spacer(minLength: 16)
            }
            .padding(.horizontal, SeekTheme.screenHorizontalPadding)
            .padding(.bottom, 24)
        }
        .themedScreenBackground()
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
        }
        .task {
            if libraryData.traditions.isEmpty {
                await libraryData.bootstrapIfNeeded()
            }
            await GuidedSearchManager.shared.warmIndex(with: libraryData.traditions)
            refreshLastReadingState()
        }
    }

    private func continueReadingCard(state: LastReadingState) -> some View {
        NavigationLink(value: AppRoute.reader(makeReaderDestination(from: state))) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(displayBookName(for: state)) \(state.chapter)")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(SeekTheme.textPrimary)
                            .lineLimit(1)

                        Text("Last opened \(relativeTimeString(since: state.timestamp))")
                            .font(.system(size: 13))
                            .foregroundColor(SeekTheme.textSecondary)
                    }

                    Spacer()

                    Text("Resume")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(SeekTheme.maroonAccent)
                        .cornerRadius(10)
                }
            }
            .contentShape(Rectangle())
            .padding(16)
            .background(SeekTheme.cardBackground)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }

    private var inlineChatComposer: some View {
        HStack(alignment: .center, spacing: 10) {
            TextField("Start a guided study…", text: $inlineChatText, axis: .vertical)
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
                        : SeekTheme.maroonAccent
                    )
                    .background(
                        (inlineChatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPreparingLaunch
                         ? SeekTheme.creamBackground.opacity(0.5)
                         : SeekTheme.creamBackground.opacity(0.75))
                    )
                    .clipShape(Circle())
            }
            .disabled(inlineChatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPreparingLaunch)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(SeekTheme.cardBackground)
        .cornerRadius(14)
    }

    private func startGuidedStudy(prompt: String? = nil) {
        Task {
            await prepareLaunch(
                existingConversation: nil,
                initialPrompt: prompt,
                initialInputText: nil,
                showPassagePickerOnAppear: prompt == nil,
                autoFocusInputOnAppear: false,
                avoidScriptureFallback: false
            )
        }
    }

    private func sendInlineChatEntry() {
        let trimmed = inlineChatText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let resumeConversation = studyStore.conversations.first { conversation in
            if case .general = conversation.context {
                return true
            }
            return false
        }
        let targetConversation = resumeConversation ?? studyStore.createGeneralConversation()

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

    private func makeReaderDestination(from state: LastReadingState) -> ReaderDestination {
        let bookName = displayBookName(for: state)
        return ReaderDestination(
            scriptureId: state.scriptureId ?? "bible-kjv",
            bookId: state.bookId,
            chapter: state.chapter,
            bookName: bookName,
            verseStart: state.verseStart,
            verseEnd: state.verseEnd
        )
    }

    private func refreshLastReadingState() {
        lastReadingState = LastReadingStore.loadLastReadingState()
    }

    private func displayBookName(for state: LastReadingState) -> String {
        if let scriptureId = state.scriptureId,
           let book = libraryData.getBook(scriptureId: scriptureId, bookId: state.bookId) {
            return book.name
        }
        return state.bookId
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
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

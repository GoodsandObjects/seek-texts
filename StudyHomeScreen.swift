import SwiftUI

struct StudyHomeScreen: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var libraryData = LibraryData.shared

    @State private var activeLaunch: GuidedStudyLaunch?
    @State private var isPreparingLaunch = false

    private let promptSuggestions = [
        "What is the context of this passage?",
        "What themes should I notice here?",
        "Help me reflect on this personally.",
        "Explain this simply without preaching."
    ]

    private var lastSession: GuidedSession? {
        appState.sortedGuidedSessions.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
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

                VStack(spacing: 12) {
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

                    if lastSession != nil {
                        Button {
                            resumeLastSession()
                        } label: {
                            Text("Resume Last Session")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(SeekTheme.maroonAccent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(SeekTheme.cardBackground)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(SeekTheme.maroonAccent.opacity(0.22), lineWidth: 1)
                                )
                        }
                        .disabled(isPreparingLaunch)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
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
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
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
                existingSession: launch.existingSession,
                initialPrompt: launch.initialPrompt,
                showPassagePickerOnAppear: launch.showPassagePickerOnAppear
            )
            .environmentObject(appState)
        }
        .task {
            if libraryData.traditions.isEmpty {
                await libraryData.bootstrapIfNeeded()
            }
            await GuidedSearchManager.shared.warmIndex(with: libraryData.traditions)
        }
    }

    private func startGuidedStudy(prompt: String? = nil) {
        Task {
            await prepareLaunch(
                existingSession: nil,
                initialPrompt: prompt,
                showPassagePickerOnAppear: prompt == nil
            )
        }
    }

    private func resumeLastSession() {
        guard let session = lastSession else { return }
        Task {
            await prepareLaunch(existingSession: session, initialPrompt: nil, showPassagePickerOnAppear: false)
        }
    }

    private func prepareLaunch(
        existingSession: GuidedSession?,
        initialPrompt: String?,
        showPassagePickerOnAppear: Bool
    ) async {
        guard !isPreparingLaunch else { return }

        isPreparingLaunch = true
        defer { isPreparingLaunch = false }

        let context = await resolveContext(preferredSession: existingSession)
        activeLaunch = GuidedStudyLaunch(
            context: context,
            existingSession: existingSession,
            initialPrompt: initialPrompt,
            showPassagePickerOnAppear: showPassagePickerOnAppear
        )
    }

    private func resolveContext(preferredSession: GuidedSession?) async -> GuidedStudyContext {
        var candidates: [StartCandidate] = []

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

        if let session = preferredSession {
            candidates.append(StartCandidate.from(session: session))
        }

        if let recentSession = appState.sortedGuidedSessions.first,
           recentSession.id != preferredSession?.id {
            candidates.append(StartCandidate.from(session: recentSession))
        }

        if libraryData.traditions.isEmpty {
            await libraryData.bootstrapIfNeeded()
        }

        if let tradition = libraryData.traditions.first,
           let scripture = tradition.texts.first,
           let book = scripture.books.first {
            candidates.append(
                StartCandidate(
                    chapterRef: ChapterRef(
                        scriptureId: scripture.id,
                        bookId: book.id,
                        chapterNumber: 1,
                        bookName: book.name
                    ),
                    textName: scripture.name,
                    traditionId: tradition.id,
                    traditionName: tradition.name
                )
            )
        }

        candidates.append(
            StartCandidate(
                chapterRef: ChapterRef(
                    scriptureId: "bible-kjv",
                    bookId: "genesis",
                    chapterNumber: 1,
                    bookName: "Genesis"
                ),
                textName: "King James Bible",
                traditionId: "christianity",
                traditionName: "Christianity"
            )
        )

        var uniqueCandidates: [StartCandidate] = []
        var seenIDs = Set<String>()

        for candidate in candidates where seenIDs.insert(candidate.chapterRef.id).inserted {
            uniqueCandidates.append(candidate)
        }

        let fallback = uniqueCandidates.first ?? StartCandidate(
            chapterRef: ChapterRef(
                scriptureId: "bible-kjv",
                bookId: "genesis",
                chapterNumber: 1,
                bookName: "Genesis"
            ),
            textName: "King James Bible",
            traditionId: "christianity",
            traditionName: "Christianity"
        )

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

    static func from(session: GuidedSession) -> StartCandidate {
        StartCandidate(
            chapterRef: ChapterRef(
                scriptureId: session.scriptureId,
                bookId: normalizeBookId(session.book),
                chapterNumber: session.chapter,
                bookName: session.book
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
    let existingSession: GuidedSession?
    let initialPrompt: String?
    let showPassagePickerOnAppear: Bool
}

#Preview {
    NavigationStack {
        StudyHomeScreen()
            .environmentObject(AppState())
    }
}

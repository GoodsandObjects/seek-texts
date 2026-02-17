//
//  GuidedStudyScreen.swift
//  Seek
//
//  Guided Study premium chat interface with AI-style responses.
//  Non-judgmental, calm, curious, reflective companion.
//

import SwiftUI
import Combine

// MARK: - AI Provider Protocol

protocol AIProvider {
    func generateResponse(message: String, context: GuidedStudyProviderContext) async throws -> String
}

// MARK: - Mock AI Provider

final class MockAIProvider: AIProvider, @unchecked Sendable {

    private let reflectiveResponses = [
        "That's a profound passage. What feelings arise when you read these words? Sometimes our initial emotional response reveals what our hearts need to hear.",
        "I notice this text speaks to %THEME%. What experiences in your own life might connect with this teaching? Often scripture becomes clearer when we see it through our lived experiences.",
        "This is a passage many have found meaningful across centuries. What draws you to it today? There's often wisdom in understanding why certain words speak to us at particular moments.",
        "Let's sit with this together. If you were to share this passage with someone struggling, what comfort or challenge might they find in it?",
        "I'm curious about what you notice first in this passage. Our attention often guides us to what we most need to explore. What word or phrase stands out?",
        "This teaching touches on themes of %THEME%. How do you see these ideas playing out in your daily life? Sometimes ancient wisdom illuminates modern challenges in unexpected ways.",
        "Reading this, I wonder: what questions does it raise for you? Sometimes the questions a text evokes are as valuable as the answers it provides.",
        "There's a richness here worth exploring slowly. What would it look like to carry this passage with you through your day? How might it shape your interactions?",
        "Many find that returning to the same passage at different life stages reveals new meanings. What might a younger version of you have understood differently here?",
        "This is beautiful. I'm struck by how %THEME% emerges from these words. What do you think the original audience would have heard in this teaching?",
    ]

    private let themes = [
        "faith and trust",
        "compassion and kindness",
        "patience and perseverance",
        "wisdom and understanding",
        "love and connection",
        "hope and renewal",
        "peace and stillness",
        "gratitude and joy",
        "service and humility",
        "transformation and growth"
    ]

    func generateResponse(message: String, context: GuidedStudyProviderContext) async throws -> String {
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        var response = reflectiveResponses.randomElement() ?? reflectiveResponses[0]
        let theme = themes.randomElement() ?? themes[0]
        response = response.replacingOccurrences(of: "%THEME%", with: theme)
        return response
    }
}

// MARK: - Chat Message Model

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let content: String
    let isUser: Bool
    let timestamp: Date

    init(content: String, isUser: Bool) {
        self.id = UUID()
        self.content = content
        self.isUser = isUser
        self.timestamp = Date()
    }

    init(from sessionMessage: GuidedSessionMessage) {
        self.id = sessionMessage.id
        self.content = sessionMessage.text
        self.isUser = sessionMessage.role == .user
        self.timestamp = sessionMessage.timestamp
    }
}

// MARK: - Guided Study View Model

@MainActor
class GuidedStudyViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isTyping = false
    @Published var hasUsedFreeResponse = false
    @Published var showPaywall = false
    @Published var showSaveConfirmation = false
    @Published var showSaveInsightSheet = false

    @Published var currentScope: GuidedSessionScope
    @Published var currentVerseRange: ClosedRange<Int>?
    @Published var currentReference: String
    @Published var currentVerseText: String
    @Published var isSwitchingPassage = false

    private var context: GuidedStudyContext
    let aiProvider: AIProvider

    private weak var appState: AppState?
    private var currentSession: GuidedSession?

    init(context: GuidedStudyContext, appState: AppState, existingSession: GuidedSession? = nil, aiProvider: AIProvider? = nil) {
        self.context = context
        self.appState = appState
        self.aiProvider = aiProvider ?? Self.makeDefaultProvider()

        // Check if user has already used their free response today
        hasUsedFreeResponse = !appState.canUseGuidedStudy()

        // Determine initial scope based on context or existing session
        let initialScope: GuidedSessionScope
        let initialVerseRange: ClosedRange<Int>?

        if let session = existingSession {
            // Resuming an existing session - use its scope
            initialScope = session.scope
            initialVerseRange = session.verseRange
        } else if !context.selectedVerseIds.isEmpty {
            // New session with selected verses - use selected scope
            initialScope = .selected
            initialVerseRange = nil
        } else {
            // New session without selection - default to full chapter
            initialScope = .chapter
            initialVerseRange = nil
        }

        // Build initial passage (before setting self properties)
        let passage = context.buildPassage(scope: initialScope, verseRange: initialVerseRange)

        // Now initialize all stored properties
        self.currentScope = initialScope
        self.currentVerseRange = initialVerseRange
        self.currentReference = passage.reference
        self.currentVerseText = passage.verseText

        // Load existing session messages or create welcome
        if let session = existingSession {
            self.currentSession = session
            for msg in session.messages {
                messages.append(ChatMessage(from: msg))
            }
        } else {
            addWelcomeMessage()
        }
    }

    private func addWelcomeMessage() {
        let welcome = """
        Welcome to Guided Study. I'm here to explore this passage with you in a spirit of curiosity and reflection.

        Take a moment to read through the text. When you're ready, choose a prompt below or share what's on your mind.
        """
        messages.append(ChatMessage(content: welcome, isUser: false))
    }

    var suggestedPrompts: [String] {
        [
            "What does this passage mean?",
            "How can I apply this today?",
            "What's the historical context?",
            "Help me reflect on this",
            "What questions should I ask?"
        ]
    }

    var scopeLabel: String {
        let chapterLabel = ScriptureTerminology.chapterLabel(for: context.chapterRef.scriptureId)
        let verseLabel = ScriptureTerminology.verseLabel(for: context.chapterRef.scriptureId)
        let verseLabelPlural = ScriptureTerminology.verseLabelLowercased(for: context.chapterRef.scriptureId, plural: true).capitalized

        switch currentScope {
        case .chapter:
            return "Full \(chapterLabel)"
        case .range:
            if let range = currentVerseRange {
                if range.lowerBound == range.upperBound {
                    return "\(verseLabel) \(range.lowerBound)"
                }
                return "\(verseLabel) \(range.lowerBound)-\(range.upperBound)"
            }
            return "\(verseLabel) Range"
        case .selected:
            return "Selected \(verseLabelPlural)"
        }
    }

    var hasSelectedVerses: Bool {
        !context.selectedVerseIds.isEmpty
    }

    var maxVerseNumber: Int {
        context.verses.map { $0.number }.max() ?? 1
    }

    var currentPassageSelection: GuidedPassageSelectionRef {
        GuidedPassageSelectionRef(
            traditionId: context.traditionId,
            traditionName: context.traditionName,
            scriptureId: context.chapterRef.scriptureId,
            scriptureName: context.textName,
            bookId: context.chapterRef.bookId,
            bookName: context.chapterRef.bookName,
            chapterNumber: context.chapterRef.chapterNumber
        )
    }

    var currentScriptureRef: ScriptureRef {
        ScriptureRef(
            scriptureId: context.chapterRef.scriptureId,
            bookId: context.chapterRef.bookId,
            chapter: context.chapterRef.chapterNumber,
            verseStart: currentVerseRange?.lowerBound,
            verseEnd: currentVerseRange?.upperBound,
            display: currentReference
        )
    }

    var currentSessionId: UUID? {
        currentSession?.id
    }

    func changePassage(scope: GuidedSessionScope, verseRange: ClosedRange<Int>? = nil) {
        currentScope = scope
        currentVerseRange = verseRange
        let passage = context.buildPassage(scope: scope, verseRange: verseRange)
        currentReference = passage.reference
        currentVerseText = passage.verseText
    }

    func applyPassageSelection(
        _ selection: GuidedPassageSelectionRef,
        scope: GuidedSessionScope,
        verseRange: ClosedRange<Int>?
    ) async {
        guard !isSwitchingPassage else { return }

        isSwitchingPassage = true
        defer { isSwitchingPassage = false }

        do {
            let loadedVerses = try await RemoteDataService.shared.loadChapter(
                scriptureId: selection.scriptureId,
                bookId: selection.bookId,
                chapter: selection.chapterNumber
            )

            let newContext = GuidedStudyContext(
                chapterRef: ChapterRef(
                    scriptureId: selection.scriptureId,
                    bookId: selection.bookId,
                    chapterNumber: selection.chapterNumber,
                    bookName: selection.bookName
                ),
                verses: loadedVerses,
                selectedVerseIds: [],
                textName: selection.scriptureName,
                traditionId: selection.traditionId,
                traditionName: selection.traditionName
            )

            context = newContext

            let maxVerse = loadedVerses.map(\.number).max() ?? 1
            var safeRange: ClosedRange<Int>?
            if scope == .range, let range = verseRange, maxVerse > 0 {
                let lower = max(1, min(range.lowerBound, maxVerse))
                let upper = max(lower, min(range.upperBound, maxVerse))
                safeRange = lower...upper
            }

            let resolvedScope: GuidedSessionScope = (scope == .range && safeRange == nil) ? .chapter : scope
            currentScope = resolvedScope
            currentVerseRange = safeRange

            let passage = context.buildPassage(scope: resolvedScope, verseRange: safeRange)
            currentReference = passage.reference
            currentVerseText = passage.verseText

            // Passage changes begin a fresh conversation/session.
            currentSession = nil
            messages = []
            addWelcomeMessage()
        } catch {
            messages.append(ChatMessage(
                content: "I couldn't load that passage right now. Please try another selection.",
                isUser: false
            ))
        }
    }

    func sendMessage(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let state = appState else { return }

        if !state.effectivelyGuided && hasUsedFreeResponse {
            showPaywall = true
            return
        }

        messages.append(ChatMessage(content: text, isUser: true))

        if !state.effectivelyGuided {
            state.recordGuidedStudyUsage()
            hasUsedFreeResponse = true
        }

        Task {
            isTyping = true
            do {
                let providerContext = GuidedStudyProviderContext(
                    context: buildProviderContext(),
                    scriptureId: context.chapterRef.scriptureId,
                    bookId: context.chapterRef.bookId,
                    chapter: context.chapterRef.chapterNumber,
                    verseRange: currentScope == .range ? currentVerseRange : nil,
                    selectedVerseIds: currentScope == .selected ? Array(context.selectedVerseIds).sorted() : []
                )
                let response = try await aiProvider.generateResponse(message: text, context: providerContext)
                isTyping = false
                messages.append(ChatMessage(content: response, isUser: false))
            } catch {
                isTyping = false
                messages.append(ChatMessage(
                    content: "I couldn't reach Guided Study right now. Please try again in a moment.",
                    isUser: false
                ))
                #if DEBUG
                print("[GuidedStudy] Provider error: \(error.localizedDescription)")
                #endif
            }

            if !state.effectivelyGuided {
                try? await Task.sleep(nanoseconds: 500_000_000)
                showPaywall = true
            }
        }
    }

    private func buildProviderContext() -> String {
        """
        Reference: \(currentReference)
        Scope: \(scopeLabel)
        Passage:
        \(currentVerseText)
        """
    }

    private static func makeDefaultProvider() -> AIProvider {
        if RemoteConfig.useMockGuidedStudyProvider {
            return MockAIProvider()
        }

        if RemoteConfig.hasConfiguredOpenAIProxyBaseURL {
            return OpenAIProxyClient(baseURL: RemoteConfig.openAIProxyBaseURL)
        }

        return MockAIProvider()
    }

    func saveSession() {
        guard let state = appState else { return }

        // Build session messages (skip the welcome message which is at index 0)
        let sessionMessages: [GuidedSessionMessage] = messages.dropFirst().map { msg in
            GuidedSessionMessage(role: msg.isUser ? .user : .assistant, text: msg.content)
        }

        if var session = currentSession {
            // Update existing session
            session.messages = sessionMessages
            session.updatedAt = Date()
            if let firstUserMsg = sessionMessages.first(where: { $0.role == .user })?.text {
                session.updateTitle(from: firstUserMsg)
            }
            state.updateGuidedSession(session)
            currentSession = session
        } else {
            // Create new session
            var newSession = GuidedSession(
                reference: currentReference,
                scope: currentScope,
                scriptureId: context.chapterRef.scriptureId,
                book: context.chapterRef.bookName,
                chapter: context.chapterRef.chapterNumber,
                verseRange: currentVerseRange,
                messages: sessionMessages
            )
            if let firstUserMsg = sessionMessages.first(where: { $0.role == .user })?.text {
                newSession.updateTitle(from: firstUserMsg)
            }
            state.saveGuidedSession(newSession)
            currentSession = newSession
        }

        showSaveConfirmation = true
    }

    var canSave: Bool {
        // Can save if there's at least one user message
        messages.contains { $0.isUser }
    }

    /// Get the last assistant response for saving as insight
    var lastAssistantResponse: String? {
        messages.last(where: { !$0.isUser })?.content
    }
}

// MARK: - Guided Study Screen

struct GuidedStudyScreen: View {
    @StateObject private var viewModel: GuidedStudyViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    private let initialPrompt: String?
    private let showPassagePickerOnAppear: Bool
    @State private var inputText = ""
    @State private var showPassagePicker = false
    @State private var hasSentInitialPrompt = false
    @State private var hasAutoPresentedPicker = false
    @FocusState private var isInputFocused: Bool

    init(
        context: GuidedStudyContext,
        appState: AppState,
        existingSession: GuidedSession? = nil,
        initialPrompt: String? = nil,
        showPassagePickerOnAppear: Bool = false
    ) {
        _viewModel = StateObject(wrappedValue: GuidedStudyViewModel(
            context: context,
            appState: appState,
            existingSession: existingSession
        ))
        self.initialPrompt = initialPrompt
        self.showPassagePickerOnAppear = showPassagePickerOnAppear
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                passageHeader

                Divider()

                // Main content area with empty state handling
                if viewModel.currentVerseText.isEmpty && viewModel.messages.isEmpty {
                    emptyStateView
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach(viewModel.messages) { message in
                                    ChatBubble(message: message)
                                        .id(message.id)
                                }

                                if viewModel.messages.count == 1 {
                                    suggestedPromptsView
                                }

                                if viewModel.isTyping {
                                    TypingIndicator()
                                        .id("typing")
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                        }
                        .onChange(of: viewModel.messages.count) { _, _ in
                            withAnimation {
                                if let lastMessage = viewModel.messages.last {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }

                Divider()

                inputArea
            }
            .themedScreenBackground()
            .navigationTitle("Guided Study")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(SeekTheme.maroonAccent)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    // Save Insight button
                    if viewModel.lastAssistantResponse != nil && viewModel.messages.count > 2 {
                        Button {
                            viewModel.showSaveInsightSheet = true
                        } label: {
                            Image(systemName: "lightbulb")
                        }
                        .foregroundColor(SeekTheme.maroonAccent)
                    }

                    // Save Session button
                    Button {
                        viewModel.saveSession()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .foregroundColor(viewModel.canSave ? SeekTheme.maroonAccent : SeekTheme.textSecondary)
                    .disabled(!viewModel.canSave)
                }
            }
            .sheet(isPresented: $viewModel.showPaywall) {
                PaywallView(triggerType: .guidedStudy)
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showPassagePicker) {
                GuidedPassagePickerSheet(
                    initialSelection: viewModel.currentPassageSelection,
                    initialScope: viewModel.currentScope,
                    initialRange: viewModel.currentVerseRange
                ) { selection, scope, range in
                    Task {
                        await viewModel.applyPassageSelection(selection, scope: scope, verseRange: range)
                    }
                }
            }
            .sheet(isPresented: $viewModel.showSaveInsightSheet) {
                SaveInsightSheet(viewModel: viewModel)
                    .environmentObject(appState)
            }
            .overlay(alignment: .top) {
                if viewModel.showSaveConfirmation {
                    SaveConfirmationBanner()
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation {
                                    viewModel.showSaveConfirmation = false
                                }
                            }
                        }
                }
            }
            .animation(.easeInOut, value: viewModel.showSaveConfirmation)
            .onAppear {
                guard !hasSentInitialPrompt else { return }
                guard let prompt = initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty else { return }
                hasSentInitialPrompt = true
                viewModel.sendMessage(prompt)
            }
            .onAppear {
                guard showPassagePickerOnAppear else { return }
                guard !hasAutoPresentedPicker else { return }
                hasAutoPresentedPicker = true
                showPassagePicker = true
            }
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "text.book.closed")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(SeekTheme.textSecondary.opacity(0.5))
            Text("No passage loaded")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(SeekTheme.textSecondary)
            Text("Try selecting a different passage or go back and try again.")
                .font(.system(size: 14))
                .foregroundColor(SeekTheme.textSecondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Passage Header

    private var passageHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.currentReference)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(SeekTheme.textPrimary)

                    Text(viewModel.scopeLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(SeekTheme.textSecondary)
                }

                Spacer()

                Button {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    showPassagePicker = true
                } label: {
                    Text("Change")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(SeekTheme.maroonAccent)
                }
            }

            if !viewModel.currentVerseText.isEmpty {
                Text(viewModel.currentVerseText)
                    .font(.custom("Georgia", size: 14))
                    .foregroundColor(SeekTheme.textPrimary.opacity(0.85))
                    .lineLimit(2)
                    .lineSpacing(4)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(SeekTheme.cardBackground)
    }

    // MARK: - Suggested Prompts

    private var suggestedPromptsView: some View {
        VStack(spacing: 10) {
            ForEach(viewModel.suggestedPrompts, id: \.self) { prompt in
                Button {
                    viewModel.sendMessage(prompt)
                } label: {
                    Text(prompt)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(SeekTheme.maroonAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(SeekTheme.maroonAccent.opacity(0.08))
                        .cornerRadius(20)
                }
                .disabled(viewModel.hasUsedFreeResponse && !appState.effectivelyGuided)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Input Area

    private var inputArea: some View {
        Group {
            if appState.effectivelyGuided || !viewModel.hasUsedFreeResponse {
                HStack(spacing: 12) {
                    TextField("Ask a question...", text: $inputText, axis: .vertical)
                        .font(.system(size: 15))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(SeekTheme.cardBackground)
                        .cornerRadius(24)
                        .focused($isInputFocused)
                        .lineLimit(1...4)

                    Button {
                        viewModel.sendMessage(inputText)
                        inputText = ""
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(inputText.isEmpty ? SeekTheme.textSecondary : SeekTheme.maroonAccent)
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 14))
                        Text("Session locked")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(SeekTheme.textSecondary)

                    Button {
                        viewModel.showPaywall = true
                    } label: {
                        Text("Unlock Unlimited Guided Study")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(SeekTheme.maroonAccent)
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .background(SeekTheme.creamBackground)
    }
}

// MARK: - Save Insight Sheet

struct SaveInsightSheet: View {
    @ObservedObject var viewModel: GuidedStudyViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var insightTitle: String = ""
    @State private var showSavedConfirmation = false

    private var defaultTitle: String {
        "Insight from \(viewModel.currentReference)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Info
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 14))
                                .foregroundColor(SeekTheme.maroonAccent)
                            Text("Save Insight")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(SeekTheme.textPrimary)
                        }

                        Text("Save this reflection to your Journey for later reference.")
                            .font(.system(size: 14))
                            .foregroundColor(SeekTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(SeekTheme.cardBackground)
                    .cornerRadius(14)

                    // Title input
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Title (optional)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(SeekTheme.textSecondary)
                            .textCase(.uppercase)
                            .tracking(0.5)

                        TextField(defaultTitle, text: $insightTitle)
                            .font(.system(size: 15))
                            .padding(14)
                            .background(SeekTheme.cardBackground)
                            .cornerRadius(10)
                    }

                    // Preview of insight
                    if let response = viewModel.lastAssistantResponse {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Insight Preview")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(SeekTheme.textSecondary)
                                .textCase(.uppercase)
                                .tracking(0.5)

                            Text(response)
                                .font(.system(size: 14))
                                .foregroundColor(SeekTheme.textPrimary)
                                .lineSpacing(4)
                                .padding(14)
                                .background(SeekTheme.cardBackground)
                                .cornerRadius(10)
                        }
                    }

                    // Save button
                    Button {
                        saveInsight()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("Save to Journey")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(SeekTheme.maroonAccent)
                        .cornerRadius(12)
                    }
                }
                .padding(20)
            }
            .themedScreenBackground()
            .navigationTitle("Save Insight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(SeekTheme.maroonAccent)
                }
            }
            .overlay(alignment: .top) {
                if showSavedConfirmation {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.white)
                        Text("Insight saved")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(SeekTheme.maroonAccent)
                    .cornerRadius(20)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func saveInsight() {
        guard let response = viewModel.lastAssistantResponse else { return }

        // Create JourneyStore instance to save insight
        let journeyStore = JourneyStore(appState: appState)

        let title = insightTitle.isEmpty ? nil : insightTitle

        if let sessionId = viewModel.currentSessionId {
            journeyStore.saveInsight(
                title: title,
                body: response,
                quote: viewModel.currentVerseText,
                sessionId: sessionId,
                ref: viewModel.currentScriptureRef
            )
        } else {
            // Save session first if not already saved
            viewModel.saveSession()
            if let sessionId = viewModel.currentSessionId {
                journeyStore.saveInsight(
                    title: title,
                    body: response,
                    quote: viewModel.currentVerseText,
                    sessionId: sessionId,
                    ref: viewModel.currentScriptureRef
                )
            }
        }

        withAnimation {
            showSavedConfirmation = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            dismiss()
        }
    }
}

// MARK: - Save Confirmation Banner

private struct SaveConfirmationBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.white)
            Text("Session saved to My Journey")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(SeekTheme.maroonAccent)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .padding(.top, 60)
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 60) }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.system(size: 15))
                    .foregroundColor(message.isUser ? .white : SeekTheme.textPrimary)
                    .lineSpacing(4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(message.isUser ? SeekTheme.maroonAccent : SeekTheme.cardBackground)
                    .cornerRadius(20)
                    .cornerRadius(message.isUser ? 20 : 20, corners: message.isUser ? [.topLeft, .topRight, .bottomLeft] : [.topLeft, .topRight, .bottomRight])
            }

            if !message.isUser { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var animationPhase = 0

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(SeekTheme.textSecondary)
                        .frame(width: 8, height: 8)
                        .scaleEffect(animationPhase == index ? 1.2 : 0.8)
                        .opacity(animationPhase == index ? 1.0 : 0.4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(SeekTheme.cardBackground)
            .cornerRadius(20)

            Spacer()
        }
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                animationPhase = (animationPhase + 1) % 3
            }
        }
    }
}

// MARK: - Corner Radius Extension

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Paywall Trigger Type

enum PaywallTriggerType {
    case highlight
    case note
    case guidedStudy
}

// MARK: - Paywall View

struct PaywallView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState

    var triggerType: PaywallTriggerType = .guidedStudy

    private var headerTitle: String {
        switch triggerType {
        case .highlight:
            return "Highlight Limit Reached"
        case .note:
            return "Note Limit Reached"
        case .guidedStudy:
            return "Unlock Guided Study"
        }
    }

    private var headerDescription: String {
        switch triggerType {
        case .highlight:
            return "You've reached the free limit of \(AppState.maxHighlightsFree) highlights. Upgrade to save unlimited highlights across all scriptures."
        case .note:
            return "You've reached the free limit of \(AppState.maxNotesFree) notes. Upgrade to write unlimited notes on any verse."
        case .guidedStudy:
            return "Continue your journey with unlimited AI-guided reflection and deeper understanding."
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(SeekTheme.maroonAccent.opacity(0.1))
                                .frame(width: 100, height: 100)

                            Image(systemName: iconForTrigger)
                                .font(.system(size: 44, weight: .medium))
                                .foregroundColor(SeekTheme.maroonAccent)
                        }

                        Text(headerTitle)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(SeekTheme.textPrimary)

                        Text(headerDescription)
                            .font(.system(size: 16))
                            .foregroundColor(SeekTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .padding(.top, 20)

                    VStack(spacing: 16) {
                        FeatureRow(icon: "bubble.left.and.bubble.right.fill", title: "Unlimited Sessions", description: "Continue exploring passages without limits")
                        FeatureRow(icon: "highlighter", title: "Unlimited Highlights", description: "Save as many verses as you need")
                        FeatureRow(icon: "note.text", title: "Unlimited Notes", description: "Write without restrictions")
                        FeatureRow(icon: "heart.fill", title: "Support Development", description: "Help us bring wisdom to more seekers")
                    }
                    .padding(.horizontal, 20)

                    VStack(spacing: 16) {
                        Button {
                            appState.setSandboxMode(true)
                            dismiss()
                        } label: {
                            VStack(spacing: 4) {
                                Text("Become Guided")
                                    .font(.system(size: 18, weight: .bold))
                                Text("$4.99/month")
                                    .font(.system(size: 14, weight: .medium))
                                    .opacity(0.9)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(SeekTheme.maroonAccent)
                            .cornerRadius(14)
                        }

                        Button {
                            dismiss()
                        } label: {
                            Text("Restore Purchases")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(SeekTheme.textSecondary)
                        }
                    }
                    .padding(.horizontal, 20)

                    Text("Cancel anytime. Recurring billing.")
                        .font(.system(size: 12))
                        .foregroundColor(SeekTheme.textSecondary.opacity(0.7))
                }
                .padding(.bottom, 40)
            }
            .themedScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(SeekTheme.textSecondary.opacity(0.5))
                    }
                }
            }
        }
    }

    private var iconForTrigger: String {
        switch triggerType {
        case .highlight:
            return "highlighter"
        case .note:
            return "note.text"
        case .guidedStudy:
            return "sparkles"
        }
    }
}

// MARK: - Feature Row

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(SeekTheme.maroonAccent.opacity(0.1))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(SeekTheme.maroonAccent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(SeekTheme.textPrimary)

                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(SeekTheme.textSecondary)
            }

            Spacer()
        }
        .padding(16)
        .background(SeekTheme.cardBackground)
        .cornerRadius(14)
    }
}

// MARK: - Preview

#Preview("Guided Study") {
    let context = GuidedStudyContext(
        chapterRef: ChapterRef(scriptureId: "bible-kjv", bookId: "genesis", chapterNumber: 1, bookName: "Genesis"),
        verses: [
            LoadedVerse(id: "1", number: 1, text: "In the beginning God created the heaven and the earth."),
            LoadedVerse(id: "2", number: 2, text: "And the earth was without form, and void."),
        ],
        selectedVerseIds: [],
        textName: "Bible (KJV)",
        traditionId: "christianity",
        traditionName: "Christianity"
    )
    GuidedStudyScreen(context: context, appState: AppState())
        .environmentObject(AppState())
}

#Preview("Paywall") {
    PaywallView()
        .environmentObject(AppState())
}

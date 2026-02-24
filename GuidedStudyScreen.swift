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
    func generateResponse(messages: [GuidedStudyChatMessage], context: GuidedStudyProviderContext) async throws -> String
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

    func generateResponse(messages: [GuidedStudyChatMessage], context: GuidedStudyProviderContext) async throws -> String {
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

    init(from studyMessage: StudyMessage) {
        self.id = studyMessage.id
        self.content = studyMessage.content
        self.isUser = studyMessage.role == "user"
        self.timestamp = studyMessage.timestamp
    }
}

struct DisplayChatMessage: Identifiable {
    let id: String
    let content: String
    let isUser: Bool
}

// MARK: - Guided Study View Model

@MainActor
class GuidedStudyViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isTyping = false
    @Published var hasUsedFreeResponse = false
    @Published var showSaveConfirmation = false
    @Published var showSaveInsightSheet = false
    @Published var showServiceUnavailableError = false

    @Published var currentScope: GuidedSessionScope
    @Published var currentVerseRange: ClosedRange<Int>?
    @Published var currentReference: String
    @Published var currentVerseText: String
    @Published var isSwitchingPassage = false
    @Published var isHydratingResume = false
    @Published var studyContext: StudyContext

    private var context: GuidedStudyContext
    let aiProvider: AIProvider
    private let studyStore = StudyStore.shared
    private var pendingMessageAfterUnlock: String?
    private var lastFailedMessageText: String?
    private var lastFailedConversationID: UUID?
    private let welcomeMessageText = """
    Welcome to Guided Study. This is a space to explore the passage with curiosity and reflection.

    Take a moment to read through the text. When you're ready, choose a prompt below or add your own question.
    """
    private var trimmedWelcomeMessageText: String {
        welcomeMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private weak var appState: AppState?
    private var currentConversation: StudyConversation?
    private let maxUserMessageCharacters = 1_200

    init(context: GuidedStudyContext, appState: AppState, existingConversation: StudyConversation? = nil, aiProvider: AIProvider? = nil) {
        self.context = context
        self.appState = appState
        self.aiProvider = aiProvider ?? Self.makeDefaultProvider()
        let resolvedStudyContext = Self.resolveInitialStudyContext(
            context: context,
            existingConversation: existingConversation
        )
        self.studyContext = resolvedStudyContext

        // Check if user has reached today's free-tier message limit
        hasUsedFreeResponse = EntitlementManager.shared.isPremium ? false : !StudyUsageTracker.shared.canSendMessageToday()

        // Determine initial scope based on context or existing session
        let initialScope: GuidedSessionScope
        let initialVerseRange: ClosedRange<Int>?
        let isGeneralConversation: Bool
        if case .general = resolvedStudyContext {
            isGeneralConversation = true
        } else {
            isGeneralConversation = false
        }

        if isGeneralConversation {
            initialScope = .chapter
            initialVerseRange = nil
        } else if let conversation = existingConversation {
            // Resuming an existing session - use its scope
            if let start = conversation.verseStart, let end = conversation.verseEnd {
                initialScope = (start == end) ? .selected : .range
                initialVerseRange = start...end
            } else {
                initialScope = .chapter
                initialVerseRange = nil
            }
        } else if !context.selectedVerseIds.isEmpty {
            // New session with selected verses - use selected scope
            initialScope = .selected
            let selectedNumbers = context.verses
                .filter { context.selectedVerseIds.contains($0.id) }
                .map(\.number)
            if let min = selectedNumbers.min(), let max = selectedNumbers.max() {
                initialVerseRange = min...max
            } else {
                initialVerseRange = nil
            }
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
        self.currentReference = isGeneralConversation ? "" : passage.reference
        self.currentVerseText = isGeneralConversation ? "" : passage.verseText

        // Load existing session messages or create welcome
        if let conversation = existingConversation {
            isHydratingResume = true
            loadConversation(conversation)
            Task { [weak self] in
                await self?.hydrateResumedConversationIfNeeded(conversation)
            }
        } else {
            if isGeneralConversation {
                currentConversation = studyStore.createGeneralConversation()
                addWelcomeMessage()
            } else {
                let passage = makePassageRef()
                if let conversation = studyStore.fetchConversationForPassage(passage) {
                    loadConversation(conversation)
                } else {
                    currentConversation = studyStore.createConversation(passage)
                    addWelcomeMessage()
                }
            }
            maybeRespondToPendingUserMessage()
        }
    }

    private func loadConversation(_ conversation: StudyConversation) {
        currentConversation = conversation
        let stored = studyStore.loadMessages(conversationId: conversation.id)
        if stored.isEmpty {
            addWelcomeMessage()
        } else {
            for msg in stored {
                messages.append(ChatMessage(from: msg))
            }
        }
    }

    private func addWelcomeMessage() {
        messages.append(ChatMessage(content: welcomeMessageText, isUser: false))
    }

    var suggestedPrompts: [String] {
        if !isGeneralMode {
            return [
                "Explore the context of this passage",
                "Summarize what is happening here",
                "Help me reflect on this",
                "Identify themes in this passage"
            ]
        }

        guard let latestUserMessage = latestUserMessageForPromptChips else {
            return [
                "Help me learn the basics",
                "What should I explore next?",
                "Explain this clearly and respectfully",
                "Suggest a passage to start with"
            ]
        }

        switch classifyGeneralPromptCategory(for: latestUserMessage) {
        case .traditionOverview:
            return [
                "Key beliefs and practices",
                "Important texts and terms",
                "Common questions beginners ask",
                "Suggest a passage to read first"
            ]
        case .bookOverview:
            return [
                "High-level summary",
                "Main themes",
                "Historical context",
                "Where should I start reading?"
            ]
        case .conceptTheme:
            return [
                "Define the concept",
                "How different traditions view this",
                "Everyday application",
                "Suggest related passages"
            ]
        case .personalReflection:
            return [
                "A gentle reflection",
                "A practical next step",
                "A short guided prompt for journaling",
                "Suggest a comforting passage"
            ]
        case .fallback:
            return [
                "Clarify what you mean",
                "Offer a balanced overview",
                "Suggest a passage to anchor this",
                "What would you like to focus on?"
            ]
        }
    }

    var isGeneralMode: Bool {
        if case .general = studyContext {
            return true
        }
        return studyContext.scriptureRef == nil
    }

    var showsPassageHeader: Bool {
        studyContext.scriptureRef != nil && !currentReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var visibleMessages: [ChatMessage] {
        guard messages.first?.content == welcomeMessageText,
              messages.contains(where: { $0.isUser }) else {
            return messages
        }
        return Array(messages.dropFirst())
    }

    var hasUserMessages: Bool {
        messages.contains(where: { $0.isUser })
    }

    var hasAssistantMessages: Bool {
        messages.contains { message in
            !isWelcomeAssistantMessage(message)
        }
    }

    var shouldShowStarterPrompts: Bool {
        !hasUserMessages && !hasAssistantMessages && !isTyping
    }

    var scopeLabel: String {
        let chapterLabel = ScriptureTerminology.chapterLabel(for: context.chapterRef.scriptureId)
        let verseLabel = ScriptureTerminology.verseLabel(for: context.chapterRef.scriptureId)
        let verseLabelPlural = ScriptureTerminology.verseLabelLowercased(for: context.chapterRef.scriptureId, plural: true).capitalized

        switch currentScope {
        case .chapter:
            return "Read Entire \(chapterLabel)"
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
        let scriptureId = currentConversation?.scriptureId ?? context.chapterRef.scriptureId
        let bookId = currentConversation?.bookId ?? context.chapterRef.bookId
        let chapter = currentConversation?.chapter ?? context.chapterRef.chapterNumber
        let fallbackBookName = currentConversation?.bookId ?? context.chapterRef.bookName
        let fallbackScriptureName = context.textName
        let fallbackTraditionId = context.traditionId
        let fallbackTraditionName = context.traditionName

        let library = LibraryData.shared
        if scriptureId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGeneralMode {
            if let tradition = library.traditions.first,
               let scripture = tradition.texts.first,
               let book = scripture.books.first {
                return GuidedPassageSelectionRef(
                    traditionId: tradition.id,
                    traditionName: tradition.name,
                    scriptureId: scripture.id,
                    scriptureName: scripture.name,
                    bookId: book.id,
                    bookName: book.name,
                    chapterNumber: 1
                )
            }
        }
        let matchedTradition = library.traditions.first { tradition in
            tradition.texts.contains(where: { $0.id == scriptureId })
        }
        let matchedScripture = matchedTradition?.texts.first(where: { $0.id == scriptureId })
        let matchedBook = matchedScripture?.books.first(where: { $0.id == bookId })

        return GuidedPassageSelectionRef(
            traditionId: matchedTradition?.id ?? fallbackTraditionId,
            traditionName: matchedTradition?.name ?? fallbackTraditionName,
            scriptureId: scriptureId,
            scriptureName: matchedScripture?.name ?? fallbackScriptureName,
            bookId: bookId,
            bookName: matchedBook?.name ?? fallbackBookName,
            chapterNumber: chapter
        )
    }

    var currentScriptureRef: ScriptureRef {
        if let ref = studyContext.scriptureRef {
            return ref
        }
        return ScriptureRef(
            scriptureId: context.chapterRef.scriptureId,
            bookId: context.chapterRef.bookId,
            chapter: context.chapterRef.chapterNumber,
            verseStart: currentVerseRange?.lowerBound,
            verseEnd: currentVerseRange?.upperBound,
            display: currentReference
        )
    }

    var currentSessionId: UUID? {
        currentConversation?.id
    }

    private var latestUserMessageForPromptChips: String? {
        messages
            .reversed()
            .first(where: { $0.isUser })?
            .content
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum GeneralPromptCategory {
        case traditionOverview
        case bookOverview
        case conceptTheme
        case personalReflection
        case fallback
    }

    private func classifyGeneralPromptCategory(for message: String) -> GeneralPromptCategory {
        let normalized = message.lowercased()

        let personalMarkers = [
            "i feel", "i'm feeling", "im feeling", "i am feeling", "anxious", "anxiety",
            "stressed", "overwhelmed", "afraid", "sad", "grief", "lonely",
            "how do i apply this", "apply this spiritually", "in my life",
            "personally", "i struggle", "i am struggling", "help me apply"
        ]
        if personalMarkers.contains(where: { normalized.contains($0) }) {
            return .personalReflection
        }

        let traditionMarkers = [
            "tell me about islam", "what is islam", "tell me about buddhism", "what is buddhism",
            "tell me about christianity", "what is christianity", "tell me about hinduism",
            "what is hinduism", "tell me about judaism", "what is judaism",
            "tell me about sikhism", "what is sikhism", "tell me about taoism",
            "what is taoism", "tell me about religion", "about this tradition"
        ]
        if traditionMarkers.contains(where: { normalized.contains($0) }) {
            return .traditionOverview
        }

        let bookMarkers = [
            "what is revelation about", "what is exodus about", "what is genesis about",
            "what happens in", "overview of", "summary of", "book of", "chapter overview",
            "surah", "psalms", "proverbs", "gospel", "revelation", "exodus", "genesis"
        ]
        if bookMarkers.contains(where: { normalized.contains($0) }) {
            return .bookOverview
        }

        let conceptMarkers = [
            "what is karma", "what is salvation", "what is prayer", "what is grace",
            "what is sin", "what is forgiveness", "what is faith", "what is dharma",
            "what is enlightenment", "what is meditation", "meaning of", "define",
            "concept of", "theme of"
        ]
        if conceptMarkers.contains(where: { normalized.contains($0) }) {
            return .conceptTheme
        }

        return .fallback
    }

    func changePassage(scope: GuidedSessionScope, verseRange: ClosedRange<Int>? = nil) {
        currentScope = scope
        currentVerseRange = verseRange
        let passage = context.buildPassage(scope: scope, verseRange: verseRange)
        currentReference = passage.reference
        currentVerseText = passage.verseText
        studyContext = .passage(scriptureRef: ScriptureRef(
            scriptureId: context.chapterRef.scriptureId,
            bookId: context.chapterRef.bookId,
            chapter: context.chapterRef.chapterNumber,
            verseStart: verseRange?.lowerBound,
            verseEnd: verseRange?.upperBound,
            display: passage.reference
        ))
    }

    func applyPassageSelection(
        _ selection: GuidedPassageSelectionRef,
        scope: GuidedSessionScope,
        verseRange: ClosedRange<Int>?
    ) async {
        guard !isSwitchingPassage else { return }
        guard appState?.canUseGuidedStudy() ?? UsageLimitManager.shared.canPerform(.guidedStudyMessage) else {
            hasUsedFreeResponse = true
            appState?.presentPaywall(.guidedStudyLimit)
            return
        }

        isSwitchingPassage = true
        defer {
            isSwitchingPassage = false
        }

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
            studyContext = .passage(scriptureRef: ScriptureRef(
                scriptureId: selection.scriptureId,
                bookId: selection.bookId,
                chapter: selection.chapterNumber,
                verseStart: safeRange?.lowerBound,
                verseEnd: safeRange?.upperBound,
                display: passage.reference
            ))

            messages = []
            let passageRef = makePassageRef()
            currentConversation = studyStore.createConversation(passageRef)
            addWelcomeMessage()
            pendingMessageAfterUnlock = nil
            lastFailedMessageText = nil
            lastFailedConversationID = nil
            showServiceUnavailableError = false
            isTyping = false
        } catch {
            messages.append(ChatMessage(
                content: "I couldn't load that passage right now. Please try another selection.",
                isUser: false
            ))
        }
    }

    func sendMessage(_ text: String) async {
        guard !isTyping else { return }
        guard !isHydratingResume else { return }
        guard !isSwitchingPassage else { return }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        guard guardGuidedStudyAccessOrPresentPaywall(pendingMessage: trimmedText) else { return }
        guard trimmedText.count <= maxUserMessageCharacters else {
            showServiceUnavailableError = false
            messages.append(ChatMessage(
                content: "Please keep messages under \(maxUserMessageCharacters) characters.",
                isUser: false
            ))
            return
        }
        showServiceUnavailableError = false
        lastFailedMessageText = nil
        lastFailedConversationID = nil

        guard let conversationID = persistUserMessageForSending(trimmedText) else { return }
        isTyping = true

        await requestAssistantReply(
            messageText: trimmedText,
            conversationID: conversationID
        )
    }

    func retryLastRequest() async {
        guard !isTyping else { return }
        guard !isHydratingResume else { return }
        guard let messageText = lastFailedMessageText,
              let conversationID = lastFailedConversationID else { return }
        guard guardGuidedStudyAccessOrPresentPaywall(pendingMessage: messageText) else { return }
        showServiceUnavailableError = false
        isTyping = true

        await requestAssistantReply(
            messageText: messageText,
            conversationID: conversationID
        )
    }

    func completePremiumUnlock() {
        appState?.dismissPaywall()
        refreshFreeLimitState()
        guard let pending = pendingMessageAfterUnlock else { return }
        pendingMessageAfterUnlock = nil
        Task {
            await sendMessage(pending)
        }
    }

    private func refreshFreeLimitState() {
        if EntitlementManager.shared.isPremium {
            hasUsedFreeResponse = false
        } else {
            hasUsedFreeResponse = !StudyUsageTracker.shared.canSendMessageToday()
        }
    }

    private func buildProxyMessages() -> [GuidedStudyChatMessage] {
        messages.compactMap { message in
            let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if isWelcomeAssistantMessage(message) {
                return nil
            }
            return GuidedStudyChatMessage(role: message.isUser ? "user" : "assistant", content: trimmed)
        }
    }

    private func persistUserMessageForSending(_ messageText: String) -> UUID? {
        ensureConversationIfNeeded()
        guard let conversationID = currentConversation?.id else { return nil }

        messages.append(ChatMessage(content: messageText, isUser: true))
        studyStore.appendMessage(
            conversationId: conversationID,
            message: StudyMessage(conversationId: conversationID, role: "user", content: messageText)
        )
        updateConversationTitleIfNeeded()
        return conversationID
    }

    private func isWelcomeAssistantMessage(_ message: ChatMessage) -> Bool {
        guard !message.isUser else { return false }
        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed == trimmedWelcomeMessageText
    }

    private func maybeRespondToPendingUserMessage() {
        guard !isTyping else { return }
        guard !isHydratingResume else { return }
        guard let conversationID = currentConversation?.id else { return }
        guard let pendingText = latestPendingUserMessageText() else { return }
        guard guardGuidedStudyAccessOrPresentPaywall(pendingMessage: pendingText) else { return }

        isTyping = true
        Task {
            await requestAssistantReply(
                messageText: pendingText,
                conversationID: conversationID
            )
        }
    }

    func sendMessageWhenReady(_ text: String) async {
        while isHydratingResume {
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        await sendMessage(text)
    }

    private func hydrateResumedConversationIfNeeded(_ conversation: StudyConversation) async {
        defer {
            isHydratingResume = false
            maybeRespondToPendingUserMessage()
        }

        guard case .passage = conversation.context else {
            return
        }

        let scriptureId = conversation.scriptureId.trimmingCharacters(in: .whitespacesAndNewlines)
        let bookId = conversation.bookId.trimmingCharacters(in: .whitespacesAndNewlines)
        let chapter = conversation.chapter

        guard !scriptureId.isEmpty, !bookId.isEmpty, chapter > 0 else {
            applyResumeHydrationFallback()
            return
        }

        do {
            let loadedVerses = try await RemoteDataService.shared.loadChapter(
                scriptureId: scriptureId,
                bookId: bookId,
                chapter: chapter
            )
            guard !loadedVerses.isEmpty else {
                applyResumeHydrationFallback()
                return
            }

            let maxVerse = loadedVerses.map(\.number).max() ?? 1
            var safeRange: ClosedRange<Int>?
            if let start = conversation.verseStart, let end = conversation.verseEnd {
                let lower = max(1, min(start, maxVerse))
                let upper = max(lower, min(end, maxVerse))
                safeRange = lower...upper
            }

            context = GuidedStudyContext(
                chapterRef: ChapterRef(
                    scriptureId: scriptureId,
                    bookId: bookId,
                    chapterNumber: chapter,
                    bookName: context.chapterRef.bookName
                ),
                verses: loadedVerses,
                selectedVerseIds: [],
                textName: context.textName,
                traditionId: context.traditionId,
                traditionName: context.traditionName
            )

            let resolvedScope: GuidedSessionScope
            if let safeRange {
                resolvedScope = safeRange.lowerBound == safeRange.upperBound ? .selected : .range
            } else {
                resolvedScope = .chapter
            }
            currentScope = resolvedScope
            currentVerseRange = safeRange

            let passage = context.buildPassage(scope: resolvedScope, verseRange: safeRange)
            currentReference = passage.reference
            currentVerseText = passage.verseText
            studyContext = .passage(scriptureRef: ScriptureRef(
                scriptureId: scriptureId,
                bookId: bookId,
                chapter: chapter,
                verseStart: safeRange?.lowerBound,
                verseEnd: safeRange?.upperBound,
                display: passage.reference
            ))
        } catch {
            applyResumeHydrationFallback()
        }
    }

    private func applyResumeHydrationFallback() {
        context = GuidedStudyContext(
            chapterRef: ChapterRef(
                scriptureId: "guided-study",
                bookId: "passage",
                chapterNumber: 1,
                bookName: "Passage"
            ),
            verses: [],
            selectedVerseIds: [],
            textName: "",
            traditionId: "",
            traditionName: ""
        )
        studyContext = .general
        currentScope = .chapter
        currentVerseRange = nil
        currentReference = ""
        currentVerseText = ""
        currentConversation = studyStore.createGeneralConversation()
        messages = []
        addWelcomeMessage()
        pendingMessageAfterUnlock = nil
        lastFailedMessageText = nil
        lastFailedConversationID = nil
        showServiceUnavailableError = false
        isTyping = false
    }

    private func latestPendingUserMessageText() -> String? {
        guard let latestUserIndex = messages.lastIndex(where: { $0.isUser }) else {
            return nil
        }
        if let latestAssistantIndex = messages.lastIndex(where: { !isWelcomeAssistantMessage($0) }),
           latestAssistantIndex > latestUserIndex {
            return nil
        }

        let pending = messages[latestUserIndex].content.trimmingCharacters(in: .whitespacesAndNewlines)
        return pending.isEmpty ? nil : pending
    }

    private func guardGuidedStudyAccessOrPresentPaywall(pendingMessage: String) -> Bool {
        let canUseGuidedStudy = appState?.canUseGuidedStudy() ?? UsageLimitManager.shared.canPerform(.guidedStudyMessage)
        if canUseGuidedStudy {
            hasUsedFreeResponse = false
            return true
        } else {
            handleGuidedStudyLimitReached(pendingMessage: pendingMessage)
            return false
        }
    }

    private func handleGuidedStudyLimitReached(pendingMessage: String) {
        hasUsedFreeResponse = true
        pendingMessageAfterUnlock = pendingMessage
        appState?.presentPaywall(.guidedStudyLimit, onUnlock: { [weak self] in
            self?.completePremiumUnlock()
        })
    }

    private static func makeDefaultProvider() -> AIProvider {
        if RemoteConfig.useMockGuidedStudyProvider {
            return MockAIProvider()
        }

        return OpenAIProxyClient(baseURL: RemoteConfig.guidedStudyProxyBaseURL)
    }

    private static func resolveInitialStudyContext(
        context: GuidedStudyContext,
        existingConversation: StudyConversation?
    ) -> StudyContext {
        if let existingConversation {
            return existingConversation.context
        }

        let isPlaceholderContext = context.chapterRef.scriptureId == "guided-study" || context.verses.isEmpty
        if isPlaceholderContext {
            return .general
        }

        return .passage(scriptureRef: ScriptureRef(
            scriptureId: context.chapterRef.scriptureId,
            bookId: context.chapterRef.bookId,
            chapter: context.chapterRef.chapterNumber,
            verseStart: nil,
            verseEnd: nil,
            display: context.chapterRef.bookName
        ))
    }

    private func requestAssistantReply(messageText: String, conversationID: UUID) async {
        do {
            let scriptureRefForProvider: String
            let passageTextForProvider: String
            if case .passage = studyContext {
                scriptureRefForProvider = currentReference
                passageTextForProvider = currentVerseText
            } else {
                scriptureRefForProvider = "General Study"
                passageTextForProvider = ""
            }
            let providerContext = GuidedStudyProviderContext(
                scriptureRef: scriptureRefForProvider,
                passageText: passageTextForProvider,
                locale: Locale.current.identifier
            )

            let proxyMessages = buildProxyMessages()
            let response = try await aiProvider.generateResponse(messages: proxyMessages, context: providerContext)

            isTyping = false
            showServiceUnavailableError = false
            lastFailedMessageText = nil
            lastFailedConversationID = nil

            messages.append(ChatMessage(content: response, isUser: false))
            studyStore.appendMessage(
                conversationId: conversationID,
                message: StudyMessage(conversationId: conversationID, role: "assistant", content: response)
            )

            if !EntitlementManager.shared.isPremium {
                StudyUsageTracker.shared.incrementAfterSend()
            }
            refreshFreeLimitState()
        } catch {
            isTyping = false
            lastFailedMessageText = messageText
            lastFailedConversationID = conversationID

            if let proxyError = error as? OpenAIProxyClientError,
               case .httpError(let statusCode, _) = proxyError {
                showServiceUnavailableError = false
                if statusCode == 429 {
                    messages.append(ChatMessage(
                        content: "You’re sending messages too quickly. Please wait a moment and try again.",
                        isUser: false
                    ))
                } else if statusCode == 400 {
                    messages.append(ChatMessage(
                        content: "Something went wrong. Please try again.",
                        isUser: false
                    ))
                } else {
                    messages.append(ChatMessage(
                        content: "Something went wrong. Please try again.",
                        isUser: false
                    ))
                }
            } else {
                showServiceUnavailableError = false
                messages.append(ChatMessage(
                    content: "Something went wrong. Please try again.",
                    isUser: false
                ))
            }
        }
    }

    func saveSession() {
        ensureConversationIfNeeded()
        if let conversationID = currentConversation?.id {
            studyStore.updateConversationTimestamp(conversationId: conversationID)
            updateConversationTitleIfNeeded()
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

    private func ensureConversationIfNeeded() {
        if currentConversation == nil {
            if isGeneralMode {
                currentConversation = studyStore.createGeneralConversation()
            } else {
                let passage = makePassageRef()
                if let conversation = studyStore.fetchConversationForPassage(passage) {
                    currentConversation = conversation
                } else {
                    currentConversation = studyStore.createConversation(passage)
                }
            }
        }
    }

    private func updateConversationTitleIfNeeded() {
        guard let conversationID = currentConversation?.id else { return }
        guard let firstUser = messages.first(where: { $0.isUser }) else { return }
        let fallbackTitle = isGeneralMode ? "General Conversation" : currentReference
        studyStore.updateConversationTitle(
            conversationId: conversationID,
            firstUserMessage: firstUser.content,
            fallbackTitle: fallbackTitle
        )
    }

    private func makePassageRef() -> StudyPassageRef {
        let verseStart: Int?
        let verseEnd: Int?

        switch currentScope {
        case .chapter:
            verseStart = nil
            verseEnd = nil
        case .range:
            verseStart = currentVerseRange?.lowerBound
            verseEnd = currentVerseRange?.upperBound
        case .selected:
            let selectedNumbers = context.verses
                .filter { context.selectedVerseIds.contains($0.id) }
                .map(\.number)
            if let min = selectedNumbers.min(), let max = selectedNumbers.max() {
                verseStart = min
                verseEnd = max
            } else if let range = currentVerseRange {
                verseStart = range.lowerBound
                verseEnd = range.upperBound
            } else {
                verseStart = nil
                verseEnd = nil
            }
        }

        return StudyPassageRef(
            scriptureId: context.chapterRef.scriptureId,
            bookId: context.chapterRef.bookId,
            chapter: context.chapterRef.chapterNumber,
            verseStart: verseStart,
            verseEnd: verseEnd,
            fallbackTitle: currentReference
        )
    }
}

// MARK: - Guided Study Screen

struct GuidedStudyScreen: View {
    @StateObject private var viewModel: GuidedStudyViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    private let initialPrompt: String?
    private let initialInputText: String
    private let showPassagePickerOnAppear: Bool
    private let autoFocusInputOnAppear: Bool
    @State private var inputText = ""
    @State private var showPassagePicker = false
    @State private var hasSentInitialPrompt = false
    @State private var hasAutoPresentedPicker = false
    @State private var showAllPrompts = false
    @State private var showReader = false
    @State private var didMarkStreakForAppearance = false
    @State private var showShareOptions = false
    @State private var hasInitialized = false
    @State private var isOpeningGuidedStudy = false
    @FocusState private var isInputFocused: Bool

    init(
        context: GuidedStudyContext,
        appState: AppState,
        existingConversation: StudyConversation? = nil,
        initialPrompt: String? = nil,
        initialInputText: String? = nil,
        showPassagePickerOnAppear: Bool = false,
        autoFocusInputOnAppear: Bool = false
    ) {
        _viewModel = StateObject(wrappedValue: GuidedStudyViewModel(
            context: context,
            appState: appState,
            existingConversation: existingConversation
        ))
        self.initialPrompt = initialPrompt
        let trimmedInitialInput = initialInputText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.initialInputText = trimmedInitialInput
        _inputText = State(initialValue: trimmedInitialInput)
        self.showPassagePickerOnAppear = showPassagePickerOnAppear
        self.autoFocusInputOnAppear = autoFocusInputOnAppear
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.showsPassageHeader {
                    passageHeader
                    Divider()
                } else if viewModel.isGeneralMode {
                    generalModeAttachmentBar
                }

                // Main content area with empty state handling
                if viewModel.currentVerseText.isEmpty && viewModel.messages.isEmpty {
                    emptyStateView
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach(displayMessages) { message in
                                    ChatBubble(message: message)
                                        .id(message.id)
                                }

                                if viewModel.shouldShowStarterPrompts {
                                    suggestedPromptsView
                                }

                                if viewModel.showServiceUnavailableError {
                                    GuidedStudyUnavailableInlineView {
                                        Task { await viewModel.retryLastRequest() }
                                    }
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
                                if let lastMessage = displayMessages.last {
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
                        handleShareTapped()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .foregroundColor(
                        viewModel.currentVerseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? SeekTheme.textSecondary
                            : SeekTheme.maroonAccent
                    )
                    .disabled(viewModel.currentVerseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $showPassagePicker) {
                GuidedPassagePickerSheet(
                    initialSelection: viewModel.currentPassageSelection,
                    initialScope: viewModel.currentScope,
                    initialRange: viewModel.currentVerseRange
                ) { selection, scope, range in
                    guard !isOpeningGuidedStudy else { return }
                    Task {
                        await viewModel.applyPassageSelection(selection, scope: scope, verseRange: range)
                    }
                }
            }
            .sheet(isPresented: $viewModel.showSaveInsightSheet) {
                SaveInsightSheet(viewModel: viewModel)
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showAllPrompts) {
                MorePromptsSheet(
                    prompts: viewModel.suggestedPrompts,
                    isLocked: viewModel.isTyping || viewModel.isSwitchingPassage || viewModel.isHydratingResume
                ) { prompt in
                    Task { await viewModel.sendMessage(prompt) }
                }
            }
            .confirmationDialog("Share", isPresented: $showShareOptions, titleVisibility: .visible) {
                Button("Share passage only") {
                    sharePassageOnly()
                }
                Button("Share passage + my reflection") {
                    if let reflection = latestUserReflection {
                        sharePassageAndReflection(reflection)
                    } else {
                        sharePassageOnly()
                    }
                }
                Button("Share my reflection only") {
                    if let reflection = latestUserReflection {
                        shareReflectionOnly(reflection)
                    } else {
                        sharePassageOnly()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .fullScreenCover(isPresented: $showReader) {
                NavigationStack {
                    ReaderScreen(
                        chapterRef: ChapterRef(
                            scriptureId: viewModel.currentPassageSelection.scriptureId,
                            bookId: viewModel.currentPassageSelection.bookId,
                            chapterNumber: viewModel.currentPassageSelection.chapterNumber,
                            bookName: viewModel.currentPassageSelection.bookName
                        ),
                        initialVerseNumber: viewModel.currentVerseRange?.lowerBound
                    )
                    .environmentObject(appState)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showReader = false }
                                .foregroundColor(SeekTheme.maroonAccent)
                        }
                    }
                }
            }
            .overlay(alignment: .top) {
                if viewModel.showSaveConfirmation {
                    SaveConfirmationBanner()
                        .allowsHitTesting(false)
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
                guard !hasInitialized, !isOpeningGuidedStudy else { return }
                isOpeningGuidedStudy = true
                defer {
                    hasInitialized = true
                    isOpeningGuidedStudy = false
                }
                if !didMarkStreakForAppearance {
                    didMarkStreakForAppearance = true
                    StreakTracker.shared.markEngaged(source: .study)
                }
                if !hasSentInitialPrompt,
                   let prompt = initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !prompt.isEmpty {
                    hasSentInitialPrompt = true
                    Task { await viewModel.sendMessageWhenReady(prompt) }
                }

                if showPassagePickerOnAppear, !hasAutoPresentedPicker {
                    hasAutoPresentedPicker = true
                    showPassagePicker = true
                }

                if autoFocusInputOnAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        if !initialInputText.isEmpty {
                            inputText = initialInputText
                        }
                        isInputFocused = true
                    }
                }
            }
            .onDisappear {
                didMarkStreakForAppearance = false
            }
        }
    }

    private var latestUserReflection: String? {
        for message in viewModel.messages.reversed() where message.isUser {
            let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private var displayMessages: [DisplayChatMessage] {
        viewModel.visibleMessages.flatMap { message in
            let normalized = normalizeAssistantContent(message.content, isUser: message.isUser)
            let chunks = splitAssistantIntoBubblesIfNeeded(normalized, isUser: message.isUser)
            return chunks.enumerated().map { index, chunk in
                let suffix = index == 0 ? "" : "-\(index)"
                return DisplayChatMessage(
                    id: "\(message.id.uuidString)\(suffix)",
                    content: chunk,
                    isUser: message.isUser
                )
            }
        }
    }

    private func normalizeAssistantContent(_ text: String, isUser: Bool) -> String {
        guard !isUser else { return text }
        let originalTrimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !originalTrimmed.isEmpty else { return text }
        guard !containsMarkdownBlockSyntax(originalTrimmed) else { return text }

        let spacingNormalized = normalizeAssistantSpacing(text)
        let trimmed = spacingNormalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains("\n") else { return spacingNormalized }
        guard trimmed.count > 420 else { return spacingNormalized }

        let sentences = splitSentences(trimmed)
        guard sentences.count >= 3 else { return spacingNormalized }

        var paragraphs: [String] = []
        var cursor = 0
        while cursor < sentences.count {
            let end = min(cursor + 2, sentences.count)
            paragraphs.append(sentences[cursor..<end].joined(separator: " "))
            cursor = end
        }
        return paragraphs.joined(separator: "\n\n")
    }

    private func normalizeAssistantSpacing(_ text: String) -> String {
        var normalized = text

        normalized = normalized.replacingOccurrences(
            of: #"(?<=[A-Za-z0-9\)\.\!\?])\n(?=[A-Za-z0-9])"#,
            with: " ",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: #"(?<=[a-z\)][\.\!\?])(?=[A-Z])"#,
            with: " ",
            options: .regularExpression
        )

        return normalized
    }

    private func splitAssistantIntoBubblesIfNeeded(_ text: String, isUser: Bool) -> [String] {
        guard !isUser else { return [text] }
        guard text.count > 1800 else { return [text] }
        guard !containsMarkdownBlockSyntax(text) else { return [text] }

        let paragraphs = text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard paragraphs.count >= 2 else { return [text] }

        let targetChunkSize = max(700, text.count / 3)
        var chunks: [String] = []
        var current: [String] = []
        var currentCount = 0

        for paragraph in paragraphs {
            let nextCount = currentCount + paragraph.count + (current.isEmpty ? 0 : 2)
            if !current.isEmpty && nextCount > targetChunkSize && chunks.count < 2 {
                chunks.append(current.joined(separator: "\n\n"))
                current = [paragraph]
                currentCount = paragraph.count
            } else {
                current.append(paragraph)
                currentCount = nextCount
            }
        }

        if !current.isEmpty {
            chunks.append(current.joined(separator: "\n\n"))
        }

        return chunks.count > 1 ? chunks : [text]
    }

    private func containsMarkdownBlockSyntax(_ text: String) -> Bool {
        if text.contains("```") { return true }
        if text.contains("\n") {
            let pattern = #"(?m)^\s{0,3}(([-*+]\s)|(\d+\.\s)|(#)|(\>))"#
            return text.range(of: pattern, options: .regularExpression) != nil
        }
        return false
    }

    private func splitSentences(_ text: String) -> [String] {
        let pattern = #"[^.!?]+[.!?]["')\]]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [text]
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)
        guard !matches.isEmpty else { return [text] }

        let sentences = matches.compactMap { match -> String? in
            guard let range = Range(match.range, in: text) else { return nil }
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            return sentence.isEmpty ? nil : sentence
        }

        return sentences.isEmpty ? [text] : sentences
    }

    private func handleShareTapped() {
        if latestUserReflection != nil {
            showShareOptions = true
            return
        }
        sharePassageOnly()
    }

    private func sharePassageOnly() {
        ShareManager.shared.shareGuidedStudy(
            reference: viewModel.currentReference,
            passageText: viewModel.currentVerseText,
            reflectionText: nil,
            option: .passageOnly
        )
    }

    private func sharePassageAndReflection(_ reflection: String) {
        ShareManager.shared.shareGuidedStudy(
            reference: viewModel.currentReference,
            passageText: viewModel.currentVerseText,
            reflectionText: reflection,
            option: .passageWithReflection
        )
    }

    private func shareReflectionOnly(_ reflection: String) {
        ShareManager.shared.shareGuidedStudy(
            reference: viewModel.currentReference,
            passageText: viewModel.currentVerseText,
            reflectionText: reflection,
            option: .reflectionOnly
        )
    }

    private var generalModeAttachmentBar: some View {
        HStack {
            Spacer()
            Button {
                showPassagePicker = true
            } label: {
                Text("Choose a passage")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(.separator), lineWidth: 1)
                    )
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
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
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.currentReference)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(SeekTheme.textPrimary)

                if !viewModel.currentVerseText.isEmpty {
                    Text(viewModel.currentVerseText)
                        .font(.custom("Georgia", size: 14))
                        .foregroundColor(SeekTheme.textPrimary.opacity(0.85))
                        .lineLimit(2)
                        .lineSpacing(4)
                        .padding(.top, 2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                showReader = true
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Open passage in reader")
            .accessibilityAddTraits(.isButton)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Button {
                    showReader = true
                } label: {
                    HStack(spacing: 4) {
                        let chapterLabel = ScriptureTerminology.chapterLabel(for: viewModel.currentPassageSelection.scriptureId)
                        Image(systemName: "book")
                            .font(.system(size: 12, weight: .medium))
                        Text(viewModel.currentScope == .chapter ? "Read Entire \(chapterLabel)" : "Read in Reader")
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(SeekTheme.maroonAccent)
                    .padding(.top, 2)
                }
                .buttonStyle(.plain)

                Button {
                    showPassagePicker = true
                } label: {
                    Text("Change Passage")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(SeekTheme.maroonAccent)
                }
                .buttonStyle(.plain)
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
            ForEach(Array(viewModel.suggestedPrompts.prefix(3)), id: \.self) { prompt in
                Button {
                    Task { await viewModel.sendMessage(prompt) }
                } label: {
                    Text(prompt)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color(.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color(.separator), lineWidth: 1)
                        )
                        .cornerRadius(20)
                }
                .disabled(viewModel.isTyping || viewModel.isSwitchingPassage || viewModel.isHydratingResume)
            }

            if viewModel.suggestedPrompts.count > 3 {
                Button {
                    showAllPrompts = true
                } label: {
                    Text("More prompts")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(SeekTheme.textSecondary)
                        .padding(.top, 2)
                }
                .disabled(viewModel.isTyping || viewModel.isSwitchingPassage || viewModel.isHydratingResume)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Input Area

    private var inputArea: some View {
        Group {
            if !viewModel.hasUsedFreeResponse {
                HStack(spacing: 12) {
                    TextField("Ask a question...", text: $inputText, axis: .vertical)
                        .font(.system(size: 15))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(SeekTheme.cardBackground)
                        .cornerRadius(24)
                        .focused($isInputFocused)
                        .lineLimit(1...4)
                        .disabled(viewModel.isTyping || viewModel.isSwitchingPassage || viewModel.isHydratingResume)

                    Button {
                        let outgoing = inputText
                        inputText = ""
                        Task { await viewModel.sendMessage(outgoing) }
                    } label: {
                        Group {
                            if viewModel.isTyping {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: SeekTheme.textSecondary))
                            } else {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(inputText.isEmpty ? SeekTheme.textSecondary : SeekTheme.maroonAccent)
                            }
                        }
                    }
                    .disabled(
                        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        viewModel.isTyping ||
                        viewModel.isSwitchingPassage ||
                        viewModel.isHydratingResume
                    )
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
                        appState.presentPaywall(.guidedStudyLimit, onUnlock: { [viewModel] in
                            viewModel.completePremiumUnlock()
                        })
                    } label: {
                        Text("Unlock Unlimited Guided Study")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(SeekTheme.onAccentText)
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
                        .foregroundColor(SeekTheme.onAccentText)
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
                            .foregroundColor(SeekTheme.onAccentText)
                        Text("Insight saved")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(SeekTheme.onAccentText)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(SeekTheme.maroonAccent)
                    .cornerRadius(20)
                    .shadow(color: SeekTheme.overlayShadow, radius: 8, y: 4)
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

private struct MorePromptsSheet: View {
    let prompts: [String]
    let isLocked: Bool
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(prompts, id: \.self) { prompt in
                Button {
                    onSelect(prompt)
                    dismiss()
                } label: {
                    Text(prompt)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(SeekTheme.textPrimary)
                }
                .disabled(isLocked)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Prompt Ideas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(SeekTheme.maroonAccent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Save Confirmation Banner

private struct SaveConfirmationBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(SeekTheme.onAccentText)
            Text("Session saved to My Journey")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(SeekTheme.onAccentText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(SeekTheme.maroonAccent)
        .cornerRadius(20)
        .shadow(color: SeekTheme.overlayShadow, radius: 8, y: 4)
        .padding(.top, 60)
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: DisplayChatMessage

    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 60) }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                messageContent
                    .foregroundColor(message.isUser ? SeekTheme.onAccentText : SeekTheme.textPrimary)
                    .tint(SeekTheme.maroonAccent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(message.isUser ? SeekTheme.maroonAccent : SeekTheme.cardBackground)
                    .cornerRadius(20)
                    .cornerRadius(message.isUser ? 20 : 20, corners: message.isUser ? [.topLeft, .topRight, .bottomLeft] : [.topLeft, .topRight, .bottomRight])
            }

            if !message.isUser { Spacer(minLength: 60) }
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        if message.isUser {
            Text(message.content)
                .font(.system(size: 15))
                .lineSpacing(4)
        } else if let markdown = markdownAttributedContent {
            Text(markdown)
                .font(.system(size: 15))
                .lineSpacing(3)
                .multilineTextAlignment(.leading)
        } else {
            Text(message.content)
                .font(.system(size: 15))
                .lineSpacing(3)
        }
    }

    private var markdownAttributedContent: AttributedString? {
        do {
            return try AttributedString(
                markdown: message.content,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .full,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            )
        } catch {
            return nil
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

private struct GuidedStudyUnavailableInlineView: View {
    let onRetry: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("Guided Study is unavailable right now.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(SeekTheme.textPrimary)

                Text("Please try again.")
                    .font(.system(size: 13))
                    .foregroundColor(SeekTheme.textSecondary)

                Button {
                    onRetry()
                } label: {
                    Text("Try Again")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(.separator), lineWidth: 1)
                        )
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(SeekTheme.cardBackground)
            .cornerRadius(14)

            Spacer(minLength: 60)
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
    PaywallView(streakDays: 8) { }
}

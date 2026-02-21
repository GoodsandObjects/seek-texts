import Foundation
import Combine

enum StudyContext: Codable, Equatable {
    case passage(scriptureRef: ScriptureRef)
    case general

    private enum CodingKeys: String, CodingKey {
        case sessionContext
        case type
        case scriptureRef
    }

    private enum ContextType: String, Codable {
        case passage
        case general
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(ContextType.self, forKey: .sessionContext)
            ?? container.decode(ContextType.self, forKey: .type)
        switch type {
        case .passage:
            let ref = try container.decode(ScriptureRef.self, forKey: .scriptureRef)
            self = .passage(scriptureRef: ref)
        case .general:
            self = .general
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .passage(let scriptureRef):
            try container.encode(ContextType.passage, forKey: .sessionContext)
            try container.encode(ContextType.passage, forKey: .type)
            try container.encode(scriptureRef, forKey: .scriptureRef)
        case .general:
            try container.encode(ContextType.general, forKey: .sessionContext)
            try container.encode(ContextType.general, forKey: .type)
        }
    }

    var scriptureRef: ScriptureRef? {
        guard case .passage(let ref) = self else { return nil }
        return ref
    }
}

struct StudyConversation: Identifiable, Codable, Equatable {
    let id: UUID
    var context: StudyContext
    var scriptureId: String
    var bookId: String
    var chapter: Int
    var verseStart: Int?
    var verseEnd: Int?
    var title: String
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        context: StudyContext,
        scriptureId: String,
        bookId: String,
        chapter: Int,
        verseStart: Int?,
        verseEnd: Int?,
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.context = context
        self.scriptureId = scriptureId
        self.bookId = bookId
        self.chapter = chapter
        self.verseStart = verseStart
        self.verseEnd = verseEnd
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case context
        case scriptureId
        case bookId
        case chapter
        case verseStart
        case verseEnd
        case title
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        scriptureId = try container.decode(String.self, forKey: .scriptureId)
        bookId = try container.decode(String.self, forKey: .bookId)
        chapter = try container.decode(Int.self, forKey: .chapter)
        verseStart = try container.decodeIfPresent(Int.self, forKey: .verseStart)
        verseEnd = try container.decodeIfPresent(Int.self, forKey: .verseEnd)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)

        if let decodedContext = try container.decodeIfPresent(StudyContext.self, forKey: .context) {
            context = decodedContext
        } else {
            if scriptureId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                bookId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                chapter <= 0 {
                context = .general
            } else {
                let fallbackDisplay: String
                if let start = verseStart, let end = verseEnd {
                    fallbackDisplay = start == end ? "\(bookId) \(chapter):\(start)" : "\(bookId) \(chapter):\(start)-\(end)"
                } else {
                    fallbackDisplay = "\(bookId) \(chapter)"
                }

                context = .passage(scriptureRef: ScriptureRef(
                    scriptureId: scriptureId,
                    bookId: bookId,
                    chapter: chapter,
                    verseStart: verseStart,
                    verseEnd: verseEnd,
                    display: fallbackDisplay
                ))
            }
        }
    }
}

struct StudyMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let conversationId: UUID
    let role: String // "user" | "assistant"
    let content: String
    let timestamp: Date

    init(
        id: UUID = UUID(),
        conversationId: UUID,
        role: String,
        content: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.conversationId = conversationId
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

struct StudyPassageRef: Equatable {
    let scriptureId: String
    let bookId: String
    let chapter: Int
    let verseStart: Int?
    let verseEnd: Int?
    let fallbackTitle: String
}

@MainActor
final class StudyStore: ObservableObject {
    static let shared = StudyStore()

    @Published private(set) var conversations: [StudyConversation] = []

    private let fileManager = FileManager.default

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
    }

    private var conversationsFileURL: URL {
        documentsDirectory.appendingPathComponent("StudyConversations.json")
    }

    private var messagesDirectoryURL: URL {
        documentsDirectory.appendingPathComponent("StudyMessages", isDirectory: true)
    }

    private init() {
        ensureDirectories()
        _ = loadAllConversations()
    }

    func createConversation(_ passage: StudyPassageRef) -> StudyConversation {
        let scriptureRef = ScriptureRef(
            scriptureId: passage.scriptureId,
            bookId: passage.bookId,
            chapter: passage.chapter,
            verseStart: passage.verseStart,
            verseEnd: passage.verseEnd,
            display: passage.fallbackTitle
        )
        let conversation = StudyConversation(
            context: .passage(scriptureRef: scriptureRef),
            scriptureId: passage.scriptureId,
            bookId: passage.bookId,
            chapter: passage.chapter,
            verseStart: passage.verseStart,
            verseEnd: passage.verseEnd,
            title: passage.fallbackTitle
        )

        conversations.append(conversation)
        persistConversations()
        return conversation
    }

    func createGeneralConversation(title: String = "General Conversation") -> StudyConversation {
        let conversation = StudyConversation(
            context: .general,
            scriptureId: "",
            bookId: "",
            chapter: 0,
            verseStart: nil,
            verseEnd: nil,
            title: title
        )

        conversations.append(conversation)
        persistConversations()
        return conversation
    }

    func fetchConversationForPassage(_ passage: StudyPassageRef) -> StudyConversation? {
        conversations.first { convo in
            guard case .passage(let ref) = convo.context else { return false }
            return ref.scriptureId == passage.scriptureId &&
            ref.bookId == passage.bookId &&
            ref.chapter == passage.chapter &&
            ref.verseStart == passage.verseStart &&
            ref.verseEnd == passage.verseEnd
        }
    }

    @discardableResult
    func loadAllConversations() -> [StudyConversation] {
        ensureDirectories()

        guard fileManager.fileExists(atPath: conversationsFileURL.path) else {
            conversations = []
            return []
        }

        do {
            let data = try Data(contentsOf: conversationsFileURL)
            let loaded = try JSONDecoder().decode([StudyConversation].self, from: data)
            conversations = loaded.sorted { $0.updatedAt > $1.updatedAt }
            return conversations
        } catch {
            #if DEBUG
            print("[StudyStore] Failed to load conversations: \(error)")
            #endif
            conversations = []
            return []
        }
    }

    func loadMessages(conversationId: UUID) -> [StudyMessage] {
        let fileURL = messagesFileURL(for: conversationId)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let messages = try JSONDecoder().decode([StudyMessage].self, from: data)
            return messages.sorted { $0.timestamp < $1.timestamp }
        } catch {
            #if DEBUG
            print("[StudyStore] Failed to load messages for \(conversationId): \(error)")
            #endif
            return []
        }
    }

    func appendMessage(conversationId: UUID, message: StudyMessage) {
        var messages = loadMessages(conversationId: conversationId)
        messages.append(message)
        persistMessages(messages, conversationId: conversationId)
        updateConversationTimestamp(conversationId: conversationId)
    }

    func updateConversationTimestamp(conversationId: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }

        conversations[index].updatedAt = Date()
        let updated = conversations[index]
        conversations.remove(at: index)
        conversations.insert(updated, at: 0)
        persistConversations()
    }

    func updateConversationTitle(conversationId: UUID, firstUserMessage: String, fallbackTitle: String) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }

        let trimmed = firstUserMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = String(trimmed.prefix(40))
        let title = preview.isEmpty ? fallbackTitle : "\(preview)\(trimmed.count > 40 ? "..." : "")"

        conversations[index].title = title
        conversations[index].updatedAt = Date()

        let updated = conversations[index]
        conversations.remove(at: index)
        conversations.insert(updated, at: 0)
        persistConversations()
    }

    func updateConversationPassage(
        conversationId: UUID,
        scriptureId: String,
        bookId: String,
        chapter: Int,
        verseStart: Int?,
        verseEnd: Int?,
        fallbackTitle: String
    ) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }

        conversations[index].scriptureId = scriptureId
        conversations[index].bookId = bookId
        conversations[index].chapter = chapter
        conversations[index].verseStart = verseStart
        conversations[index].verseEnd = verseEnd
        conversations[index].context = .passage(scriptureRef: ScriptureRef(
            scriptureId: scriptureId,
            bookId: bookId,
            chapter: chapter,
            verseStart: verseStart,
            verseEnd: verseEnd,
            display: fallbackTitle
        ))
        conversations[index].title = fallbackTitle
        conversations[index].updatedAt = Date()

        let updated = conversations[index]
        conversations.remove(at: index)
        conversations.insert(updated, at: 0)
        persistConversations()
    }

    func updateConversationContext(
        conversationId: UUID,
        context: StudyContext,
        fallbackTitle: String
    ) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }

        conversations[index].context = context
        switch context {
        case .general:
            conversations[index].scriptureId = ""
            conversations[index].bookId = ""
            conversations[index].chapter = 0
            conversations[index].verseStart = nil
            conversations[index].verseEnd = nil
        case .passage(let ref):
            conversations[index].scriptureId = ref.scriptureId
            conversations[index].bookId = ref.bookId
            conversations[index].chapter = ref.chapter
            conversations[index].verseStart = ref.verseStart
            conversations[index].verseEnd = ref.verseEnd
        }
        conversations[index].title = fallbackTitle
        conversations[index].updatedAt = Date()

        let updated = conversations[index]
        conversations.remove(at: index)
        conversations.insert(updated, at: 0)
        persistConversations()
    }

    func deleteConversation(conversationId: UUID) {
        conversations.removeAll { $0.id == conversationId }
        persistConversations()

        let fileURL = messagesFileURL(for: conversationId)
        try? fileManager.removeItem(at: fileURL)
    }

    private func messagesFileURL(for conversationId: UUID) -> URL {
        messagesDirectoryURL.appendingPathComponent("\(conversationId.uuidString).json")
    }

    private func persistConversations() {
        do {
            let data = try JSONEncoder().encode(conversations)
            try data.write(to: conversationsFileURL, options: .atomic)
        } catch {
            #if DEBUG
            print("[StudyStore] Failed to persist conversations: \(error)")
            #endif
        }
    }

    private func persistMessages(_ messages: [StudyMessage], conversationId: UUID) {
        do {
            let data = try JSONEncoder().encode(messages)
            try data.write(to: messagesFileURL(for: conversationId), options: .atomic)
        } catch {
            #if DEBUG
            print("[StudyStore] Failed to persist messages for \(conversationId): \(error)")
            #endif
        }
    }

    private func ensureDirectories() {
        if !fileManager.fileExists(atPath: messagesDirectoryURL.path) {
            try? fileManager.createDirectory(at: messagesDirectoryURL, withIntermediateDirectories: true)
        }
    }
}

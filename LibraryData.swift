import Foundation
import Combine

// MARK: - ChapterRef

struct ChapterRef: Identifiable, Hashable {
    let id: String
    let scriptureId: String
    let bookId: String
    let chapterNumber: Int
    let bookName: String

    init(scriptureId: String, bookId: String, chapterNumber: Int, bookName: String) {
        self.id = "\(scriptureId)-\(bookId)-\(chapterNumber)"
        self.scriptureId = scriptureId
        self.bookId = bookId
        self.chapterNumber = chapterNumber
        self.bookName = bookName
    }
}

// MARK: - Library Models

struct Tradition: Identifiable {
    let id: String
    let name: String
    let icon: String
    let texts: [SacredText]
}

struct SacredText: Identifiable {
    let id: String
    let name: String
    let description: String
    let books: [Book]
}

struct Book: Identifiable {
    let id: String
    let name: String
    let chapterCount: Int
}

// MARK: - Scripture Terminology

enum ScriptureTerminology {
    static func chapterLabel(for scriptureId: String) -> String {
        scriptureId == "quran" ? "Surah" : "Chapter"
    }

    static func verseLabel(for scriptureId: String) -> String {
        scriptureId == "quran" ? "Ayah" : "Verse"
    }

    static func verseLabelLowercased(for scriptureId: String, plural: Bool = false) -> String {
        if scriptureId == "quran" {
            return plural ? "ayat" : "ayah"
        }
        return plural ? "verses" : "verse"
    }

    static func chapterBadge(for scriptureId: String, chapterNumber: Int) -> String {
        if scriptureId == "quran" {
            return "Surah \(chapterNumber)"
        }
        return "Ch. \(chapterNumber)"
    }
}

// MARK: - Library Load State

enum LibraryLoadState: Equatable {
    case idle
    case loading
    case loaded
    case error(String)
    case offline
}

// MARK: - LibraryData

/// Async library data manager that loads Top 5 from bundled data.
/// Uses RemoteDataService for strict bundle-first loading.
@MainActor
class LibraryData: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var traditions: [Tradition] = []
    @Published private(set) var loadState: LibraryLoadState = .idle
    @Published private(set) var loadSource: String = ""

    // MARK: - Singleton

    static let shared = LibraryData()

    // MARK: - Private Properties

    private let remoteService = RemoteDataService.shared
    private var hasLoaded = false
    private var hasBootstrapped = false

    // MARK: - Initialization

    private init() {
        // Intentionally side-effect free.
        // Call bootstrapIfNeeded() from app startup.
    }

    // MARK: - Public Methods

    /// Explicit startup bootstrap.
    /// Safe by design: never traps, never force unwraps, never fatalErrors.
    func bootstrapIfNeeded() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        do {
            try loadFromCacheIfAvailableSafely()
        } catch {
            traditions = []
            loadState = .idle
            loadSource = "cache unavailable"
            #if DEBUG
            print("[LibraryData] Cache bootstrap failed safely: \(error.localizedDescription)")
            #endif
        }

        if shouldLoadFromNetworkAfterBootstrap {
            await loadTraditions()
        }
    }

    /// Load traditions asynchronously from bundled index.
    func loadTraditions() async {
        // Avoid duplicate loading
        guard loadState != .loading else { return }

        loadState = .loading

        do {
            let index = try await remoteService.loadIndex()
            traditions = remoteService.convertToTraditions(index)
            SearchManager.shared.rebuildIndex(using: traditions)
            loadState = .loaded
            hasLoaded = true
            logLoadState()
        } catch {
            // Keep already loaded bundled data visible if a refresh path fails.
            if !traditions.isEmpty {
                loadState = .loaded
                loadSource = "bundle (refresh failed)"
                #if DEBUG
                print("[LibraryData] Refresh failed, keeping bundled data: \(error.localizedDescription)")
                #endif
            } else {
                loadState = .error(error.localizedDescription)
                #if DEBUG
                print("[LibraryData] Failed to load: \(error.localizedDescription)")
                #endif
            }
        }
    }

    /// Force refresh from remote (ignoring cache)
    func refresh() async {
        hasLoaded = false
        await loadTraditions()
    }

    /// Retry loading after an error
    func retry() async {
        loadState = .idle
        await loadTraditions()
    }

    // MARK: - Private Methods

    private func loadFromCacheIfAvailableSafely() throws {
        if let index = remoteService.getCachedIndex() {
            traditions = remoteService.convertToTraditions(index)
            SearchManager.shared.rebuildIndex(using: traditions)
            loadState = .loaded
            loadSource = "bundle"
            #if DEBUG
            print("[LibraryData] Loaded \(traditions.count) traditions from bundle on startup")
            #endif
        } else {
            traditions = []
            loadState = .idle
            loadSource = "cache miss"
        }
    }

    private var shouldLoadFromNetworkAfterBootstrap: Bool {
        if loadState == .loading { return false }
        if traditions.isEmpty { return true }
        return false
    }

    private func logLoadState() {
        #if DEBUG
        print("[LibraryData] Loaded \(traditions.count) traditions")
        print("[LibraryData] Base URL: \(RemoteConfig.activeBaseURL)")
        print("[LibraryData] Source: \(loadSource.isEmpty ? "remote" : loadSource)")
        #endif
    }

    // MARK: - Legacy Compatibility

    /// Synchronous access to traditions (for backward compatibility)
    /// Returns cached data immediately, or empty array if not loaded yet
    static var allTraditions: [Tradition] {
        return shared.traditions
    }

    /// Check if index is loaded
    static var isIndexLoaded: Bool {
        return shared.loadState == .loaded && !shared.traditions.isEmpty
    }

    /// Trigger async load (fire and forget)
    static func reload() {
        Task { @MainActor in
            await shared.refresh()
        }
    }
}

// MARK: - Convenience Extensions

extension LibraryData {
    /// Get a specific tradition by ID
    func getTradition(by id: String) -> Tradition? {
        traditions.first { $0.id == id }
    }

    /// Get a specific scripture by ID
    func getScripture(by id: String) -> SacredText? {
        for tradition in traditions {
            if let scripture = tradition.texts.first(where: { $0.id == id }) {
                return scripture
            }
        }
        return nil
    }

    /// Get a specific book by scripture and book ID
    func getBook(scriptureId: String, bookId: String) -> Book? {
        guard let scripture = getScripture(by: scriptureId) else { return nil }
        return scripture.books.first { $0.id == bookId }
    }

    /// Search traditions by name
    func searchTraditions(query: String) -> [Tradition] {
        guard !query.isEmpty else { return traditions }
        let lowercasedQuery = query.lowercased()
        return traditions.filter { tradition in
            tradition.name.lowercased().contains(lowercasedQuery) ||
            tradition.texts.contains { $0.name.lowercased().contains(lowercasedQuery) }
        }
    }
}

//
//  VerseLoader.swift
//  Seek
//
//  Data loader for scripture JSON files from app bundle.
//  Structure: SeekData/<scriptureId>/<bookId>/<chapter>.json
//

import Foundation

// MARK: - LoadedVerse Model

struct LoadedVerse: Identifiable, Equatable {
    let id: String
    let number: Int
    let text: String
}

// MARK: - VerseLoader
// Note: normalizeBookId() is defined in RemoteConfig.swift

/// Singleton loader for scripture data from the app bundle.
/// Uses the SeekData folder structure: SeekData/<scriptureId>/<bookId>/<chapter>.json
final class VerseLoader {

    static let shared = VerseLoader()

    private let dataFolderName = RemoteConfig.bundledDataFolder
    private let alternateSingleChapterScriptures: Set<String> = [
        "quran",
        "bhagavad-gita",
        "dhammapada"
    ]
    private var indexCache: ScriptureIndex?
    private var chapterCache: [String: [LoadedVerse]] = [:]

    private init() {
        loadIndex()
    }

    // MARK: - Index Loading

    private func loadIndex() {
        guard let url = Bundle.main.url(forResource: "index", withExtension: "json", subdirectory: dataFolderName) else {
            #if DEBUG
            print("[VerseLoader] ERROR: index.json not found in subdirectory: \(dataFolderName)")
            #endif
            return
        }

        do {
            let data = try Data(contentsOf: url)
            indexCache = try JSONDecoder().decode(ScriptureIndex.self, from: data)
            #if DEBUG
            print("[VerseLoader] Loaded index with \(indexCache?.scriptures.count ?? 0) scriptures")
            #endif
        } catch {
            #if DEBUG
            print("[VerseLoader] ERROR: Failed to decode index.json: \(error)")
            #endif
        }
    }

    // MARK: - Chapter File Resolution

    /// Attempts to find a chapter file using multiple strategies:
    /// 1. Direct bookId as provided (with .json extension)
    /// 2. Direct bookId without .json extension
    /// 3. Normalized bookId (lowercase, no spaces/punctuation)
    /// 4. Direct file system check as fallback
    private func findChapterFileURL(scriptureId: String, bookId: String, chapter: Int) -> URL? {
        let bundle = Bundle.main
        let chapterString = String(chapter)
        let normalizedBookId = normalizeBookId(bookId)

        // Build list of subdirectories to try
        var subdirectoriesToTry: [String] = []

        // Original bookId
        subdirectoriesToTry.append("\(dataFolderName)/\(scriptureId)/\(bookId)")

        // Normalized bookId (if different)
        if normalizedBookId != bookId {
            subdirectoriesToTry.append("\(dataFolderName)/\(scriptureId)/\(normalizedBookId)")
        }

        // Lowercase original (if different from both)
        let lowercaseBookId = bookId.lowercased()
        if lowercaseBookId != bookId && lowercaseBookId != normalizedBookId {
            subdirectoriesToTry.append("\(dataFolderName)/\(scriptureId)/\(lowercaseBookId)")
        }

        // Try each subdirectory with different file extensions
        for subdirectory in subdirectoriesToTry {
            // Try with .json extension
            if let url = bundle.url(forResource: chapterString, withExtension: "json", subdirectory: subdirectory) {
                return url
            }

            // Try without extension
            if let url = bundle.url(forResource: chapterString, withExtension: nil, subdirectory: subdirectory) {
                return url
            }

            let targetChapter = intendedChapterNumberForBook(
                scriptureId: scriptureId,
                bookId: normalizedBookId,
                requestedChapter: chapter
            )
            if targetChapter != chapter {
                let targetChapterString = String(targetChapter)
                if let url = bundle.url(forResource: targetChapterString, withExtension: "json", subdirectory: subdirectory) {
                    return url
                }
                if let url = bundle.url(forResource: targetChapterString, withExtension: nil, subdirectory: subdirectory) {
                    return url
                }
            }
        }

        // Fallback: Direct file system check
        if let resourceURL = bundle.resourceURL {
            for subdirectory in subdirectoriesToTry {
                let basePath = resourceURL.appendingPathComponent(subdirectory)

                // Try .json extension
                let jsonPath = basePath.appendingPathComponent("\(chapterString).json")
                if FileManager.default.fileExists(atPath: jsonPath.path) {
                    return jsonPath
                }

                // Try without extension
                let noExtPath = basePath.appendingPathComponent(chapterString)
                if FileManager.default.fileExists(atPath: noExtPath.path) {
                    return noExtPath
                }

                if let resolved = resolveAlternateChapterFile(
                    scriptureId: scriptureId,
                    bookId: normalizedBookId,
                    requestedChapter: chapter,
                    basePath: basePath
                ) {
                    return resolved
                }
            }
        }

        #if DEBUG
        print("[VerseLoader] Chapter file NOT FOUND")
        print("[VerseLoader]   Scripture: \(scriptureId), Book: \(bookId) (normalized: \(normalizedBookId)), Chapter: \(chapter)")
        print("[VerseLoader]   Tried subdirectories: \(subdirectoriesToTry)")
        #endif

        return nil
    }

    private func resolveAlternateChapterFile(
        scriptureId: String,
        bookId: String,
        requestedChapter: Int,
        basePath: URL
    ) -> URL? {
        guard alternateSingleChapterScriptures.contains(scriptureId) else {
            return nil
        }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: basePath,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let numericJSONCandidates = contents.filter { url in
            let ext = url.pathExtension.lowercased()
            guard ext == "json" else { return false }
            let stem = url.deletingPathExtension().lastPathComponent
            return Int(stem) != nil
        }

        let targetChapter = intendedChapterNumberForBook(
            scriptureId: scriptureId,
            bookId: bookId,
            requestedChapter: requestedChapter
        )

        if let exact = numericJSONCandidates.first(where: {
            Int($0.deletingPathExtension().lastPathComponent) == targetChapter
        }) {
            return exact
        }

        let numericNoExtCandidates = contents.filter { url in
            url.pathExtension.isEmpty && Int(url.lastPathComponent) != nil
        }
        if let exactNoExt = numericNoExtCandidates.first(where: { Int($0.lastPathComponent) == targetChapter }) {
            return exactNoExt
        }
        return nil
    }

    private func intendedChapterNumberForBook(scriptureId: String, bookId: String, requestedChapter: Int) -> Int {
        if requestedChapter != 1 {
            return requestedChapter
        }

        if scriptureId == "quran" {
            if let quranBook = indexCache?.scriptures[scriptureId]?.books.first(where: { normalizeBookId($0.id) == bookId }),
               let idx = indexCache?.scriptures[scriptureId]?.books.firstIndex(where: { $0.id == quranBook.id }) {
                return idx + 1
            }
        }

        if scriptureId == "bhagavad-gita" {
            if let suffix = bookId.split(separator: "-").last, let n = Int(suffix) {
                return n
            }
        }

        return 1
    }

    // MARK: - Verse Loading

    /// Load verses for a specific chapter.
    func load(scriptureId: String, bookId: String, chapter: Int) -> [LoadedVerse] {
        let normalizedBookId = normalizeBookId(bookId)
        let cacheKey = "\(scriptureId)/\(normalizedBookId)/\(chapter)"

        if let cached = chapterCache[cacheKey] {
            return cached
        }

        guard let url = findChapterFileURL(scriptureId: scriptureId, bookId: bookId, chapter: chapter) else {
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            let chapterData = try JSONDecoder().decode(ChapterJSON.self, from: data)

            let verses = chapterData.verses.map { verse in
                LoadedVerse(
                    id: "\(scriptureId)|\(normalizedBookId)|\(chapter)|\(verse.number)",
                    number: verse.number,
                    text: verse.text
                )
            }

            chapterCache[cacheKey] = verses

            #if DEBUG
            print("[VerseLoader] Loaded \(verses.count) verses for \(scriptureId)/\(bookId)/\(chapter)")
            #endif
            return verses
        } catch {
            #if DEBUG
            print("[VerseLoader] ERROR: Failed to decode chapter at \(url.path): \(error)")
            #endif
            return []
        }
    }

    // MARK: - Chapter Existence Check

    /// Check if a chapter file exists in the bundle.
    func chapterExists(scriptureId: String, bookId: String, chapter: Int) -> Bool {
        return findChapterFileURL(scriptureId: scriptureId, bookId: bookId, chapter: chapter) != nil
    }

    // MARK: - Chapter Count

    /// Get the chapter count for a book from the index.
    func getChapterCount(scriptureId: String, bookId: String) -> Int {
        let normalizedBookId = normalizeBookId(bookId)

        if let index = indexCache,
           let scripture = index.scriptures[scriptureId] {
            // Try exact match first
            if let book = scripture.books.first(where: { $0.id == bookId }) {
                return book.chapterCount
            }
            // Try normalized match
            if let book = scripture.books.first(where: { normalizeBookId($0.id) == normalizedBookId }) {
                return book.chapterCount
            }
        }

        #if DEBUG
        print("[VerseLoader] getChapterCount() - book not found: \(scriptureId)/\(bookId)")
        #endif
        return 0
    }

    // MARK: - Data Availability Checks

    /// Check if a book has any chapter data (at least chapter 1 exists)
    func bookHasData(scriptureId: String, bookId: String) -> Bool {
        return chapterExists(scriptureId: scriptureId, bookId: bookId, chapter: 1)
    }

    /// Check if a scripture has any data (any book has chapter 1)
    func scriptureHasData(scriptureId: String) -> Bool {
        guard let index = indexCache,
              let scripture = index.scriptures[scriptureId] else {
            return false
        }

        for book in scripture.books {
            if bookHasData(scriptureId: scriptureId, bookId: book.id) {
                return true
            }
        }
        return false
    }

    /// Count how many chapters actually exist on disk for a book
    func countAvailableChapters(scriptureId: String, bookId: String) -> Int {
        var count = 0
        let maxToCheck = getChapterCount(scriptureId: scriptureId, bookId: bookId)

        for chapter in 1...max(1, maxToCheck) {
            if chapterExists(scriptureId: scriptureId, bookId: bookId, chapter: chapter) {
                count += 1
            } else {
                // Stop at first missing chapter (assuming sequential)
                break
            }
        }

        return count
    }

    // MARK: - Utility

    func clearCache() {
        chapterCache.removeAll()
    }

    var isLoaded: Bool {
        return indexCache != nil
    }

    func reloadIndex() {
        chapterCache.removeAll()
        loadIndex()
    }
}

// MARK: - Private JSON Models

private struct ChapterJSON: Decodable {
    let scriptureId: String?
    let bookId: String?
    let chapter: Int?
    let verses: [VerseJSON]
}

private struct VerseJSON: Decodable {
    let number: Int
    let text: String
}

private struct ScriptureIndex: Decodable {
    let scriptures: [String: ScriptureEntry]
}

private struct ScriptureEntry: Decodable {
    let id: String
    let name: String
    let description: String?
    let books: [BookEntry]
}

private struct BookEntry: Decodable {
    let id: String
    let name: String
    let chapterCount: Int
}

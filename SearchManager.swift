//
//  SearchManager.swift
//  Seek
//
//  Global search manager for scripture navigation.
//  Parses queries like "Genesis 4", "Al-Faatiha", "Bhagavad Gita 6"
//

import Foundation

// MARK: - Search Result Model

struct SearchResult: Identifiable {
    let id: String
    let bookName: String
    let bookId: String
    let scriptureName: String
    let scriptureId: String
    let traditionName: String
    let traditionIcon: String
    let chapterCount: Int
    let matchedChapter: Int?

    // For navigation
    let tradition: Tradition
    let sacredText: SacredText
    let book: Book
}

// MARK: - Search Manager

class SearchManager {

    static let shared = SearchManager()

    private var searchIndex: [SearchableBook] = []
    private var lastIndexedSignature: String = ""

    private init() {
        // Avoid touching LibraryData.shared during static initialization.
        // Index is built lazily on first explicit rebuild/search.
    }

    // MARK: - Index Building

    private struct SearchableBook {
        let bookName: String
        let bookNameLower: String
        let bookId: String
        let scriptureName: String
        let scriptureId: String
        let traditionName: String
        let traditionIcon: String
        let chapterCount: Int
        let tradition: Tradition
        let sacredText: SacredText
        let book: Book
    }

    private func buildIndex(from traditions: [Tradition]) {
        searchIndex.removeAll()

        for tradition in traditions {
            for text in tradition.texts {
                for book in text.books {
                    let entry = SearchableBook(
                        bookName: book.name,
                        bookNameLower: book.name.lowercased(),
                        bookId: book.id,
                        scriptureName: text.name,
                        scriptureId: text.id,
                        traditionName: tradition.name,
                        traditionIcon: tradition.icon,
                        chapterCount: book.chapterCount,
                        tradition: tradition,
                        sacredText: text,
                        book: book
                    )
                    searchIndex.append(entry)
                }
            }
        }
        print("[SearchManager] Indexed \(searchIndex.count) books")
    }

    func rebuildIndex() {
        rebuildIndex(using: LibraryData.allTraditions)
    }

    func rebuildIndex(using traditions: [Tradition]) {
        lastIndexedSignature = makeSignature(for: traditions)
        buildIndex(from: traditions)
    }

    private func makeSignature(for traditions: [Tradition]) -> String {
        traditions
            .map { tradition in
                let scriptureSummary = tradition.texts
                    .map { "\($0.id):\($0.books.count)" }
                    .sorted()
                    .joined(separator: ",")
                return "\(tradition.id)|\(scriptureSummary)"
            }
            .sorted()
            .joined(separator: ";")
    }

    private func ensureIndexIsFresh() {
        let traditions = LibraryData.allTraditions
        let signature = makeSignature(for: traditions)
        if signature != lastIndexedSignature {
            rebuildIndex(using: traditions)
        }
    }

    // MARK: - Query Parsing

    struct ParsedQuery {
        let bookQuery: String
        let chapterNumber: Int?
    }

    /// Parses user input to extract book name and optional chapter number
    /// Examples:
    ///   "Genesis 4" -> bookQuery: "Genesis", chapterNumber: 4
    ///   "Al-Faatiha" -> bookQuery: "Al-Faatiha", chapterNumber: nil
    ///   "1 Corinthians 13" -> bookQuery: "1 Corinthians", chapterNumber: 13
    ///   "Bhagavad Gita Chapter 6" -> bookQuery: "Bhagavad Gita", chapterNumber: 6
    func parseQuery(_ input: String) -> ParsedQuery {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return ParsedQuery(bookQuery: "", chapterNumber: nil)
        }

        // Remove common words like "chapter"
        let cleaned = trimmed
            .replacingOccurrences(of: " chapter ", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: " ch ", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: " ch. ", with: " ", options: .caseInsensitive)

        // Check if the last component is a number (chapter)
        let components = cleaned.split(separator: " ")

        if components.count >= 2,
           let lastComponent = components.last,
           let chapterNum = Int(lastComponent) {
            // Last part is a number - treat as chapter
            let bookPart = components.dropLast().joined(separator: " ")
            return ParsedQuery(bookQuery: bookPart, chapterNumber: chapterNum)
        }

        // Check for patterns like "Genesis4" (no space)
        let pattern = "^(.+?)(\\d+)$"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)) {
            if let bookRange = Range(match.range(at: 1), in: cleaned),
               let numRange = Range(match.range(at: 2), in: cleaned) {
                let bookPart = String(cleaned[bookRange]).trimmingCharacters(in: .whitespaces)
                if let chapterNum = Int(cleaned[numRange]) {
                    // Make sure book part isn't just a number (like "1" from "1 Corinthians")
                    if !bookPart.isEmpty && Int(bookPart) == nil {
                        return ParsedQuery(bookQuery: bookPart, chapterNumber: chapterNum)
                    }
                }
            }
        }

        // No chapter number found
        return ParsedQuery(bookQuery: cleaned, chapterNumber: nil)
    }

    // MARK: - Search

    func search(_ query: String, maxResults: Int = 6) -> [SearchResult] {
        ensureIndexIsFresh()

        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let parsed = parseQuery(query)
        let searchTerm = parsed.bookQuery.lowercased()

        guard !searchTerm.isEmpty else {
            return []
        }

        // Score and rank matches
        var scoredResults: [(entry: SearchableBook, score: Int, matchedChapter: Int?)] = []

        for entry in searchIndex {
            var score = 0

            // Exact match (highest priority)
            if entry.bookNameLower == searchTerm {
                score = 100
            }
            // Starts with query
            else if entry.bookNameLower.hasPrefix(searchTerm) {
                score = 80
            }
            // Contains query as word
            else if entry.bookNameLower.contains(" \(searchTerm)") || entry.bookNameLower.contains("\(searchTerm) ") {
                score = 60
            }
            // Contains query anywhere
            else if entry.bookNameLower.contains(searchTerm) {
                score = 40
            }
            // Scripture name matches
            else if entry.scriptureName.lowercased().contains(searchTerm) {
                score = 20
            }

            if score > 0 {
                // Validate chapter if specified
                var matchedChapter: Int? = nil
                if let requestedChapter = parsed.chapterNumber {
                    if requestedChapter >= 1 && requestedChapter <= entry.chapterCount {
                        matchedChapter = requestedChapter
                        score += 10 // Bonus for valid chapter
                    } else if entry.scriptureId == "bhagavad-gita",
                              let gitaChapter = Int(entry.bookId.replacingOccurrences(of: "chapter-", with: "")),
                              gitaChapter == requestedChapter {
                        matchedChapter = requestedChapter
                        score += 30 // Prefer exact Bhagavad Gita chapter mapping
                    }
                }

                scoredResults.append((entry, score, matchedChapter))
            }
        }

        // Sort by score descending, then alphabetically
        scoredResults.sort { a, b in
            if a.score != b.score {
                return a.score > b.score
            }
            return a.entry.bookName < b.entry.bookName
        }

        // Convert to SearchResult and limit
        let results = scoredResults.prefix(maxResults).map { item -> SearchResult in
            SearchResult(
                id: "\(item.entry.scriptureId)-\(item.entry.bookId)-\(item.matchedChapter ?? 0)",
                bookName: item.entry.bookName,
                bookId: item.entry.bookId,
                scriptureName: item.entry.scriptureName,
                scriptureId: item.entry.scriptureId,
                traditionName: item.entry.traditionName,
                traditionIcon: item.entry.traditionIcon,
                chapterCount: item.entry.chapterCount,
                matchedChapter: item.matchedChapter,
                tradition: item.entry.tradition,
                sacredText: item.entry.sacredText,
                book: item.entry.book
            )
        }

        return Array(results)
    }
}

import Foundation

struct GuidedSearchResult: Identifiable {
    let id: String
    let reference: String
    let preview: String
    let religionLabel: String
    let selection: GuidedPassageSelectionRef
    let scope: GuidedSessionScope
    let range: ClosedRange<Int>?
    let score: Int
}

actor GuidedSearchManager {
    static let shared = GuidedSearchManager()

    private struct SearchEntry {
        let traditionId: String
        let traditionName: String
        let scriptureId: String
        let scriptureName: String
        let bookId: String
        let bookName: String
        let chapterNumber: Int
        let reference: String
        let normalizedBookName: String
        let searchableText: String
        let preview: String
    }

    private struct IndexedBook {
        let traditionId: String
        let traditionName: String
        let scriptureId: String
        let scriptureName: String
        let bookId: String
        let bookName: String
        let normalizedBookName: String
        let chapterCount: Int
        let inferredUnit: Int?
    }

    private var indexedSignature = ""
    private var indexedBooks: [IndexedBook] = []
    private var entries: [SearchEntry] = []

    private let indexedTraditionIDs = Set(["christianity", "judaism", "islam", "hinduism", "buddhism"])
    private let singleUnitScriptures = Set(["quran", "bhagavad-gita", "heart-sutra", "upanishads"])

    func warmIndex(with traditions: [Tradition]) {
        let topTraditions = traditions.filter { indexedTraditionIDs.contains($0.id) }
        let signature = makeSignature(for: topTraditions)
        guard signature != indexedSignature else { return }

        var nextBooks: [IndexedBook] = []
        var nextEntries: [SearchEntry] = []
        nextBooks.reserveCapacity(700)

        for tradition in topTraditions {
            for scripture in tradition.texts {
                for book in scripture.books {
                    let indexedBook = IndexedBook(
                        traditionId: tradition.id,
                        traditionName: tradition.name,
                        scriptureId: scripture.id,
                        scriptureName: scripture.name,
                        bookId: book.id,
                        bookName: book.name,
                        normalizedBookName: normalizeName(book.name),
                        chapterCount: max(1, book.chapterCount),
                        inferredUnit: inferBookUnit(from: book.id)
                    )
                    nextBooks.append(indexedBook)

                    for chapter in 1...max(1, book.chapterCount) {
                        let verses = VerseLoader.shared.load(
                            scriptureId: scripture.id,
                            bookId: book.id,
                            chapter: chapter
                        )
                        guard !verses.isEmpty else { continue }

                        let fullText = verses.map(\.text).joined(separator: " ")
                        let reference = buildReference(
                            scriptureId: scripture.id,
                            bookName: book.name,
                            chapter: chapter
                        )
                        nextEntries.append(
                            SearchEntry(
                                traditionId: tradition.id,
                                traditionName: tradition.name,
                                scriptureId: scripture.id,
                                scriptureName: scripture.name,
                                bookId: book.id,
                                bookName: book.name,
                                chapterNumber: chapter,
                                reference: reference,
                                normalizedBookName: normalizeName(book.name),
                                searchableText: fullText.lowercased(),
                                preview: String(fullText.prefix(240))
                            )
                        )
                    }
                }
            }
        }

        indexedSignature = signature
        indexedBooks = nextBooks
        entries = nextEntries
    }

    func search(query rawQuery: String, traditions: [Tradition], maxResults: Int = 16) -> [GuidedSearchResult] {
        warmIndex(with: traditions)

        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        var results: [GuidedSearchResult] = []
        results.reserveCapacity(maxResults)

        let direct = directReferenceMatches(query: query, maxResults: maxResults)
        results.append(contentsOf: direct)

        if results.count < maxResults {
            let keyword = keywordMatches(query: query, excluding: Set(results.map(\.id)), maxResults: maxResults - results.count)
            results.append(contentsOf: keyword)
        }

        return results.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            return a.reference < b.reference
        }
    }

    private func directReferenceMatches(query: String, maxResults: Int) -> [GuidedSearchResult] {
        let normalized = normalizeName(query)
        var results: [GuidedSearchResult] = []

        if let parsed = parseReference(query), !parsed.bookTerm.isEmpty {
            let bookTerm = normalizeName(parsed.bookTerm)
            let candidates = indexedBooks.filter { $0.normalizedBookName.contains(bookTerm) || bookTerm.contains($0.normalizedBookName) }

            for book in candidates {
                let chosenChapter = resolveChapter(
                    requested: parsed.chapter,
                    book: book
                )
                guard let chosenChapter else { continue }

                let selection = GuidedPassageSelectionRef(
                    traditionId: book.traditionId,
                    traditionName: book.traditionName,
                    scriptureId: book.scriptureId,
                    scriptureName: book.scriptureName,
                    bookId: book.bookId,
                    bookName: book.bookName,
                    chapterNumber: chosenChapter
                )

                let range: ClosedRange<Int>? = parsed.verseStart.map { start in
                    let end = parsed.verseEnd ?? start
                    return min(start, end)...max(start, end)
                }

                let reference = buildReference(
                    scriptureId: book.scriptureId,
                    bookName: book.bookName,
                    chapter: chosenChapter,
                    verseRange: range
                )

                let preview = entryPreview(
                    scriptureId: book.scriptureId,
                    bookId: book.bookId,
                    chapter: chosenChapter,
                    verseRange: range
                )

                let score = parsed.verseStart != nil ? 500 : (parsed.chapter != nil ? 420 : 360)
                results.append(
                    GuidedSearchResult(
                        id: "direct-\(book.scriptureId)-\(book.bookId)-\(chosenChapter)-\(range?.lowerBound ?? 0)-\(range?.upperBound ?? 0)",
                        reference: reference,
                        preview: preview,
                        religionLabel: book.traditionName,
                        selection: selection,
                        scope: range == nil ? .chapter : .range,
                        range: range,
                        score: score
                    )
                )
            }
        }

        if results.isEmpty {
            let bookMatches = indexedBooks
                .filter { $0.normalizedBookName.contains(normalized) || normalized.contains($0.normalizedBookName) }
                .prefix(maxResults)

            for book in bookMatches {
                let chapter = resolveChapter(requested: nil, book: book) ?? 1
                let selection = GuidedPassageSelectionRef(
                    traditionId: book.traditionId,
                    traditionName: book.traditionName,
                    scriptureId: book.scriptureId,
                    scriptureName: book.scriptureName,
                    bookId: book.bookId,
                    bookName: book.bookName,
                    chapterNumber: chapter
                )
                let reference = buildReference(scriptureId: book.scriptureId, bookName: book.bookName, chapter: chapter)
                results.append(
                    GuidedSearchResult(
                        id: "book-\(book.scriptureId)-\(book.bookId)-\(chapter)",
                        reference: reference,
                        preview: entryPreview(scriptureId: book.scriptureId, bookId: book.bookId, chapter: chapter, verseRange: nil),
                        religionLabel: book.traditionName,
                        selection: selection,
                        scope: .chapter,
                        range: nil,
                        score: 300
                    )
                )
            }
        }

        return Array(results.prefix(maxResults))
    }

    private func keywordMatches(query: String, excluding ids: Set<String>, maxResults: Int) -> [GuidedSearchResult] {
        let terms = normalizeName(query)
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !terms.isEmpty else { return [] }

        var scored: [GuidedSearchResult] = []
        scored.reserveCapacity(maxResults)

        for entry in entries {
            var matchedAll = true
            var score = 0

            for term in terms {
                if let range = entry.searchableText.range(of: term) {
                    score += 30
                    if range.lowerBound == entry.searchableText.startIndex {
                        score += 10
                    }
                } else {
                    matchedAll = false
                    break
                }
            }

            guard matchedAll else { continue }

            let selection = GuidedPassageSelectionRef(
                traditionId: entry.traditionId,
                traditionName: entry.traditionName,
                scriptureId: entry.scriptureId,
                scriptureName: entry.scriptureName,
                bookId: entry.bookId,
                bookName: entry.bookName,
                chapterNumber: entry.chapterNumber
            )

            let result = GuidedSearchResult(
                id: "keyword-\(entry.scriptureId)-\(entry.bookId)-\(entry.chapterNumber)",
                reference: entry.reference,
                preview: String(entry.preview.prefix(120)),
                religionLabel: entry.traditionName,
                selection: selection,
                scope: .chapter,
                range: nil,
                score: 100 + score
            )

            if !ids.contains(result.id) {
                scored.append(result)
            }
        }

        return Array(
            scored
                .sorted { a, b in
                    if a.score != b.score { return a.score > b.score }
                    return a.reference < b.reference
                }
                .prefix(maxResults)
        )
    }

    private func resolveChapter(requested: Int?, book: IndexedBook) -> Int? {
        guard let requested else {
            if singleUnitScriptures.contains(book.scriptureId) {
                return 1
            }
            return 1
        }

        if book.chapterCount > 1 {
            return (1...book.chapterCount).contains(requested) ? requested : nil
        }

        if requested == 1 { return 1 }
        if let inferred = book.inferredUnit, inferred == requested { return 1 }
        return nil
    }

    private func parseReference(_ query: String) -> (bookTerm: String, chapter: Int?, verseStart: Int?, verseEnd: Int?)? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let pattern = #"^\s*(.+?)\s+(\d+)(?::(\d+)(?:\s*[-–]\s*(\d+))?)?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        guard let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) else {
            return (bookTerm: trimmed, chapter: nil, verseStart: nil, verseEnd: nil)
        }

        func group(_ idx: Int) -> String? {
            guard let r = Range(match.range(at: idx), in: trimmed) else { return nil }
            return String(trimmed[r])
        }

        let bookTerm = group(1)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? trimmed
        let chapter = group(2).flatMap(Int.init)
        let verseStart = group(3).flatMap(Int.init)
        let verseEnd = group(4).flatMap(Int.init)

        return (bookTerm: bookTerm, chapter: chapter, verseStart: verseStart, verseEnd: verseEnd)
    }

    private func buildReference(
        scriptureId: String,
        bookName: String,
        chapter: Int,
        verseRange: ClosedRange<Int>? = nil
    ) -> String {
        let base: String
        if singleUnitScriptures.contains(scriptureId) && chapter == 1 {
            base = bookName
        } else {
            base = "\(bookName) \(chapter)"
        }

        guard let verseRange else { return base }
        if verseRange.lowerBound == verseRange.upperBound {
            return "\(base):\(verseRange.lowerBound)"
        }
        return "\(base):\(verseRange.lowerBound)-\(verseRange.upperBound)"
    }

    private func entryPreview(scriptureId: String, bookId: String, chapter: Int, verseRange: ClosedRange<Int>?) -> String {
        let verses = VerseLoader.shared.load(scriptureId: scriptureId, bookId: bookId, chapter: chapter)
        guard !verses.isEmpty else { return "" }

        let source: [LoadedVerse]
        if let range = verseRange {
            let filtered = verses.filter { range.contains($0.number) }
            source = filtered.isEmpty ? verses : filtered
        } else {
            source = verses
        }

        let text = source.map(\.text).joined(separator: " ")
        return String(text.prefix(120))
    }

    private func makeSignature(for traditions: [Tradition]) -> String {
        traditions
            .map { tradition in
                let texts = tradition.texts
                    .map { "\($0.id):\($0.books.count)" }
                    .sorted()
                    .joined(separator: ",")
                return "\(tradition.id)|\(texts)"
            }
            .sorted()
            .joined(separator: ";")
    }

    private func normalizeName(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func inferBookUnit(from bookId: String) -> Int? {
        let digits = bookId.split(separator: "-").compactMap { Int($0) }
        if let last = digits.last {
            return last
        }
        return Int(bookId)
    }
}

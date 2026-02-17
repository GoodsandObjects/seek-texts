//
//  RemoteDataService.swift
//  Seek
//
//  Online-first data service for loading scripture metadata and chapter content.
//  Implements CatalogProvider and ChapterProvider protocols with disk caching.
//

import Foundation
import Network
import UIKit

// MARK: - Provider Protocols

/// Protocol for loading scripture catalog (traditions, scriptures, books, chapters metadata)
protocol CatalogProvider {
    func loadIndex() async throws -> RemoteIndex
    func getCachedIndex() -> RemoteIndex?
}

/// Protocol for loading chapter verses
protocol ChapterProvider {
    func loadChapter(scriptureId: String, bookId: String, chapter: Int) async throws -> [LoadedVerse]
    func getCachedChapter(scriptureId: String, bookId: String, chapter: Int) -> [LoadedVerse]?
}

// MARK: - Remote Index Models

struct RemoteIndex: Codable {
    let version: String
    let traditions: [RemoteTradition]
    let scriptures: [String: RemoteScripture]
}

struct RemoteTradition: Codable {
    let id: String
    let name: String
    let icon: String
    let scriptures: [String]
}

struct RemoteScripture: Codable {
    let id: String
    let name: String
    let description: String?
    let books: [RemoteBook]
}

struct RemoteBook: Codable {
    let id: String
    let name: String
    let chapterCount: Int
}

struct RemoteChapter: Codable {
    let scriptureId: String?
    let bookId: String?
    let chapter: Int?
    let reference: String?
    let verses: [RemoteVerse]
}

struct RemoteVerse: Codable {
    let id: String?
    let number: Int
    let text: String
}

// MARK: - Error Types

enum RemoteDataError: Error, LocalizedError {
    case networkError(Error)
    case invalidURL
    case noData
    case decodingError(Error)
    case invalidIndexData(String)
    case invalidChapterData(String)
    case missingBundleResource(String)
    case missingTopFiveLocalData(String)
    case allURLsFailed
    case offline

    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidURL:
            return "Invalid URL"
        case .noData:
            return "No data received"
        case .decodingError(let error):
            return "Failed to decode data: \(error.localizedDescription)"
        case .invalidIndexData(let message):
            return "Invalid index data: \(message)"
        case .invalidChapterData(let message):
            return "Invalid chapter data: \(message)"
        case .missingBundleResource(let path):
            return "Missing bundled data resource: \(path)"
        case .missingTopFiveLocalData(let path):
            return "Top 5 scripture unavailable locally (bundle/cache): \(path)"
        case .allURLsFailed:
            return "All remote URLs failed"
        case .offline:
            return "Device is offline"
        }
    }
}

// MARK: - Remote Data Service

/// Singleton service for online-first scripture data loading
@MainActor
final class RemoteDataService: CatalogProvider, ChapterProvider {

    static let shared = RemoteDataService()
    static let topFiveTraditionIDs = ["christianity", "judaism", "islam", "hinduism", "buddhism"]
    static let topFiveScriptureIDs = ["bible-kjv", "quran", "tanakh-jps", "bhagavad-gita", "dhammapada"]
    static let topFiveScriptureIDSet = Set(topFiveScriptureIDs)
    static let topFiveTraditionIDSet = Set(topFiveTraditionIDs)
    private let alternateSingleChapterScriptures: Set<String> = [
        "quran",
        "bhagavad-gita",
        "dhammapada"
    ]

    struct ScriptureStatus: Identifiable {
        let id: String
        let name: String
        let totalBooks: Int
        let totalChapters: Int
        let sampleChapterSuccess: Bool
        let sampleChapterReference: String
    }

    struct DataStatusReport {
        let hasBundleIndex: Bool
        let hasCacheIndex: Bool
        let hasRemoteIndex: Bool
        let sourceSummary: String
        let scriptureStatuses: [ScriptureStatus]
    }

    struct PrefetchResult {
        let attemptedChapters: Int
        let succeededChapters: Int
        let failedChapters: Int
    }

    // MARK: - Properties

    private let session: URLSession
    private let fileManager = FileManager.default
    private let datasetProvider = RemoteDatasetProvider.shared

    // In-memory caches
    private var indexCache: RemoteIndex?
    private var chapterCache: [String: [LoadedVerse]] = [:]

    // Cache directories
    private lazy var cacheDirectory: URL = {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let cacheDir = appSupport.appendingPathComponent("SeekCache", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        return cacheDir
    }()

    private var indexCacheFile: URL {
        cacheDirectory.appendingPathComponent("index.json")
    }

    private var chaptersCacheDir: URL {
        let dir = cacheDirectory.appendingPathComponent("chapters", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // Logging state
    private var hasLoggedStartup = false
    private var hasLoggedSeekDataCheck = false
    private let prefetchTimestampKey = "seek_top5_prefetch_last_run"

    // MARK: - Initialization

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = RemoteConfig.requestTimeout
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    // MARK: - CatalogProvider

    /// Load the scripture index from bundle first.
    /// Remote may exist for future expansion, but Top 5 must never require it.
    func loadIndex() async throws -> RemoteIndex {
        if let cached = indexCache {
            logOnce("[RemoteDataService] Index loaded from memory cache")
            return cached
        }

        guard let bundled = loadIndexFromBundle() else {
            throw RemoteDataError.missingBundleResource("\(RemoteConfig.bundledDataFolder)/index.json")
        }

        let index = normalizeKnownTraditionIcons(in: filterToTopFive(bundled))
        indexCache = index
        try? saveIndexToCache(index)
        return index
    }

    func getCachedIndex() -> RemoteIndex? {
        if let cached = indexCache {
            return cached
        }
        if let bundled = loadIndexFromBundle() {
            let index = normalizeKnownTraditionIcons(in: filterToTopFive(bundled))
            indexCache = index
            return index
        }
        return nil
    }

    // MARK: - ChapterProvider

    /// Load chapter verses. Top 5 are bundle-first and never require remote fetches.
    func loadChapter(scriptureId: String, bookId: String, chapter: Int) async throws -> [LoadedVerse] {
        let normalizedBookId = normalizeBookId(bookId)
        let cacheKey = "\(scriptureId)/\(normalizedBookId)/\(chapter)"

        if let cached = chapterCache[cacheKey] {
            return cached
        }

        if isTopFiveScripture(scriptureId) {
            return try await loadTopFiveChapter(scriptureId: scriptureId, bookId: bookId, chapter: chapter)
        }

        var lastError: Error?
        var sawMalformedRemoteData = false

        for baseURL in RemoteConfig.baseURLs {
            do {
                let verses = try await fetchChapter(
                    scriptureId: scriptureId,
                    bookId: normalizedBookId,
                    chapter: chapter,
                    from: baseURL
                )
                chapterCache[cacheKey] = verses
                try? saveChapterToCache(verses, scriptureId: scriptureId, bookId: normalizedBookId, chapter: chapter)
                log("[RemoteDataService] Chapter \(cacheKey) loaded from network")
                return verses
            } catch {
                lastError = error
                if isMalformedRemoteDataError(error) {
                    sawMalformedRemoteData = true
                }
                log("[RemoteDataService] Failed to load chapter from \(baseURL): \(error.localizedDescription)")
                continue
            }
        }

        // Only use local fallbacks when remote failures are connectivity/offline related.
        // Data/schema errors should surface rather than being silently masked.
        if !sawMalformedRemoteData {
            if let cached = loadChapterFromCache(scriptureId: scriptureId, bookId: normalizedBookId, chapter: chapter) {
                chapterCache[cacheKey] = cached
                log("[RemoteDataService] Chapter \(cacheKey) loaded from disk cache")
                return cached
            }

            if let bundled = loadChapterFromBundle(scriptureId: scriptureId, bookId: bookId, chapter: chapter) {
                chapterCache[cacheKey] = bundled
                log("[RemoteDataService] Chapter \(cacheKey) loaded from bundle")
                return bundled
            }
        }

        if let lastError {
            throw lastError
        }
        throw RemoteDataError.noData
    }

    func getCachedChapter(scriptureId: String, bookId: String, chapter: Int) -> [LoadedVerse]? {
        let normalizedBookId = normalizeBookId(bookId)
        let cacheKey = "\(scriptureId)/\(normalizedBookId)/\(chapter)"

        if let cached = chapterCache[cacheKey] {
            return cached
        }
        if isTopFiveScripture(scriptureId) {
            if let bundled = loadChapterFromBundle(scriptureId: scriptureId, bookId: bookId, chapter: chapter) {
                chapterCache[cacheKey] = bundled
                return bundled
            }
            if let cached = loadChapterFromCache(scriptureId: scriptureId, bookId: normalizedBookId, chapter: chapter) {
                chapterCache[cacheKey] = cached
                return cached
            }
            return nil
        }

        if let cached = loadChapterFromCache(scriptureId: scriptureId, bookId: normalizedBookId, chapter: chapter) {
            chapterCache[cacheKey] = cached
            return cached
        }
        return loadChapterFromBundle(scriptureId: scriptureId, bookId: bookId, chapter: chapter)
    }

    // MARK: - Network Fetching

    private func fetchIndex(from baseURL: String) async throws -> RemoteIndex {
        guard let url = URL(string: "\(baseURL)/\(RemoteConfig.indexPath)") else {
            throw RemoteDataError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw RemoteDataError.networkError(NSError(domain: "HTTP", code: (response as? HTTPURLResponse)?.statusCode ?? -1))
        }

        do {
            let index = try JSONDecoder().decode(RemoteIndex.self, from: data)
            try validateIndex(index)
            return index
        } catch let error as RemoteDataError {
            throw error
        } catch {
            throw RemoteDataError.decodingError(error)
        }
    }

    private func fetchChapter(scriptureId: String, bookId: String, chapter: Int, from baseURL: String) async throws -> [LoadedVerse] {
        let path = RemoteConfig.chapterPathTemplate
            .replacingOccurrences(of: "{scriptureId}", with: scriptureId)
            .replacingOccurrences(of: "{bookId}", with: bookId)
            .replacingOccurrences(of: "{chapter}", with: String(chapter))

        guard let url = URL(string: "\(baseURL)/\(path)") else {
            throw RemoteDataError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw RemoteDataError.networkError(NSError(domain: "HTTP", code: (response as? HTTPURLResponse)?.statusCode ?? -1))
        }

        do {
            let chapterData = try JSONDecoder().decode(RemoteChapter.self, from: data)
            guard !chapterData.verses.isEmpty else {
                throw RemoteDataError.invalidChapterData("Verse array is empty for \(scriptureId)/\(bookId)/\(chapter)")
            }
            let loadedVerses = chapterData.verses.map { verse in
                LoadedVerse(id: "", number: verse.number, text: verse.text)
            }
            return try normalizeVerses(
                loadedVerses,
                scriptureId: scriptureId,
                bookId: bookId,
                chapter: chapter
            )
        } catch let error as RemoteDataError {
            throw error
        } catch {
            throw RemoteDataError.decodingError(error)
        }
    }

    // MARK: - Disk Cache Operations

    private func saveIndexToCache(_ index: RemoteIndex) throws {
        let data = try JSONEncoder().encode(index)
        try data.write(to: indexCacheFile)
    }

    private func loadIndexFromCache() -> RemoteIndex? {
        guard fileManager.fileExists(atPath: indexCacheFile.path) else { return nil }

        do {
            let data = try Data(contentsOf: indexCacheFile)
            let index = try JSONDecoder().decode(RemoteIndex.self, from: data)
            try validateIndex(index)
            return index
        } catch {
            log("[RemoteDataService] Failed to load index from cache: \(error)")
            return nil
        }
    }

    private func saveChapterToCache(_ verses: [LoadedVerse], scriptureId: String, bookId: String, chapter: Int) throws {
        let scriptureDir = chaptersCacheDir.appendingPathComponent(scriptureId, isDirectory: true)
        let bookDir = scriptureDir.appendingPathComponent(bookId, isDirectory: true)
        try fileManager.createDirectory(at: bookDir, withIntermediateDirectories: true)

        let chapterFile = bookDir.appendingPathComponent("\(chapter).json")

        // Create a codable wrapper for verses
        let wrapper = CachedChapter(verses: verses)
        let data = try JSONEncoder().encode(wrapper)
        try data.write(to: chapterFile)
    }

    private func loadChapterFromCache(scriptureId: String, bookId: String, chapter: Int) -> [LoadedVerse]? {
        let chapterBaseDir = chaptersCacheDir
            .appendingPathComponent(scriptureId, isDirectory: true)
            .appendingPathComponent(bookId, isDirectory: true)
        let chapterJSONFile = chapterBaseDir.appendingPathComponent("\(chapter).json")
        let chapterNoExtFile = chapterBaseDir.appendingPathComponent("\(chapter)")
        let chapterFile: URL

        if fileManager.fileExists(atPath: chapterJSONFile.path) {
            chapterFile = chapterJSONFile
        } else if fileManager.fileExists(atPath: chapterNoExtFile.path) {
            chapterFile = chapterNoExtFile
        } else if let resolved = resolveAlternateCacheChapterFile(
            scriptureId: scriptureId,
            bookId: bookId,
            requestedChapter: chapter,
            basePath: chapterBaseDir
        ) {
            chapterFile = resolved
        } else {
            return nil
        }

        do {
            let data = try Data(contentsOf: chapterFile)
            let wrapper = try JSONDecoder().decode(CachedChapter.self, from: data)
            return try normalizeVerses(
                wrapper.loadedVerses,
                scriptureId: scriptureId,
                bookId: bookId,
                chapter: chapter
            )
        } catch {
            return nil
        }
    }

    // MARK: - Bundle Fallback

    private func loadIndexFromBundle() -> RemoteIndex? {
        guard let url = Bundle.main.url(forResource: "index", withExtension: "json", subdirectory: RemoteConfig.bundledDataFolder) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let index = try JSONDecoder().decode(RemoteIndex.self, from: data)
            try validateIndex(index)
            return index
        } catch {
            return nil
        }
    }

    private func filterToTopFive(_ index: RemoteIndex) -> RemoteIndex {
        let filteredTraditions = index.traditions
            .filter { Self.topFiveTraditionIDSet.contains($0.id) }
            .map { tradition in
                RemoteTradition(
                    id: tradition.id,
                    name: tradition.name,
                    icon: tradition.icon,
                    scriptures: tradition.scriptures.filter { Self.topFiveScriptureIDSet.contains($0) }
                )
            }

        let filteredScriptures = index.scriptures.filter { Self.topFiveScriptureIDSet.contains($0.key) }

        return RemoteIndex(
            version: index.version,
            traditions: filteredTraditions,
            scriptures: filteredScriptures
        )
    }

    private func normalizeKnownTraditionIcons(in index: RemoteIndex) -> RemoteIndex {
        let normalizedTraditions = index.traditions.map { tradition -> RemoteTradition in
            guard tradition.id == "judaism" else { return tradition }
            return RemoteTradition(
                id: tradition.id,
                name: tradition.name,
                icon: "star.fill",
                scriptures: tradition.scriptures
            )
        }

        return RemoteIndex(
            version: index.version,
            traditions: normalizedTraditions,
            scriptures: index.scriptures
        )
    }

    private func loadChapterFromBundle(scriptureId: String, bookId: String, chapter: Int) -> [LoadedVerse]? {
        let verses = VerseLoader.shared.load(scriptureId: scriptureId, bookId: bookId, chapter: chapter)
        return try? normalizeVerses(
            verses,
            scriptureId: scriptureId,
            bookId: normalizeBookId(bookId),
            chapter: chapter
        )
    }

    private func normalizeVerses(
        _ verses: [LoadedVerse],
        scriptureId: String,
        bookId: String,
        chapter: Int
    ) throws -> [LoadedVerse] {
        guard !verses.isEmpty else {
            throw RemoteDataError.invalidChapterData("Verse array is empty for \(scriptureId)/\(bookId)/\(chapter)")
        }

        return verses.map { verse in
            let text = verse.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let verseID = makeVerseID(scriptureId: scriptureId, bookId: bookId, chapter: chapter, verseNumber: verse.number)
            return LoadedVerse(id: verseID, number: verse.number, text: text)
        }
    }

    private func validateIndex(_ index: RemoteIndex) throws {
        guard !index.traditions.isEmpty else {
            throw RemoteDataError.invalidIndexData("traditions is empty")
        }
        guard !index.scriptures.isEmpty else {
            throw RemoteDataError.invalidIndexData("scriptures is empty")
        }

        for (scriptureID, scripture) in index.scriptures {
            if scripture.books.isEmpty {
                throw RemoteDataError.invalidIndexData("scripture \(scriptureID) has no books")
            }
            if scripture.books.contains(where: { $0.chapterCount < 1 }) {
                throw RemoteDataError.invalidIndexData("scripture \(scriptureID) has a book with chapterCount < 1")
            }
        }
    }

    private func makeVerseID(scriptureId: String, bookId: String, chapter: Int, verseNumber: Int) -> String {
        "\(scriptureId)|\(bookId)|\(chapter)|\(verseNumber)"
    }

    private func isTopFiveScripture(_ scriptureId: String) -> Bool {
        Self.topFiveScriptureIDSet.contains(scriptureId)
    }

    private func loadRequiredBundledChapter(scriptureId: String, bookId: String, chapter: Int) throws -> [LoadedVerse] {
        if let verses = loadChapterFromBundle(scriptureId: scriptureId, bookId: bookId, chapter: chapter), !verses.isEmpty {
            return verses
        }
        throw RemoteDataError.missingBundleResource(expectedBundledChapterPath(scriptureId: scriptureId, bookId: bookId, chapter: chapter))
    }

    private func loadTopFiveChapter(scriptureId: String, bookId: String, chapter: Int) async throws -> [LoadedVerse] {
        let normalizedBookId = normalizeBookId(bookId)
        let cacheKey = "\(scriptureId)/\(normalizedBookId)/\(chapter)"

        // STRICT ORDER for Top 5: BUNDLE -> CACHE -> REMOTE
        if let bundled = loadChapterFromBundle(scriptureId: scriptureId, bookId: bookId, chapter: chapter), !bundled.isEmpty {
            chapterCache[cacheKey] = bundled
            return bundled
        }

        if let cached = loadChapterFromCache(scriptureId: scriptureId, bookId: normalizedBookId, chapter: chapter), !cached.isEmpty {
            chapterCache[cacheKey] = cached
            return cached
        }

        guard datasetProvider.mode != .bundleOnly else {
            throw RemoteDataError.missingTopFiveLocalData(expectedBundledChapterPath(scriptureId: scriptureId, bookId: bookId, chapter: chapter))
        }

        for baseURL in datasetProvider.remoteBaseURLs {
            do {
                let verses = try await fetchChapter(
                    scriptureId: scriptureId,
                    bookId: normalizedBookId,
                    chapter: chapter,
                    from: baseURL
                )
                chapterCache[cacheKey] = verses
                try? saveChapterToCache(verses, scriptureId: scriptureId, bookId: normalizedBookId, chapter: chapter)
                return verses
            } catch {
                continue
            }
        }

        throw RemoteDataError.missingTopFiveLocalData(expectedBundledChapterPath(scriptureId: scriptureId, bookId: bookId, chapter: chapter))
    }

    private func expectedBundledChapterPath(scriptureId: String, bookId: String, chapter: Int) -> String {
        let normalizedBookId = normalizeBookId(bookId)
        let chapterNumber = intendedChapterNumberForBook(scriptureId: scriptureId, bookId: normalizedBookId, requestedChapter: chapter)
        return "\(RemoteConfig.bundledDataFolder)/\(scriptureId)/\(normalizedBookId)/\(chapterNumber).json"
    }

    private func resolveAlternateCacheChapterFile(
        scriptureId: String,
        bookId: String,
        requestedChapter: Int,
        basePath: URL
    ) -> URL? {
        guard alternateSingleChapterScriptures.contains(scriptureId) else {
            return nil
        }
        guard let contents = try? fileManager.contentsOfDirectory(
            at: basePath,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let numericJSON = contents.filter { file in
            file.pathExtension.lowercased() == "json" &&
            Int(file.deletingPathExtension().lastPathComponent) != nil
        }
        if numericJSON.count == 1 {
            return numericJSON[0]
        }

        let target = intendedChapterNumberForBook(
            scriptureId: scriptureId,
            bookId: bookId,
            requestedChapter: requestedChapter
        )
        if let exact = numericJSON.first(where: { Int($0.deletingPathExtension().lastPathComponent) == target }) {
            return exact
        }

        let numericNoExt = contents.filter { file in
            file.pathExtension.isEmpty && Int(file.lastPathComponent) != nil
        }
        if numericNoExt.count == 1 {
            return numericNoExt[0]
        }
        if let exactNoExt = numericNoExt.first(where: { Int($0.lastPathComponent) == target }) {
            return exactNoExt
        }

        return (numericJSON + numericNoExt).sorted { lhs, rhs in
            let l = Int(lhs.deletingPathExtension().lastPathComponent) ?? Int(lhs.lastPathComponent) ?? Int.max
            let r = Int(rhs.deletingPathExtension().lastPathComponent) ?? Int(rhs.lastPathComponent) ?? Int.max
            return l < r
        }.first
    }

    private func intendedChapterNumberForBook(scriptureId: String, bookId: String, requestedChapter: Int) -> Int {
        if requestedChapter != 1 {
            return requestedChapter
        }
        if scriptureId == "quran",
           let quranIndex = indexCache?.scriptures[scriptureId]?.books.firstIndex(where: { normalizeBookId($0.id) == bookId }) {
            return quranIndex + 1
        }
        if scriptureId == "bhagavad-gita",
           let suffix = bookId.split(separator: "-").last,
           let n = Int(suffix) {
            return n
        }
        return 1
    }

    private func isMalformedRemoteDataError(_ error: Error) -> Bool {
        if case RemoteDataError.decodingError = error {
            return true
        }
        if case RemoteDataError.invalidIndexData = error {
            return true
        }
        if case RemoteDataError.invalidChapterData = error {
            return true
        }
        return false
    }

    private func isCharging() -> Bool {
        let device = UIDevice.current
        let wasMonitoring = device.isBatteryMonitoringEnabled
        if !wasMonitoring {
            device.isBatteryMonitoringEnabled = true
        }
        defer {
            if !wasMonitoring {
                device.isBatteryMonitoringEnabled = false
            }
        }

        switch device.batteryState {
        case .charging, .full:
            return true
        default:
            return false
        }
    }

    private func isOnWiFi() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "seek.prefetch.wifi.check")
            monitor.pathUpdateHandler = { path in
                let connected = path.status == .satisfied && path.usesInterfaceType(.wifi)
                monitor.cancel()
                continuation.resume(returning: connected)
            }
            monitor.start(queue: queue)
        }
    }

    // MARK: - Diagnostics & Prefetch

    func logBundleStartupVerification() async {
        guard !hasLoggedSeekDataCheck else { return }
        hasLoggedSeekDataCheck = true

        let hasBundleIndex = Bundle.main.url(
            forResource: "index",
            withExtension: "json",
            subdirectory: RemoteConfig.bundledDataFolder
        ) != nil

        let bundledIndex = loadIndexFromBundle()
        func scriptureReadable(_ scriptureId: String) -> Bool {
            guard let scripture = bundledIndex?.scriptures[scriptureId],
                  let firstBook = scripture.books.first else {
                return false
            }
            let verses = loadChapterFromBundle(scriptureId: scriptureId, bookId: firstBook.id, chapter: 1) ?? []
            return !verses.isEmpty
        }

        print("[SeekDataCheck]")
        print("index: \(hasBundleIndex ? "ok" : "missing")")
        for scriptureId in Self.topFiveScriptureIDs {
            print("\(scriptureId): \(scriptureReadable(scriptureId) ? "ok" : "missing")")
        }
    }

    func topFiveDataStatusReport() async -> DataStatusReport {
        let hasBundleIndex = loadIndexFromBundle() != nil
        let hasCacheIndex = loadIndexFromCache() != nil
        let hasRemoteIndex = (try? await fetchIndex(from: RemoteConfig.baseURLs.first ?? "")) != nil

        let sourceSummary: String
        if hasRemoteIndex {
            sourceSummary = "remote"
        } else if hasCacheIndex {
            sourceSummary = "cache"
        } else if hasBundleIndex {
            sourceSummary = "bundle"
        } else {
            sourceSummary = "missing"
        }

        let resolvedIndex = (try? await loadIndex()) ?? getCachedIndex()
        var statuses: [ScriptureStatus] = []

        for scriptureID in Self.topFiveScriptureIDs {
            guard let scripture = resolvedIndex?.scriptures[scriptureID] else {
                statuses.append(
                    ScriptureStatus(
                        id: scriptureID,
                        name: scriptureID,
                        totalBooks: 0,
                        totalChapters: 0,
                        sampleChapterSuccess: false,
                        sampleChapterReference: "Missing in index"
                    )
                )
                continue
            }

            let totalBooks = scripture.books.count
            let totalChapters = scripture.books.reduce(0) { $0 + max(1, $1.chapterCount) }
            let sampleBook = scripture.books.first
            let sampleChapter = 1

            var sampleOK = false
            var sampleRef = "No sample"
            if let sampleBook {
                sampleRef = "\(sampleBook.name) \(sampleChapter)"
                if let verses = try? await loadChapter(
                    scriptureId: scriptureID,
                    bookId: sampleBook.id,
                    chapter: sampleChapter
                ), !verses.isEmpty {
                    sampleOK = true
                }
            }

            statuses.append(
                ScriptureStatus(
                    id: scriptureID,
                    name: scripture.name,
                    totalBooks: totalBooks,
                    totalChapters: totalChapters,
                    sampleChapterSuccess: sampleOK,
                    sampleChapterReference: sampleRef
                )
            )
        }

        return DataStatusReport(
            hasBundleIndex: hasBundleIndex,
            hasCacheIndex: hasCacheIndex,
            hasRemoteIndex: hasRemoteIndex,
            sourceSummary: sourceSummary,
            scriptureStatuses: statuses
        )
    }

    func prefetchTopFiveNow() async -> PrefetchResult {
        await prefetchTopFive()
    }

    func prefetchTopFiveIfEligible() async -> PrefetchResult? {
        let now = Date()
        let lastRun = UserDefaults.standard.object(forKey: prefetchTimestampKey) as? Date
        if let lastRun, now.timeIntervalSince(lastRun) < 12 * 60 * 60 {
            return nil
        }

        let shouldPrefetch = await isOnWiFi() || isCharging()
        guard shouldPrefetch else { return nil }
        let result = await prefetchTopFive()
        UserDefaults.standard.set(now, forKey: prefetchTimestampKey)
        return result
    }

    private func prefetchTopFive() async -> PrefetchResult {
        guard let index = try? await loadIndex() else {
            return PrefetchResult(attemptedChapters: 0, succeededChapters: 0, failedChapters: 0)
        }

        var attempted = 0
        var succeeded = 0
        var failed = 0

        for scriptureID in Self.topFiveScriptureIDs {
            guard let scripture = index.scriptures[scriptureID] else { continue }
            for book in scripture.books {
                let chapterCount = max(1, book.chapterCount)
                for chapter in 1...chapterCount {
                    attempted += 1
                    do {
                        let verses = try await loadChapter(
                            scriptureId: scriptureID,
                            bookId: book.id,
                            chapter: chapter
                        )
                        if verses.isEmpty {
                            failed += 1
                        } else {
                            succeeded += 1
                        }
                    } catch {
                        failed += 1
                    }
                }
            }
        }

        return PrefetchResult(attemptedChapters: attempted, succeededChapters: succeeded, failedChapters: failed)
    }

    // MARK: - Cache Management

    /// Clear all caches (memory and disk)
    func clearAllCaches() {
        indexCache = nil
        chapterCache.removeAll()
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        log("[RemoteDataService] All caches cleared")
    }

    /// Clear only chapter caches
    func clearChapterCaches() {
        chapterCache.removeAll()
        try? fileManager.removeItem(at: chaptersCacheDir)
        try? fileManager.createDirectory(at: chaptersCacheDir, withIntermediateDirectories: true)
        log("[RemoteDataService] Chapter caches cleared")
    }

    /// Get cache size in bytes
    func getCacheSize() -> Int64 {
        var size: Int64 = 0
        if let enumerator = fileManager.enumerator(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    size += Int64(fileSize)
                }
            }
        }
        return size
    }

    // MARK: - Logging

    private func log(_ message: String) {
        #if DEBUG
        print(message)
        #endif
    }

    private func logOnce(_ message: String) {
        if !hasLoggedStartup {
            hasLoggedStartup = true
            log(message)
        }
    }
}

// MARK: - Cache Models

private struct CachedChapter: Codable {
    let verses: [CachedVerse]

    init(verses: [LoadedVerse]) {
        self.verses = verses.map { CachedVerse(id: $0.id, number: $0.number, text: $0.text) }
    }
}

private struct CachedVerse: Codable {
    let id: String
    let number: Int
    let text: String
}

extension CachedChapter {
    var loadedVerses: [LoadedVerse] {
        verses.map { LoadedVerse(id: $0.id, number: $0.number, text: $0.text) }
    }
}

// MARK: - Convenience Extensions

extension RemoteDataService {
    /// Convert RemoteIndex to app models
    func convertToTraditions(_ index: RemoteIndex) -> [Tradition] {
        return index.traditions.map { remoteTradition in
            let texts = remoteTradition.scriptures.compactMap { scriptureId -> SacredText? in
                guard let scripture = index.scriptures[scriptureId] else { return nil }

                let books = scripture.books.map { book in
                    Book(id: book.id, name: book.name, chapterCount: book.chapterCount)
                }

                return SacredText(
                    id: scripture.id,
                    name: scripture.name,
                    description: scripture.description ?? "",
                    books: books
                )
            }

            return Tradition(
                id: remoteTradition.id,
                name: remoteTradition.name,
                icon: remoteTradition.id == "judaism" ? "star.fill" : remoteTradition.icon,
                texts: texts
            )
        }
    }
}

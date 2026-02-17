//
//  RemoteConfig.swift
//  Seek
//
//  Configuration for remote data fetching.
//  Supports multiple fallback URLs for reliability.
//  Uses GitHub raw content and jsDelivr CDN (free hosting).
//

import Foundation

// MARK: - Remote Configuration

struct RemoteConfig {
    /// Canonical bundled data folder name. Keep this consistent app-wide.
    static let bundledDataFolder = "SeekData"

    // MARK: - Base URLs (Primary + Fallbacks)

    /// Primary base URLs for fetching scripture data.
    /// The app will try these in order until one succeeds.
    /// These point to GitHub raw content / jsDelivr CDN (free hosting).
    ///
    /// To change the data source:
    /// 1. Update these URLs to point to your hosted data
    /// 2. Or use setCustomBaseURL() at runtime for testing
    static let baseURLs: [String] = [
        "https://cdn.jsdelivr.net/gh/anthropics/seek-texts@main/data",
        "https://raw.githubusercontent.com/anthropics/seek-texts/main/data"
    ]

    /// Current active base URL (can be overridden for testing/development)
    static var activeBaseURL: String {
        get { UserDefaults.standard.string(forKey: Keys.activeBaseURL) ?? baseURLs.first ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.activeBaseURL) }
    }

    /// Placeholder base URL for Guided Study proxy.
    /// Replace this at runtime (UserDefaults) with your own backend endpoint.
    static let openAIProxyBaseURLPlaceholder = "https://your-guided-study-proxy.example.com"

    /// Base URL for Guided Study proxy backend.
    static var openAIProxyBaseURL: String {
        get { UserDefaults.standard.string(forKey: Keys.openAIProxyBaseURL) ?? openAIProxyBaseURLPlaceholder }
        set { UserDefaults.standard.set(newValue, forKey: Keys.openAIProxyBaseURL) }
    }

    /// Toggle for local mock responses versus live proxy responses.
    static var useMockGuidedStudyProvider: Bool {
        get { UserDefaults.standard.object(forKey: Keys.useMockGuidedStudyProvider) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: Keys.useMockGuidedStudyProvider) }
    }

    static var hasConfiguredOpenAIProxyBaseURL: Bool {
        let trimmed = openAIProxyBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != openAIProxyBaseURLPlaceholder
    }

    // MARK: - Path Templates

    /// Path to the main index file containing all traditions/scriptures/books
    static let indexPath = "index.json"

    /// Template for chapter data paths.
    /// Placeholders: {scriptureId}, {bookId}, {chapter}
    static let chapterPathTemplate = "{scriptureId}/{bookId}/{chapter}.json"

    // MARK: - URL Builders

    /// Build the full URL for the index file
    static func indexURL(baseURL: String? = nil) -> URL? {
        let base = baseURL ?? activeBaseURL
        return URL(string: "\(base)/\(indexPath)")
    }

    /// Build the full URL for a specific chapter
    static func chapterURL(scriptureId: String, bookId: String, chapter: Int, baseURL: String? = nil) -> URL? {
        let base = baseURL ?? activeBaseURL
        let normalizedBookId = normalizeBookId(bookId)
        let path = chapterPathTemplate
            .replacingOccurrences(of: "{scriptureId}", with: scriptureId)
            .replacingOccurrences(of: "{bookId}", with: normalizedBookId)
            .replacingOccurrences(of: "{chapter}", with: String(chapter))
        return URL(string: "\(base)/\(path)")
    }

    // MARK: - Cache Settings

    /// How long to cache the index before checking for updates (in seconds)
    static let indexCacheDuration: TimeInterval = 24 * 60 * 60 // 24 hours

    /// How long to cache chapter data (in seconds)
    static let chapterCacheDuration: TimeInterval = 7 * 24 * 60 * 60 // 7 days

    // MARK: - Network Settings

    /// Request timeout in seconds
    static let requestTimeout: TimeInterval = 30

    /// Retry count for failed requests
    static let maxRetries: Int = 2

    // MARK: - Cache Directory

    /// The directory used for caching remote data
    /// Located in Application Support/SeekCache
    static var cacheDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport.appendingPathComponent("SeekCache", isDirectory: true)
    }

    // MARK: - Debug

    /// Log network activity in debug builds
    static var debugLogging: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    // MARK: - Configuration Methods

    /// Reset to default base URL
    static func resetToDefaultBaseURL() {
        UserDefaults.standard.removeObject(forKey: Keys.activeBaseURL)
    }

    /// Set a custom base URL (for development/testing)
    /// Example: setCustomBaseURL("http://localhost:8080/data")
    static func setCustomBaseURL(_ url: String) {
        activeBaseURL = url
    }

    /// Get current configuration summary for logging
    static func configurationSummary() -> String {
        """
        RemoteConfig:
          Active Base URL: \(activeBaseURL)
          Index Path: \(indexPath)
          Chapter Path Template: \(chapterPathTemplate)
          Cache Directory: \(cacheDirectory.path)
          Request Timeout: \(requestTimeout)s
        """
    }

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let activeBaseURL = "seek_active_base_url"
        static let openAIProxyBaseURL = "seek_openai_proxy_base_url"
        static let useMockGuidedStudyProvider = "seek_guided_study_use_mock_provider"
    }
}

// MARK: - Book ID Normalization

/// Normalizes a book ID to a folder-safe format.
/// - Converts to lowercase
/// - Removes spaces and punctuation (except hyphens)
/// - Preserves leading digits (e.g., "1 Corinthians" -> "1corinthians")
///
/// This function is used by both RemoteConfig and VerseLoader for consistency.
func normalizeBookId(_ bookId: String) -> String {
    var result = ""
    let lowercased = bookId.lowercased()

    for char in lowercased {
        if char.isLetter || char.isNumber {
            result.append(char)
        } else if char == "-" {
            result.append(char)
        }
    }

    return result
}

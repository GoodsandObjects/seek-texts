//
//  RemoteDatasetProvider.swift
//  Seek
//
//  Central dataset routing mode for bundle/cache/remote behavior.
//

import Foundation

enum DatasetMode {
    case bundleOnly
    case bundlePreferred
    case remotePreferred
}

@MainActor
final class RemoteDatasetProvider {
    static let shared = RemoteDatasetProvider()

    // Default mode required by app behavior.
    var mode: DatasetMode = .bundlePreferred

    // Prepared for future Cloudflare Pages hosting. Intentionally not active by default.
    private let cloudflareTemplate = "https://seek-texts.pages.dev/{scripture}/{book}/{chapter}.json"

    // Existing remote sources remain active until Cloudflare cutover.
    var remoteBaseURLs: [String] {
        RemoteConfig.baseURLs
    }

    private init() {}

    func cloudflareChapterURL(scriptureId: String, bookId: String, chapter: Int) -> URL? {
        let path = cloudflareTemplate
            .replacingOccurrences(of: "{scripture}", with: scriptureId)
            .replacingOccurrences(of: "{book}", with: normalizeBookId(bookId))
            .replacingOccurrences(of: "{chapter}", with: String(chapter))
        return URL(string: path)
    }
}

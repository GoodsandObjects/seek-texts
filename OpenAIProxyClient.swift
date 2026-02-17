import Foundation

struct GuidedStudyProviderContext {
    let context: String
    let scriptureId: String
    let bookId: String
    let chapter: Int
    let verseRange: ClosedRange<Int>?
    let selectedVerseIds: [String]
}

enum OpenAIProxyClientError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case emptyReply

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Guided Study proxy URL is invalid."
        case .invalidResponse:
            return "Guided Study proxy returned an invalid response."
        case .httpError(let statusCode, let message):
            return "Guided Study proxy failed (HTTP \(statusCode)): \(message)"
        case .emptyReply:
            return "Guided Study proxy returned an empty reply."
        }
    }
}

final class OpenAIProxyClient: AIProvider, @unchecked Sendable {

    private struct GuidedStudyProxyRequest: Encodable {
        let message: String
        let context: String
        let scriptureId: String
        let bookId: String
        let chapter: Int
        let verseRange: [Int]?
        let selectedVerseIds: [String]?
    }

    private struct GuidedStudyProxyResponse: Decodable {
        let reply: String
    }

    private let baseURL: String
    private let urlSession: URLSession

    // Keep system behavior deterministic and non-judgmental across providers.
    private let systemPrompt = "You are a non-judgmental companion for reflective scripture study. Be calm, respectful, and curious. Avoid certainty where the text is open to interpretation, and invite grounded reflection without moralizing or shaming."

    init(baseURL: String, timeout: TimeInterval = RemoteConfig.requestTimeout) {
        self.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.urlSession = URLSession(configuration: configuration)
    }

    func generateResponse(message: String, context: GuidedStudyProviderContext) async throws -> String {
        guard let endpoint = endpointURL() else {
            throw OpenAIProxyClientError.invalidBaseURL
        }

        let requestBody = GuidedStudyProxyRequest(
            message: message,
            context: "\(systemPrompt)\n\n\(context.context)",
            scriptureId: context.scriptureId,
            bookId: context.bookId,
            chapter: context.chapter,
            verseRange: context.verseRange.map { [$0.lowerBound, $0.upperBound] },
            selectedVerseIds: context.selectedVerseIds.isEmpty ? nil : context.selectedVerseIds
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIProxyClientError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data.prefix(240), encoding: .utf8) ?? "Unknown server error"
            throw OpenAIProxyClientError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        let payload = try JSONDecoder().decode(GuidedStudyProxyResponse.self, from: data)
        let trimmedReply = payload.reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReply.isEmpty else {
            throw OpenAIProxyClientError.emptyReply
        }

        return trimmedReply
    }

    private func endpointURL() -> URL? {
        guard !baseURL.isEmpty else { return nil }
        return URL(string: baseURL)?.appendingPathComponent("guided-study")
    }
}

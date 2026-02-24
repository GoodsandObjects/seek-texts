import Foundation

struct GuidedStudyChatMessage: Encodable {
    let role: String
    let content: String
}

struct GuidedStudyProviderContext {
    let scriptureRef: String
    let passageText: String
    let locale: String
}

enum OpenAIProxyClientError: LocalizedError {
    case invalidBaseURL
    case insecureBaseURL
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case emptyReply
    case network(underlying: String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Guided Study proxy URL is invalid."
        case .insecureBaseURL:
            return "Guided Study requires a secure HTTPS proxy URL."
        case .invalidResponse:
            return "Guided Study proxy returned an invalid response."
        case .httpError(let statusCode, let message):
            return "Guided Study proxy failed (HTTP \(statusCode)): \(message)"
        case .emptyReply:
            return "Guided Study proxy returned an empty reply."
        case .network(let underlying):
            return "Guided Study is temporarily unavailable. \(underlying)"
        }
    }
}

final class OpenAIProxyClient: AIProvider, @unchecked Sendable {

    private struct GuidedStudyProxyRequest: Encodable {
        let scriptureRef: String
        let passageText: String
        let messages: [GuidedStudyChatMessage]
        let locale: String
    }

    private struct GuidedStudyProxyResponse: Decodable {
        let replyText: String

        private enum CodingKeys: String, CodingKey {
            case replyText
            case reply
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let replyText = try container.decodeIfPresent(String.self, forKey: .replyText) {
                self.replyText = replyText
                return
            }
            if let legacyReply = try container.decodeIfPresent(String.self, forKey: .reply) {
                self.replyText = legacyReply
                return
            }
            throw OpenAIProxyClientError.invalidResponse
        }
    }

    private let baseURL: String
    private let urlSession: URLSession
    private let maxRetries: Int
    private let maxPassageCharacters = 2_400
    private let maxProxyMessageCount = 24

    init(
        baseURL: String,
        timeout: TimeInterval = RemoteConfig.requestTimeout,
        maxRetries: Int = RemoteConfig.maxRetries
    ) {
        self.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.maxRetries = max(0, maxRetries)

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.urlSession = URLSession(configuration: configuration)
    }

    func generateResponse(messages: [GuidedStudyChatMessage], context: GuidedStudyProviderContext) async throws -> String {
        let endpoints = endpointURLs()
        guard !endpoints.isEmpty else {
            throw OpenAIProxyClientError.invalidBaseURL
        }
        guard endpoints.allSatisfy({ $0.scheme?.lowercased() == "https" }) else {
            throw OpenAIProxyClientError.insecureBaseURL
        }
        let cleanedMessages = messages.filter {
            !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !cleanedMessages.isEmpty else {
            throw OpenAIProxyClientError.invalidResponse
        }

        let normalizedScriptureRef: String = {
            let trimmed = context.scriptureRef.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "General Study" : trimmed
        }()

        let boundedMessages = Array(cleanedMessages.suffix(maxProxyMessageCount))

        let requestBody = GuidedStudyProxyRequest(
            scriptureRef: normalizedScriptureRef,
            passageText: String(context.passageText.prefix(maxPassageCharacters)),
            messages: boundedMessages,
            locale: context.locale
        )

        let encodedBody = try JSONEncoder().encode(requestBody)
        var lastError: Error?

        for (index, endpoint) in endpoints.enumerated() {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = encodedBody

            do {
                let (data, _) = try await performRequestWithRetry(request)
                let payload = try JSONDecoder().decode(GuidedStudyProxyResponse.self, from: data)
                let trimmedReply = payload.replyText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedReply.isEmpty else {
                    throw OpenAIProxyClientError.emptyReply
                }
                return trimmedReply
            } catch let error as OpenAIProxyClientError {
                lastError = error
                if case .httpError(let statusCode, _) = error, statusCode == 404, index < endpoints.count - 1 {
                    continue
                }
                throw error
            } catch {
                lastError = error
                throw error
            }
        }

        throw lastError ?? OpenAIProxyClientError.invalidResponse
    }

    private func endpointURLs() -> [URL] {
        guard !baseURL.isEmpty else { return [] }
        guard let url = URL(string: baseURL) else { return [] }

        let normalizedURL = normalizedURLWithoutTrailingSlash(url)
        let path = normalizedURL.path.lowercased()
        var candidates: [URL] = []

        if path.hasSuffix("/guided-study") {
            candidates.append(normalizedURL)
        } else {
            candidates.append(normalizedURL.appendingPathComponent("guided-study"))
        }

        if path.hasSuffix("/api") {
            let withoutAPI = normalizedURL.deletingLastPathComponent().appendingPathComponent("guided-study")
            candidates.append(withoutAPI)
        }

        return deduplicatedURLs(candidates)
    }

    private func normalizedURLWithoutTrailingSlash(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = components?.path ?? ""
        if path.count > 1, path.hasSuffix("/") {
            components?.path = String(path.dropLast())
        }
        return components?.url ?? url
    }

    private func deduplicatedURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls {
            let absolute = url.absoluteString
            if !seen.contains(absolute) {
                seen.insert(absolute)
                result.append(url)
            }
        }
        return result
    }

    private func performRequestWithRetry(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var attempt = 0
        var lastError: Error?

        while attempt <= maxRetries {
            do {
                let (data, response) = try await urlSession.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw OpenAIProxyClientError.invalidResponse
                }

                if (200...299).contains(httpResponse.statusCode) {
                    return (data, response)
                }

                let message = String(data: data.prefix(240), encoding: .utf8) ?? "Unknown server error"
                let isRetryableServerError = (500...599).contains(httpResponse.statusCode)
                if isRetryableServerError && attempt < maxRetries {
                    try await backoffDelay(for: attempt)
                    attempt += 1
                    continue
                }
                throw OpenAIProxyClientError.httpError(statusCode: httpResponse.statusCode, message: message)
            } catch let proxyError as OpenAIProxyClientError {
                throw proxyError
            } catch {
                lastError = error
                if isRetryable(error: error), attempt < maxRetries {
                    try await backoffDelay(for: attempt)
                    attempt += 1
                    continue
                }
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                throw OpenAIProxyClientError.network(underlying: message)
            }
        }

        let message = (lastError as? LocalizedError)?.errorDescription ?? lastError?.localizedDescription ?? "Unknown network error."
        throw OpenAIProxyClientError.network(underlying: message)
    }

    private func isRetryable(error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed, .notConnectedToInternet:
            return true
        default:
            return false
        }
    }

    private func backoffDelay(for attempt: Int) async throws {
        let baseDelayNanoseconds: UInt64 = 400_000_000
        let multiplier = UInt64(1 << min(attempt, 4))
        try await Task.sleep(nanoseconds: baseDelayNanoseconds * multiplier)
    }
}

struct GuidedStudyProxyDebugResponse {
    let statusCode: Int
    let snippet: String
}

enum GuidedStudyProxyDiagnostics {
    private static let timeout: TimeInterval = 12

    static func testHealth(baseURL: String) async throws -> GuidedStudyProxyDebugResponse {
        let endpoint = try healthEndpoint(baseURL: baseURL)
        return try await requestRaw(endpoint: endpoint, method: "GET", body: nil)
    }

    static func testGuidedStudy(baseURL: String, locale: String) async throws -> GuidedStudyProxyDebugResponse {
        let endpoint = try guidedStudyEndpoint(baseURL: baseURL)
        let payload = [
            "scriptureRef": "John 3:16",
            "passageText": "For God so loved the world...",
            "messages": [
                [
                    "role": "user",
                    "content": "Give a short neutral context summary."
                ]
            ],
            "locale": locale
        ] as [String : Any]

        let body = try JSONSerialization.data(withJSONObject: payload)
        return try await requestRaw(endpoint: endpoint, method: "POST", body: body)
    }

    private static func requestRaw(endpoint: URL, method: String, body: Data?) async throws -> GuidedStudyProxyDebugResponse {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)

        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIProxyClientError.invalidResponse
        }
        let snippet = String(data: data.prefix(240), encoding: .utf8) ?? "<non-utf8>"
        return GuidedStudyProxyDebugResponse(statusCode: httpResponse.statusCode, snippet: snippet)
    }

    private static func healthEndpoint(baseURL: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), !trimmed.isEmpty else {
            throw OpenAIProxyClientError.invalidBaseURL
        }
        guard url.scheme?.lowercased() == "https" else {
            throw OpenAIProxyClientError.insecureBaseURL
        }
        if url.path.lowercased().hasSuffix("/health") {
            return url
        }
        if url.path.lowercased().hasSuffix("/guided-study") {
            return url.deletingLastPathComponent().appendingPathComponent("health")
        }
        return url.appendingPathComponent("health")
    }

    private static func guidedStudyEndpoint(baseURL: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), !trimmed.isEmpty else {
            throw OpenAIProxyClientError.invalidBaseURL
        }
        guard url.scheme?.lowercased() == "https" else {
            throw OpenAIProxyClientError.insecureBaseURL
        }
        if url.path.lowercased().hasSuffix("/guided-study") {
            return url
        }
        if url.path.lowercased().hasSuffix("/health") {
            return url.deletingLastPathComponent().appendingPathComponent("guided-study")
        }
        return url.appendingPathComponent("guided-study")
    }
}

import Foundation

/// A single decoded HTTP response returned by `APIClient`.
public struct APIResponse: Sendable {
    public let data: Data
    public let statusCode: Int
    public let headers: [String: String]
    public let url: URL?
    public let durationMs: Int
}

/// Transport-level errors raised by `APIClient`. HTTP status codes are NOT
/// errors here — callers map status codes to their own typed errors so each
/// service keeps its existing, specific error vocabulary.
public enum APIClientError: LocalizedError, Sendable {
    case networkFailure(String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .networkFailure(let detail):
            return detail
        case .invalidResponse:
            return "The server returned a response that was not valid HTTP."
        }
    }
}

/// Central HTTP transport: request building, retry/backoff (honoring
/// `Retry-After`), and secret redaction. Each service keeps its own typed
/// error mapping and log categories; this only owns transport concerns.
public struct APIClient: Sendable {
    public static let shared = APIClient()

    private let session: URLSession
    private let maxRetries: Int
    private let baseRetryDelay: TimeInterval

    public init(
        session: URLSession = .shared,
        maxRetries: Int = 3,
        baseRetryDelay: TimeInterval = 0.5
    ) {
        self.session = session
        self.maxRetries = maxRetries
        self.baseRetryDelay = baseRetryDelay
    }

    // MARK: - Request building

    public static func makeRequest(
        url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        timeout: TimeInterval = 15,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.cachePolicy = cachePolicy
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }

    // MARK: - Transport with retry/backoff

    /// Sends the request, retrying transient HTTP failures (429 and 5xx) with
    /// Retry-After-aware backoff. Returns the final response for any HTTP
    /// status so callers keep their own status-to-typed-error mapping. Throws
    /// `APIClientError` only for transport-level failures.
    public func send(_ request: URLRequest) async throws -> APIResponse {
        var attempt = 0
        while true {
            let response = try await perform(request)
            if Self.isRetryable(response.statusCode), attempt < maxRetries {
                attempt += 1
                try await Task.sleep(for: .seconds(retryDelay(after: response, attempt: attempt)))
                continue
            }
            return response
        }
    }

    private func perform(_ request: URLRequest) async throws -> APIResponse {
        let start = ContinuousClock.now
        let data: Data
        let urlResponse: URLResponse
        do {
            (data, urlResponse) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw APIClientError.networkFailure(urlError.localizedDescription)
        } catch {
            throw APIClientError.networkFailure(error.localizedDescription)
        }

        guard let http = urlResponse as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        let components = start.duration(to: .now).components
        let durationMs = Int(components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000)

        var headers: [String: String] = [:]
        for (field, value) in http.allHeaderFields {
            headers[String(describing: field)] = String(describing: value)
        }

        return APIResponse(
            data: data,
            statusCode: http.statusCode,
            headers: headers,
            url: urlResponse.url,
            durationMs: max(durationMs, 1)
        )
    }

    private static func isRetryable(_ statusCode: Int) -> Bool {
        statusCode == 429 || (500...599).contains(statusCode)
    }

    private func retryDelay(after response: APIResponse, attempt: Int) -> TimeInterval {
        if let raw = response.headers["Retry-After"],
           let seconds = TimeInterval(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return max(seconds, 0.1)
        }
        return baseRetryDelay * Double(1 << min(attempt, 10))
    }

    // MARK: - Central redaction

    /// Scrubs secrets (query params and Bearer tokens) from any string before
    /// it reaches logs. The single source of truth for log redaction.
    public static func redact(_ text: String) -> String {
        redactBearer(in: redactQuerySecrets(in: text))
    }

    public static func redact(url: URL) -> String {
        redact(url.absoluteString)
    }

    private static func redactQuerySecrets(in text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "([?&](?:key|api_key|apikey|token|access_token)=)[^&]+",
            options: .caseInsensitive
        ) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(
            in: text, options: [], range: range, withTemplate: "$1<REDACTED>"
        )
    }

    private static func redactBearer(in text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "(Authorization:[ ]*Bearer[ ]+)[^ ,]+",
            options: .caseInsensitive
        ) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(
            in: text, options: [], range: range, withTemplate: "$1<REDACTED>"
        )
    }
}

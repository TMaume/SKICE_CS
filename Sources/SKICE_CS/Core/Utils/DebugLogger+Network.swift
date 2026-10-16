import Foundation

extension DebugLogger {
    public func logNetworkRequest(_ request: URLRequest, tag: String) {
        let method = request.httpMethod ?? "GET"
        let sanitizedURL = APIClient.redact(request.url?.absoluteString ?? "unknown")
        var sanitizedHeaders = request.allHTTPHeaderFields ?? [:]
        if sanitizedHeaders["Authorization"] != nil {
            sanitizedHeaders["Authorization"] = "Bearer <REDACTED>"
        }
        log("[\(tag)] -> \(method) \(sanitizedURL) | Headers: \(sanitizedHeaders)")
    }

    public func logNetworkResponse(
        url: URL?,
        statusCode: Int,
        byteCount: Int,
        durationMs: Int,
        bodyPreview: String? = nil,
        tag: String
    ) {
        let sanitizedURL = APIClient.redact(url?.absoluteString ?? "unknown")
        if let bodyPreview, !bodyPreview.isEmpty {
            log("[\(tag)] <- HTTP \(statusCode) (\(byteCount) bytes in \(durationMs) ms) | \(sanitizedURL) | Body: \(bodyPreview)")
        } else {
            log("[\(tag)] <- HTTP \(statusCode) (\(byteCount) bytes in \(durationMs) ms) | \(sanitizedURL)")
        }
    }

    public func logNetworkError(_ message: String, tag: String) {
        log("[\(tag)] ERROR: \(message)")
    }
}

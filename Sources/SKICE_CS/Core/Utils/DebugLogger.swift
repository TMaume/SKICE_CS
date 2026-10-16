import Foundation
import Observation

/// Severity levels for in-app diagnostic logs.
public enum DebugLogLevel: String, CaseIterable, Codable, Sendable {
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

/// Represents a single diagnostic log event captured on the device.
public struct DebugLogEntry: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let level: DebugLogLevel
    public let category: String
    public let message: String
    public let httpStatusCode: Int?
    public let rawPayload: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: DebugLogLevel,
        category: String,
        message: String,
        httpStatusCode: Int? = nil,
        rawPayload: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.httpStatusCode = httpStatusCode
        self.rawPayload = rawPayload
    }

    /// Formats the timestamp as `HH:mm:ss.SSS` for compact monospace display.
    public var formattedTimestamp: String {
        Self.timestampFormatter.string(from: timestamp)
    }

    /// Single-block plain text representation for clipboard export.
    public var exportString: String {
        var line = "[\(formattedTimestamp)] [\(level.rawValue)] [\(category)]"
        if let status = httpStatusCode {
            line += " [HTTP \(status)]"
        }
        line += " \(message)"
        if let payload = rawPayload, !payload.isEmpty {
            line += "\n    ↳ Payload: \(payload)"
        }
        return line
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

/// Thread-safe, observable in-app logger capped at the last 200 entries.
@Observable
public final class DebugLogger: @unchecked Sendable {
    public static let shared = DebugLogger()

    public static let maxEntries: Int = 200

    /// UserDefaults key for the "Extensive GC Logging" developer toggle.
    public static let extensiveGCLoggingKey = "isExtensiveGCLoggingEnabled"

    /// True when verbose Game Coordinator diagnostics (wire frames, token
    /// claims, decode traces) are enabled. Off by default so the debug console
    /// isn't flooded; enable from Settings > Developer to diagnose logon or
    /// decode issues.
    public static var extensiveGCLoggingEnabled: Bool {
        UserDefaults.standard.bool(forKey: extensiveGCLoggingKey)
    }

    /// Observable list of log entries (newest first for quick inspection).
    public private(set) var entries: [DebugLogEntry] = []

    private let lock = NSLock()
    private var storage: [DebugLogEntry] = []

    private init() {}

    // MARK: - Logging API

    public func log(
        _ message: String,
        level: DebugLogLevel = .info,
        category: String = "App",
        httpStatusCode: Int? = nil,
        rawPayload: String? = nil
    ) {
        let truncatedPayload: String?
        if let rawPayload, rawPayload.count > 2_000 {
            truncatedPayload = String(rawPayload.prefix(2_000)) + "… [truncated]"
        } else {
            truncatedPayload = rawPayload
        }

        let entry = DebugLogEntry(
            level: level,
            category: category,
            message: message,
            httpStatusCode: httpStatusCode,
            rawPayload: truncatedPayload
        )

        lock.lock()
        storage.insert(entry, at: 0)
        if storage.count > Self.maxEntries {
            storage.removeLast(storage.count - Self.maxEntries)
        }
        let snapshot = storage
        lock.unlock()

        if Thread.isMainThread {
            self.entries = snapshot
        } else {
            Task { @MainActor in
                self.entries = snapshot
            }
        }
    }

    public func info(
        _ message: String,
        category: String = "Network",
        httpStatusCode: Int? = nil,
        rawPayload: String? = nil
    ) {
        log(message, level: .info, category: category, httpStatusCode: httpStatusCode, rawPayload: rawPayload)
    }

    public func warning(
        _ message: String,
        category: String = "Network",
        httpStatusCode: Int? = nil,
        rawPayload: String? = nil
    ) {
        log(message, level: .warning, category: category, httpStatusCode: httpStatusCode, rawPayload: rawPayload)
    }

    public func error(
        _ message: String,
        category: String = "Network",
        httpStatusCode: Int? = nil,
        rawPayload: String? = nil
    ) {
        log(message, level: .error, category: category, httpStatusCode: httpStatusCode, rawPayload: rawPayload)
    }

    /// Removes all stored log entries.
    public func clear() {
        lock.lock()
        storage.removeAll()
        lock.unlock()

        if Thread.isMainThread {
            self.entries = []
        } else {
            Task { @MainActor in
                self.entries = []
            }
        }
    }

    /// Exports all current logs into a single formatted string for `UIPasteboard`.
    public func exportFormattedLogs() -> String {
        lock.lock()
        let snapshot = storage
        lock.unlock()

        guard !snapshot.isEmpty else {
            return "=== SKICE_CS Debug Logs (Empty) ==="
        }

        let header = "=== SKICE_CS Debug Logs (\(snapshot.count) entries) ==="
        let body = snapshot.reversed().map(\.exportString).joined(separator: "\n\n")
        return "\(header)\n\n\(body)"
    }
}
import Foundation
import UIKit

/// Fetches Steam CDN image bytes and caches them on disk.
///
/// An actor serializes access to an in-flight task map so a URL is downloaded
/// at most once at a time even when many grid cells request it simultaneously,
/// then shares the result with every waiter. Only Data (never a non-Sendable
/// UIImage) crosses the actor boundary.
public actor ImageDownloader {
    /// Bump this to invalidate every disk-cached thumbnail at once.
    private static let schemaVersion = 1

    private let session: URLSession
    private let cacheDirectory: URL
    private var inFlight: [String: Task<Data?, Never>] = [:]
    private var completed: Set<String> = []

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)

        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.cacheDirectory = base.appendingPathComponent("ImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    public func data(for url: URL) async -> Data? {
        let key = Self.stableHash(url.absoluteString)

        if completed.contains(key) {
            return try? Data(contentsOf: diskURL(for: key))
        }

        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task { await self.fetchUncached(url: url, key: key) }
        inFlight[key] = task

        let result = await task.value
        if result != nil {
            completed.insert(key)
        }
        inFlight[key] = nil
        return result
    }

    public func clear() {
        inFlight.removeAll()
        completed.removeAll()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Private

    private func fetchUncached(url: URL, key: String) async -> Data? {
        if let cached = readDisk(key: key, url: url) {
            return cached
        }

        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            return nil
        }

        writeDisk(data, key: key, url: url)
        return data
    }

    private func readDisk(key: String, url: URL) -> Data? {
        guard let data = try? Data(contentsOf: diskURL(for: key)) else { return nil }

        // A sidecar mismatch (schema bump or URL change) forces a re-download.
        if let meta = try? Data(contentsOf: sidecarURL(for: key)),
           let sidecar = try? JSONDecoder().decode(Sidecar.self, from: meta),
           sidecar.schemaVersion != Self.schemaVersion || sidecar.url != url.absoluteString {
            return nil
        }
        return data
    }

    private func writeDisk(_ data: Data, key: String, url: URL) {
        try? data.write(to: diskURL(for: key), options: .atomic)
        let sidecar = Sidecar(schemaVersion: Self.schemaVersion, url: url.absoluteString)
        if let encoded = try? JSONEncoder().encode(sidecar) {
            try? encoded.write(to: sidecarURL(for: key), options: .atomic)
        }
    }

    private func diskURL(for key: String) -> URL {
        cacheDirectory.appendingPathComponent(key).appendingPathExtension("img")
    }

    private func sidecarURL(for key: String) -> URL {
        cacheDirectory.appendingPathComponent(key).appendingPathExtension("meta")
    }

    /// FNV-1a 64-bit, self-contained (no CryptoKit needed for a cache key).
    private static func stableHash(_ string: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

private struct Sidecar: Codable {
    let schemaVersion: Int
    let url: String
}

/// In-memory, size-bounded cache of decoded thumbnails plus the async loader
/// that bridges to ImageDownloader. Main-actor isolated so UIImage and NSCache
/// never cross an actor boundary.
@MainActor
public final class ImageManager {
    public static let shared = ImageManager()

    private let downloader: ImageDownloader
    private let memoryCache = NSCache<NSString, UIImage>()

    private static let memoryCostLimit = 64 * 1_024 * 1_024
    private static let memoryCountLimit = 400

    public init() {
        self.downloader = ImageDownloader()
        memoryCache.totalCostLimit = Self.memoryCostLimit
        memoryCache.countLimit = Self.memoryCountLimit
    }

    /// Synchronous memory-cache lookup — the fast path used during scrolling.
    public func image(for url: URL?) -> UIImage? {
        guard let url else { return nil }
        return memoryCache.object(forKey: url.absoluteString as NSString)
    }

    /// Memory-first async load: returns a decoded image, downloading and
    /// caching to disk on a miss.
    public func load(for url: URL?) async -> UIImage? {
        guard let url else { return nil }
        let key = url.absoluteString as NSString
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }
        guard let data = await downloader.data(for: url),
              let image = UIImage(data: data) else {
            return nil
        }
        memoryCache.setObject(image, forKey: key, cost: Self.memoryCost(of: image))
        return image
    }

    public func clearMemory() {
        memoryCache.removeAllObjects()
    }

    public func clearAll() {
        clearMemory()
        Task { await downloader.clear() }
    }

    private static func memoryCost(of image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 1 }
        return cg.width * cg.height * 4
    }
}

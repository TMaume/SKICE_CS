import Foundation

/// Typed errors thrown when fetching or parsing a Steam CS2 inventory.
public enum SteamInventoryError: LocalizedError, Equatable, Sendable {
    case invalidSteamID(String)
    case badRequest(details: String)
    case privateInventory
    case profileNotFound
    case rateLimited(retryAfterSeconds: Int?)
    case serverError(statusCode: Int)
    case networkFailure(String)
    case decodingFailure(String)

    public var errorDescription: String? {
        switch self {
        case .invalidSteamID(let id):
            return "Invalid SteamID64 format (\(id)). Must be a 17-digit number starting with 7656119."
        case .badRequest(let details):
            return "Steam rejected the request (HTTP 400). \(details)"
        case .privateInventory:
            return "This Steam inventory is set to Private or Friends-Only. Set your Inventory Privacy to Public in Steam Settings."
        case .profileNotFound:
            return "Steam profile or CS2 inventory could not be found (HTTP 404)."
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Steam API rate limit reached (HTTP 429). Please wait \(seconds) seconds before refreshing."
            }
            return "Steam API rate limit reached (HTTP 429). Please wait a moment before refreshing."
        case .serverError(let code):
            return "Steam Community servers returned HTTP \(code)."
        case .networkFailure(let details):
            return "Network connection error: \(details)"
        case .decodingFailure(let details):
            return "Failed to parse Steam inventory JSON: \(details)"
        }
    }
}

/// Protocol enabling dependency injection and unit testing for inventory fetching.
public protocol SteamInventoryServicing: Sendable {
    func fetchInventory(for steamID64: String) async throws -> [SkinItem]
}

/// Direct-to-API client querying `steamcommunity.com/inventory/<steamid64>/730/2`.
public struct SteamInventoryService: SteamInventoryServicing {
    private let client: APIClient
    private let appID: Int = 730
    private let contextID: Int = 2
    /// Steam rejects `count > 2000` with HTTP 400. `1000` is the safest page size.
    private let pageSize: Int = 1000
    private let maxPages: Int = 5

    public init(session: URLSession = .shared) {
        self.client = APIClient(session: session)
    }

    public func fetchInventory(for steamID64: String) async throws -> [SkinItem] {
        let trimmedID = steamID64.trimmingCharacters(in: .whitespacesAndNewlines)

        guard SteamCredentialsValidator.isValidSteamID64(trimmedID) else {
            DebugLogger.shared.error(
                "SteamID64 validation failed for input: '\(trimmedID)'",
                category: "Inventory"
            )
            throw SteamInventoryError.invalidSteamID(trimmedID)
        }

        DebugLogger.shared.info(
            "Starting CS2 inventory fetch for SteamID64: \(trimmedID)",
            category: "Inventory"
        )

        var allAssets: [SteamAsset] = []
        var exactDescriptionMap: [String: SteamDescription] = [:]
        var classFallbackMap: [String: SteamDescription] = [:]
        var currentStartAssetID: String? = nil
        var currentPage = 1

        while currentPage <= maxPages {
            let response = try await performPageRequest(
                steamID64: trimmedID,
                startAssetID: currentStartAssetID
            )

            guard response.success == 1 else {
                let errString = response.error ?? "Unknown Steam error (success != 1)"
                DebugLogger.shared.warning(
                    "Steam returned success != 1: \(errString)",
                    category: "Inventory"
                )
                throw SteamInventoryError.privateInventory
            }

            if let pageDescriptions = response.descriptions {
                for desc in pageDescriptions {
                    let exactKey = "\(desc.classid)_\(desc.instanceid)"
                    exactDescriptionMap[exactKey] = desc
                    // Store classid fallback in case a trade-locked asset has a non-zero instanceid
                    // while its shared description uses instanceid "0" (or vice versa).
                    if classFallbackMap[desc.classid] == nil || desc.instanceid == "0" {
                        classFallbackMap[desc.classid] = desc
                    }
                }
            }

            if let pageAssets = response.assets, !pageAssets.isEmpty {
                allAssets.append(contentsOf: pageAssets)
            } else if currentPage == 1 {
                if response.totalInventoryCount == 0 {
                    DebugLogger.shared.info(
                        "Inventory is public and valid, but contains 0 items.",
                        category: "Inventory"
                    )
                    return []
                }
                if response.rwgrsn == -2 && response.totalInventoryCount == nil {
                    DebugLogger.shared.warning(
                        "Inventory returned rwgrsn=-2 without assets (Private Inventory).",
                        category: "Inventory"
                    )
                    throw SteamInventoryError.privateInventory
                }
                return []
            }

            if response.moreItems == 1,
               let lastAssetID = response.lastAssetId,
               !lastAssetID.isEmpty {
                currentStartAssetID = lastAssetID
                currentPage += 1
            } else {
                break
            }
        }

        // Map every single asset in `allAssets` without filtering out untradable or restricted items
        var items: [SkinItem] = []
        items.reserveCapacity(allAssets.count)

        var fallbackMatchCount = 0
        var syntheticFallbackCount = 0

        for asset in allAssets {
            let exactKey = "\(asset.classid)_\(asset.instanceid)"
            if let exactDescription = exactDescriptionMap[exactKey] {
                items.append(
                    SkinItem(
                        asset: asset,
                        description: exactDescription,
                        ownerSteamID64: trimmedID
                    )
                )
            } else if let fallbackDescription = classFallbackMap[asset.classid] {
                fallbackMatchCount += 1
                items.append(
                    SkinItem(
                        asset: asset,
                        description: fallbackDescription,
                        ownerSteamID64: trimmedID
                    )
                )
            } else {
                syntheticFallbackCount += 1
                items.append(SkinItem(unmatchedAsset: asset))
            }
        }

        let tradableCount = items.filter(\.isTradable).count
        let cooldownCount = items.filter(\.isOnTradeCooldown).count
        let untradableCount = items.filter(\.isPermanentlyUntradable).count

        DebugLogger.shared.info(
            "Parsed \(items.count)/\(allAssets.count) items (Tradable: \(tradableCount), Cooldown: \(cooldownCount), Account-Bound: \(untradableCount), ClassFallback: \(fallbackMatchCount), Synthetic: \(syntheticFallbackCount)).",
            category: "Inventory"
        )

        return items
    }

    // MARK: - Private Network Execution

    private func performPageRequest(
        steamID64: String,
        startAssetID: String?
    ) async throws -> SteamInventoryResponse {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "l", value: "english"),
            URLQueryItem(name: "count", value: String(pageSize))
        ]
        if let startAssetID, !startAssetID.isEmpty {
            queryItems.append(URLQueryItem(name: "start_assetid", value: startAssetID))
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "steamcommunity.com"
        components.path = "/inventory/\(steamID64)/\(appID)/\(contextID)"
        components.queryItems = queryItems

        guard let url = components.url else {
            DebugLogger.shared.error("Failed to construct URL for SteamID64 \(steamID64)", category: "Inventory")
            throw SteamInventoryError.invalidSteamID(steamID64)
        }

        let refererURL = "https://steamcommunity.com/profiles/\(steamID64)/inventory"
        let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Mobile/15E148 Safari/604.1"

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(refererURL, forHTTPHeaderField: "Referer")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")

        let headersSummary = (request.allHTTPHeaderFields ?? [:])
            .map { "\($0.key): \($0.value)" }
            .sorted()
            .joined(separator: " | ")

        DebugLogger.shared.info(
            "GET \(url.absoluteString)",
            category: "HTTP Req",
            rawPayload: "Headers -> \(headersSummary)"
        )

        let apiResponse: APIResponse
        do {
            apiResponse = try await client.send(request)
        } catch let error as APIClientError {
            DebugLogger.shared.error(
                "Transport Error: \(error.localizedDescription)",
                category: "HTTP Err"
            )
            throw SteamInventoryError.networkFailure(error.localizedDescription)
        }

        let data = apiResponse.data
        let rawBodyString = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes binary>"
        let statusCode = apiResponse.statusCode

        if statusCode == 200 {
            DebugLogger.shared.info(
                "Received HTTP 200 (\(data.count) bytes) from \(url.path)",
                category: "HTTP Resp",
                httpStatusCode: statusCode,
                rawPayload: String(rawBodyString.prefix(500))
            )
        } else {
            DebugLogger.shared.error(
                "Non-200 HTTP Response from \(url.absoluteString)",
                category: "HTTP Resp",
                httpStatusCode: statusCode,
                rawPayload: rawBodyString
            )
        }

        switch statusCode {
        case 200:
            break
        case 400:
            let trimmedBody = rawBodyString.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedBody == "null" || trimmedBody.isEmpty {
                throw SteamInventoryError.badRequest(
                    details: "Steam returned 'null' (check if the SteamID64 exists and CS2 inventory is public)."
                )
            }
            throw SteamInventoryError.badRequest(details: "Response: \(trimmedBody.prefix(120))")
        case 401, 403:
            throw SteamInventoryError.privateInventory
        case 404:
            throw SteamInventoryError.profileNotFound
        case 429:
            let retrySeconds = apiResponse.headers["Retry-After"].flatMap { Int($0) }
            throw SteamInventoryError.rateLimited(retryAfterSeconds: retrySeconds)
        case 500...599:
            throw SteamInventoryError.serverError(statusCode: statusCode)
        default:
            throw SteamInventoryError.serverError(statusCode: statusCode)
        }

        let trimmedBody = rawBodyString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBody == "null" || trimmedBody.isEmpty {
            DebugLogger.shared.warning(
                "HTTP 200 received with literal 'null' body — Steam indicates a private inventory.",
                category: "Inventory",
                httpStatusCode: 200,
                rawPayload: rawBodyString
            )
            throw SteamInventoryError.privateInventory
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(SteamInventoryResponse.self, from: data)
        } catch {
            DebugLogger.shared.error(
                "JSON Decoding error: \(error.localizedDescription)",
                category: "JSON Parse",
                httpStatusCode: statusCode,
                rawPayload: String(rawBodyString.prefix(1_000))
            )
            throw SteamInventoryError.decodingFailure(error.localizedDescription)
        }
    }

}
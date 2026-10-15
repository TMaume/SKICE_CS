import Foundation

public enum FaceitStatsError: LocalizedError, Equatable, Sendable {
    case missingAPIKey
    case missingPlayerIdentifier
    case unauthorizedAPIKey
    case playerNotFound(String)
    case cs2ProfileNotFound(String)
    case rateLimited
    case httpError(statusCode: Int)
    case decodingFailed(String)
    case networkFailure(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "A FACEIT Open API v4 Client Key is required. Add your key in the FACEIT configuration sheet."
        case .missingPlayerIdentifier:
            return "Enter a FACEIT Nickname, FACEIT Player ID, or configure your SteamID64."
        case .unauthorizedAPIKey:
            return "FACEIT API Key was rejected (HTTP 401/403). Check your Client API Key in the FACEIT Developer Portal."
        case .playerNotFound(let query):
            return "No FACEIT player found matching '\(query)'."
        case .cs2ProfileNotFound(let nickname):
            return "FACEIT player '\(nickname)' has no registered CS2 game statistics."
        case .rateLimited:
            return "FACEIT Open API rate limit reached (HTTP 429). Please retry in a few seconds."
        case .httpError(let statusCode):
            return "FACEIT API returned HTTP \(statusCode)."
        case .decodingFailed(let detail):
            return "Failed to parse FACEIT response: \(detail)"
        case .networkFailure(let detail):
            return "Network error while contacting FACEIT API: \(detail)"
        }
    }
}

public actor FaceitStatsService {
    public static let shared = FaceitStatsService()

    private let client: APIClient
    private let baseURL = "https://open.faceit.com/data/v4"
    private let tag = "FaceitStatsService"

    public init(session: URLSession = .shared) {
        self.client = APIClient(session: session)
    }

    public func fetchPlayerStats(
        identifier: String,
        fallbackSteamID64: String?,
        apiKey: String
    ) async throws -> FaceitPlayerStats {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            throw FaceitStatsError.missingAPIKey
        }

        let cleanQuery = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSteamID = fallbackSteamID64?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !cleanQuery.isEmpty || !cleanSteamID.isEmpty else {
            throw FaceitStatsError.missingPlayerIdentifier
        }

        let profile = try await resolvePlayerProfile(
            query: cleanQuery,
            fallbackSteamID64: cleanSteamID,
            apiKey: cleanKey
        )

        guard profile.games?["cs2"] != nil || profile.games?["csgo"] != nil else {
            throw FaceitStatsError.cs2ProfileNotFound(profile.nickname)
        }

        let playerId = profile.player_id
        let region = profile.games?["cs2"]?.region ?? profile.games?["csgo"]?.region ?? "EU"

        async let statsTask: FaceitPlayerStatsResponse? = try? fetchLifetimeStats(
            playerId: playerId,
            apiKey: cleanKey
        )
        async let historyTask: FaceitMatchHistoryResponse? = try? fetchRecentHistory(
            playerId: playerId,
            apiKey: cleanKey
        )
        async let rankTask: Int? = try? fetchRegionalRank(
            playerId: playerId,
            region: region,
            apiKey: cleanKey
        )

        let (statsResponse, historyResponse, regionalRank) = await (statsTask, historyTask, rankTask)

        // Fetch granular per-match scoreboard stats (/matches/{match_id}/stats) for the latest 5 matches
        let recentMatchIds = (historyResponse?.items ?? []).prefix(5).map(\.match_id)
        var matchDetailsById: [String: FaceitMatchStatsResponse] = [:]

        await withTaskGroup(of: (String, FaceitMatchStatsResponse?).self) { group in
            for matchId in recentMatchIds {
                group.addTask {
                    let details = try? await self.fetchMatchStats(matchId: matchId, apiKey: cleanKey)
                    return (matchId, details)
                }
            }
            for await (matchId, details) in group {
                if let details {
                    matchDetailsById[matchId] = details
                }
            }
        }

        return FaceitPlayerStats(
            profile: profile,
            statsResponse: statsResponse,
            historyResponse: historyResponse,
            matchDetailsById: matchDetailsById,
            regionalRank: regionalRank
        )
    }

    // MARK: - Profile & Match Telemetry Endpoints

    private func resolvePlayerProfile(
        query: String,
        fallbackSteamID64: String,
        apiKey: String
    ) async throws -> FaceitPlayerProfileResponse {
        if !query.isEmpty {
            if Self.isUUID(query) {
                return try await performRequest(
                    path: "/players/\(query)",
                    queryItems: [],
                    apiKey: apiKey,
                    notFoundIdentifier: query
                )
            }

            if query.count == 17, query.allSatisfy(\.isNumber) {
                return try await performRequest(
                    path: "/players",
                    queryItems: [
                        URLQueryItem(name: "game", value: "cs2"),
                        URLQueryItem(name: "game_player_id", value: query)
                    ],
                    apiKey: apiKey,
                    notFoundIdentifier: query
                )
            }

            do {
                return try await performRequest(
                    path: "/players",
                    queryItems: [URLQueryItem(name: "nickname", value: query)],
                    apiKey: apiKey,
                    notFoundIdentifier: query
                )
            } catch FaceitStatsError.playerNotFound {
                let searchResult: FaceitPlayerSearchResponse = try await performRequest(
                    path: "/search/players",
                    queryItems: [
                        URLQueryItem(name: "nickname", value: query),
                        URLQueryItem(name: "game", value: "cs2"),
                        URLQueryItem(name: "limit", value: "5")
                    ],
                    apiKey: apiKey,
                    notFoundIdentifier: query
                )

                let matchedItem = searchResult.items?.first(where: {
                    $0.nickname.caseInsensitiveCompare(query) == .orderedSame
                }) ?? searchResult.items?.first

                guard let resolvedId = matchedItem?.player_id else {
                    throw FaceitStatsError.playerNotFound(query)
                }

                return try await performRequest(
                    path: "/players/\(resolvedId)",
                    queryItems: [],
                    apiKey: apiKey,
                    notFoundIdentifier: query
                )
            }
        }

        return try await performRequest(
            path: "/players",
            queryItems: [
                URLQueryItem(name: "game", value: "cs2"),
                URLQueryItem(name: "game_player_id", value: fallbackSteamID64)
            ],
            apiKey: apiKey,
            notFoundIdentifier: fallbackSteamID64
        )
    }

    private func fetchLifetimeStats(
        playerId: String,
        apiKey: String
    ) async throws -> FaceitPlayerStatsResponse {
        try await performRequest(
            path: "/players/\(playerId)/stats/cs2",
            queryItems: [],
            apiKey: apiKey,
            notFoundIdentifier: playerId
        )
    }

    private func fetchRecentHistory(
        playerId: String,
        apiKey: String
    ) async throws -> FaceitMatchHistoryResponse {
        try await performRequest(
            path: "/players/\(playerId)/history",
            queryItems: [
                URLQueryItem(name: "game", value: "cs2"),
                URLQueryItem(name: "offset", value: "0"),
                URLQueryItem(name: "limit", value: "10")
            ],
            apiKey: apiKey,
            notFoundIdentifier: playerId
        )
    }

    private func fetchMatchStats(
        matchId: String,
        apiKey: String
    ) async throws -> FaceitMatchStatsResponse {
        try await performRequest(
            path: "/matches/\(matchId)/stats",
            queryItems: [],
            apiKey: apiKey,
            notFoundIdentifier: matchId
        )
    }

    private func fetchRegionalRank(
        playerId: String,
        region: String,
        apiKey: String
    ) async throws -> Int? {
        let encodedRegion = region.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? region
        let response: FaceitRankingResponse = try await performRequest(
            path: "/rankings/games/cs2/regions/\(encodedRegion)/players/\(playerId)",
            queryItems: [URLQueryItem(name: "limit", value: "1")],
            apiKey: apiKey,
            notFoundIdentifier: playerId
        )
        return response.position
    }

    // MARK: - Generic Authenticated Request Executor

    private func performRequest<T: Decodable & Sendable>(
        path: String,
        queryItems: [URLQueryItem],
        apiKey: String,
        notFoundIdentifier: String
    ) async throws -> T {
        var components = URLComponents(string: baseURL + path)
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }

        guard let url = components?.url else {
            throw FaceitStatsError.missingPlayerIdentifier
        }

        var mutableRequest = URLRequest(url: url)
        mutableRequest.httpMethod = "GET"
        mutableRequest.timeoutInterval = 15
        mutableRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        mutableRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        mutableRequest.setValue("SKICE_CS/1.0 (iOS 17+)", forHTTPHeaderField: "User-Agent")

        let request = mutableRequest
        let serviceTag = self.tag

        await MainActor.run {
            DebugLogger.shared.logStatsNetworkRequest(request, tag: serviceTag)
        }

        let apiResponse: APIResponse
        do {
            apiResponse = try await client.send(request)
        } catch let error as APIClientError {
            let errText = error.localizedDescription
            await MainActor.run {
                DebugLogger.shared.logStatsError(errText, tag: serviceTag)
            }
            throw FaceitStatsError.networkFailure(errText)
        }

        let statusCode = apiResponse.statusCode
        let byteCount = apiResponse.data.count
        let elapsedMs = apiResponse.durationMs

        await MainActor.run {
            DebugLogger.shared.logStatsNetworkResponse(
                url: url,
                statusCode: statusCode,
                byteCount: byteCount,
                durationMs: max(elapsedMs, 1),
                tag: serviceTag
            )
        }

        switch statusCode {
        case 200:
            break
        case 401, 403:
            throw FaceitStatsError.unauthorizedAPIKey
        case 404:
            throw FaceitStatsError.playerNotFound(notFoundIdentifier)
        case 429:
            throw FaceitStatsError.rateLimited
        default:
            throw FaceitStatsError.httpError(statusCode: statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: apiResponse.data)
        } catch {
            let errText = error.localizedDescription
            await MainActor.run {
                DebugLogger.shared.logStatsError("JSON decode error: \(errText)", tag: serviceTag)
            }
            throw FaceitStatsError.decodingFailed(errText)
        }
    }

    private static func isUUID(_ text: String) -> Bool {
        UUID(uuidString: text) != nil
    }
}
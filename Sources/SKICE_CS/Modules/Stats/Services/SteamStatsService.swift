import Foundation

public enum SteamStatsError: LocalizedError, Equatable, Sendable {
    case missingCredentials
    case invalidSteamID
    case invalidWebAPIKey
    case privateGameDetails
    case noStatsAvailable
    case rateLimited
    case httpError(statusCode: Int)
    case decodingFailed(String)
    case networkFailure(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "SteamID64 and a 32-character Steam Web API Key are required. Save both in the Profile tab."
        case .invalidSteamID:
            return "The configured SteamID64 is invalid (expected a 17-digit numeric ID)."
        case .invalidWebAPIKey:
            return "Steam rejected your Web API Key (HTTP 403). Verify that your 32-character key from steamcommunity.com/dev/apikey is saved in the Profile tab."
        case .privateGameDetails:
            return "Your Steam API Key is valid, but 'Game details' is private on this Steam account. Go to Steam -> Edit Profile -> Privacy Settings -> set 'Game details' to Public and uncheck 'Always keep my total playtime private'."
        case .noStatsAvailable:
            return "No CS2 statistics were returned for this Steam account."
        case .rateLimited:
            return "Steam Web API rate limit reached (HTTP 429). Please wait a moment and try again."
        case .httpError(let code):
            return "Steam Web API returned HTTP \(code)."
        case .decodingFailed(let detail):
            return "Failed to parse Steam stats payload: \(detail)"
        case .networkFailure(let detail):
            return "Network error while contacting Steam Web API: \(detail)"
        }
    }
}

public actor SteamStatsService {
    public static let shared = SteamStatsService()

    private let session: URLSession
    private let cs2AppID = "730"
    private let tag = "SteamStatsService"

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchPlayerStats(steamID64: String, apiKey: String) async throws -> SteamPlayerStats {
        let cleanSteamID = steamID64.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanSteamID.isEmpty, !cleanAPIKey.isEmpty else {
            throw SteamStatsError.missingCredentials
        }

        guard cleanSteamID.count == 17, cleanSteamID.allSatisfy(\.isNumber) else {
            throw SteamStatsError.invalidSteamID
        }

        var components = URLComponents(string: "https://api.steampowered.com/ISteamUserStats/GetUserStatsForGame/v0002/")
        components?.queryItems = [
            URLQueryItem(name: "appid", value: cs2AppID),
            URLQueryItem(name: "key", value: cleanAPIKey),
            URLQueryItem(name: "steamid", value: cleanSteamID),
            URLQueryItem(name: "format", value: "json")
        ]

        guard let url = components?.url else {
            throw SteamStatsError.invalidSteamID
        }

        var mutableRequest = URLRequest(url: url)
        mutableRequest.httpMethod = "GET"
        mutableRequest.timeoutInterval = 15
        mutableRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        mutableRequest.setValue("SKICE_CS/1.0 (iOS 17+)", forHTTPHeaderField: "User-Agent")

        let request = mutableRequest
        let serviceTag = self.tag

        await MainActor.run {
            DebugLogger.shared.logStatsNetworkRequest(request, tag: serviceTag)
        }

        let startTime = ContinuousClock.now
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            let errText = error.localizedDescription
            await MainActor.run {
                DebugLogger.shared.logStatsError(errText, tag: serviceTag)
            }
            throw SteamStatsError.networkFailure(errText)
        }

        let elapsedMs = Int(startTime.duration(to: .now).components.attoseconds / 1_000_000_000_000_000)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SteamStatsError.networkFailure("Invalid HTTP response")
        }

        let statusCode = httpResponse.statusCode
        let byteCount = data.count
        let bodyPreview: String? = statusCode != 200
            ? String(data: data.prefix(220), encoding: .utf8)?.replacingOccurrences(of: "\n", with: " ")
            : nil

        await MainActor.run {
            DebugLogger.shared.logStatsNetworkResponse(
                url: url,
                statusCode: statusCode,
                byteCount: byteCount,
                durationMs: max(elapsedMs, 1),
                bodyPreview: bodyPreview,
                tag: serviceTag
            )
        }

        switch statusCode {
        case 200:
            break
        case 400:
            throw SteamStatsError.invalidSteamID
        case 401, 403, 500:
            // Probe GetPlayerSummaries to determine if the API key is valid or if Game Details privacy is blocking access
            let isKeyValid = await verifyAPIKeyWithPlayerSummaries(steamID64: cleanSteamID, apiKey: cleanAPIKey)
            if isKeyValid {
                await MainActor.run {
                    DebugLogger.shared.logStatsError(
                        "API Key verified OK via GetPlayerSummaries, but GetUserStatsForGame returned HTTP \(statusCode). Cause: Steam 'Game details' privacy is set to Friends-Only/Private or 'Always keep my total playtime private' is enabled.",
                        tag: serviceTag
                    )
                }
                throw SteamStatsError.privateGameDetails
            } else {
                await MainActor.run {
                    DebugLogger.shared.logStatsError(
                        "GetPlayerSummaries also rejected the API Key (HTTP 403). The Steam Web API Key is invalid.",
                        tag: serviceTag
                    )
                }
                throw SteamStatsError.invalidWebAPIKey
            }
        case 429:
            throw SteamStatsError.rateLimited
        default:
            throw SteamStatsError.httpError(statusCode: statusCode)
        }

        do {
            let decoded = try JSONDecoder().decode(SteamUserStatsResponse.self, from: data)
            guard let payload = decoded.playerstats,
                  let rawStats = payload.stats,
                  !rawStats.isEmpty else {
                throw SteamStatsError.noStatsAvailable
            }
            return SteamPlayerStats(steamID64: cleanSteamID, payload: payload)
        } catch let error as SteamStatsError {
            throw error
        } catch {
            let errText = error.localizedDescription
            await MainActor.run {
                DebugLogger.shared.logStatsError("JSON decode error: \(errText)", tag: serviceTag)
            }
            throw SteamStatsError.decodingFailed(errText)
        }
    }

    private func verifyAPIKeyWithPlayerSummaries(steamID64: String, apiKey: String) async -> Bool {
        var components = URLComponents(string: "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002/")
        components?.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "steamids", value: steamID64)
        ]
        guard let url = components?.url else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return http.statusCode == 200
        } catch {
            return false
        }
    }
}
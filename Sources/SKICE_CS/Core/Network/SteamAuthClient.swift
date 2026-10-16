import Foundation

/// Platform type requested for the Steam session. Steam issues tokens with
/// different audiences per platform: a Steam client session yields tokens with
/// the ["web", "client"] audiences, which is what the Game Coordinator work
/// (roadmap M2) needs. Advertising another platform would produce tokens the
/// GC will not accept.
public enum SteamTokenPlatformType: Int, Sendable, CaseIterable {
    case steamClient = 1
    case webBrowser = 2
    case mobileApp = 3

    /// Value Steam expects in the website_id field of the request.
    var websiteID: String {
        switch self {
        case .steamClient: return "Unknown"
        case .webBrowser: return "Community"
        case .mobileApp: return "Mobile"
        }
    }

    var deviceLabel: String {
        switch self {
        case .steamClient: return "SKICE_CS"
        case .webBrowser: return "SKICE_CS Web"
        case .mobileApp: return "SKICE_CS iOS"
        }
    }
}

/// Steam Guard confirmation choices offered for a pending login.
public enum SteamGuardKind: Int, Sendable, Equatable, Codable {
    case unknown = 0
    case noGuard = 1
    case emailCode = 2
    case deviceCode = 3
    case deviceConfirmation = 4
    case emailConfirmation = 5
    case machineToken = 6
    case legacyMachineAuth = 7

    /// The user must type a code into the app.
    public var requiresCodeEntry: Bool {
        self == .emailCode || self == .deviceCode || self == .emailConfirmation
    }

    /// The user approves the login inside the Steam mobile app; we only poll.
    public var isRemoteApproval: Bool {
        self == .deviceConfirmation
    }

    public var isSatisfiedAutomatically: Bool {
        self == .noGuard || self == .machineToken || self == .legacyMachineAuth
    }

    public var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .noGuard: return "No guard required"
        case .emailCode: return "Email code"
        case .deviceCode: return "Device code"
        case .deviceConfirmation: return "Mobile app approval"
        case .emailConfirmation: return "Email confirmation"
        case .machineToken: return "Saved device"
        case .legacyMachineAuth: return "Legacy device auth"
        }
    }
}

/// One guard option returned by Steam for a pending login.
public struct SteamGuardConfirmation: Sendable, Equatable {
    public let kind: SteamGuardKind
    public let message: String?

    public init(kind: SteamGuardKind, message: String?) {
        self.kind = kind
        self.message = message
    }
}

/// A pending login session: Steam has accepted the credentials and wants a
/// guard satisfied before it releases the tokens.
public struct SteamAuthChallenge: Sendable, Equatable {
    public let clientID: UInt64
    public let requestID: String
    public let steamID: String?
    public let pollInterval: Double
    public let confirmations: [SteamGuardConfirmation]
    public let challengeURL: String?

    public init(
        clientID: UInt64,
        requestID: String,
        steamID: String?,
        pollInterval: Double,
        confirmations: [SteamGuardConfirmation],
        challengeURL: String? = nil
    ) {
        self.clientID = clientID
        self.requestID = requestID
        self.steamID = steamID
        self.pollInterval = pollInterval
        self.confirmations = confirmations
        self.challengeURL = challengeURL
    }
}

/// Tokens released by Steam once the session is fully authorized.
public struct SteamAuthTokens: Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let accountName: String?
    public let newGuardData: String?

    public init(accessToken: String, refreshToken: String?, accountName: String?, newGuardData: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accountName = accountName
        self.newGuardData = newGuardData
    }
}

/// Outcome of submitting credentials: either the session is complete, or a
/// guard must be satisfied first.
public enum SteamAuthStartOutcome: Sendable {
    case authorized(SteamAuthTokens)
    case guardRequired(SteamAuthChallenge)
}

/// Typed failures of the Tier B authentication flow. HTTP status is not the
/// signal here: Steam answers 200 with an EResult in the x-eresult header.
public enum SteamAuthError: LocalizedError, Sendable {
    case invalidCredentials
    case accountNotFound
    case rateLimited
    case invalidGuardCode
    case guardCodeExpired
    case sessionExpired
    case accountDisabled
    case serverUnavailable
    case unexpectedResult(Int)
    case malformedResponse(String)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Steam rejected the account name or password."
        case .accountNotFound:
            return "No Steam account matches that account name."
        case .rateLimited:
            return "Steam is rate-limiting login attempts. Wait a few minutes and try again."
        case .invalidGuardCode:
            return "Steam rejected that Steam Guard code."
        case .guardCodeExpired:
            return "That Steam Guard code has expired. Start the sign-in again."
        case .sessionExpired:
            return "The Steam session is no longer valid. Sign in again."
        case .accountDisabled:
            return "Steam reports this account is disabled."
        case .serverUnavailable:
            return "Steam is temporarily unavailable. Try again shortly."
        case .unexpectedResult(let code):
            return "Steam returned an unexpected result (EResult \(code))."
        case .malformedResponse(let detail):
            return "Unexpected response from Steam: \(detail)"
        case .transport(let detail):
            return "Network error while talking to Steam: \(detail)"
        }
    }
}

/// Steam login transport (Tier B).
///
/// Every request goes straight from the device to api.steampowered.com; there is
/// no relay and no telemetry (ROADMAP section 0.2, ADR-04). Request bodies are
/// protobuf messages carried in the input_protobuf_encoded form field, which is
/// how Steam's authentication service is driven.
public struct SteamAuthClient: Sendable {
    public static let shared = SteamAuthClient()

    private let transport: APIClient
    private static let baseURLString = "https://api.steampowered.com"

    public init(transport: APIClient = .shared) {
        self.transport = transport
    }

    // MARK: - Public flow

    /// Fetches the RSA public key Steam wants the password encrypted with.
    public func requestPasswordRSAPublicKey(accountName: String) async throws -> SteamRSAPublicKey {
        guard var components = URLComponents(string: Self.baseURLString + "/IAuthenticationService/GetPasswordRSAPublicKey/v1/") else {
            throw SteamAuthError.malformedResponse("could not build the RSA key URL")
        }
        components.queryItems = [URLQueryItem(name: "account_name", value: accountName)]
        guard let url = components.url else {
            throw SteamAuthError.malformedResponse("could not build the RSA key URL")
        }

        let request = APIClient.makeRequest(
            url: url,
            method: "GET",
            headers: ["Accept": "application/json, text/plain, */*"],
            cachePolicy: .reloadIgnoringLocalCacheData
        )

        let envelope: PasswordRSAPublicKeyEnvelope = try await sendJSON(request, method: "GetPasswordRSAPublicKey")
        guard let key = envelope.response, !key.publickeyMod.isEmpty else {
            throw SteamAuthError.malformedResponse("GetPasswordRSAPublicKey returned no key")
        }
        return SteamRSAPublicKey(
            modulusHex: key.publickeyMod,
            exponentHex: key.publickeyExp,
            timestamp: key.timestamp
        )
    }

    /// Starts a credentials login session and, when Steam needs no guard,
    /// immediately polls for the resulting tokens.
    public func beginAuthSession(
        accountName: String,
        password: String,
        platformType: SteamTokenPlatformType,
        guardData: Data? = nil,
        persistence: Bool = true
    ) async throws -> SteamAuthStartOutcome {
        let rsaKey = try await requestPasswordRSAPublicKey(accountName: accountName)
        let encrypted = try RSAEncryption.encrypt(
            plaintext: password,
            modulusHex: rsaKey.modulusHex,
            exponentHex: rsaKey.exponentHex
        )

        var payload = ProtobufEncoder()
        payload.writeString(2, accountName)
        payload.writeString(3, encrypted.base64EncodedString())
        payload.writeUInt64(4, rsaKey.timestamp)
        payload.writeBool(5, persistence)
        payload.writeInt32(6, Int32(platformType.rawValue))
        payload.writeInt32(7, persistence ? 1 : 0)
        payload.writeString(8, platformType.websiteID)

        var deviceDetails = ProtobufEncoder()
        deviceDetails.writeString(1, platformType.deviceLabel)
        deviceDetails.writeInt32(2, Int32(platformType.rawValue))
        payload.writeMessage(9, deviceDetails)

        if let guardData, !guardData.isEmpty {
            payload.writeBytes(10, guardData)
        }

        let envelope: BeginAuthSessionEnvelope = try await sendProtobuf(
            payload,
            method: "BeginAuthSessionViaCredentials"
        )

        guard let response = envelope.response,
              response.clientID != 0,
              !response.requestID.isEmpty else {
            throw SteamAuthError.invalidCredentials
        }

        let confirmations = response.allowedConfirmations.map {
            SteamGuardConfirmation(
                kind: SteamGuardKind(rawValue: $0.confirmationType) ?? .unknown,
                message: $0.associatedMessage
            )
        }

        let challenge = SteamAuthChallenge(
            clientID: response.clientID,
            requestID: response.requestID,
            steamID: response.steamID,
            pollInterval: max(Double(response.interval ?? 5), 1),
            confirmations: confirmations
        )

        return .guardRequired(challenge)
    }

    /// Starts a QR login session: the user scans the returned challenge with the
    /// Steam mobile app and approves there. No password is handled on-device.
    public func beginAuthSessionViaQR(
        platformType: SteamTokenPlatformType = .steamClient
    ) async throws -> SteamAuthChallenge {
        var deviceDetails = ProtobufEncoder()
        deviceDetails.writeString(1, platformType.deviceLabel)
        deviceDetails.writeInt32(2, Int32(platformType.rawValue))

        var payload = ProtobufEncoder()
        payload.writeMessage(3, deviceDetails)

        let envelope: BeginAuthSessionViaQREnvelope = try await sendProtobuf(
            payload,
            method: "BeginAuthSessionViaQR"
        )

        guard let response = envelope.response,
              response.clientID != 0,
              !response.requestID.isEmpty else {
            throw SteamAuthError.malformedResponse("BeginAuthSessionViaQR returned no challenge")
        }

        let confirmations = response.allowedConfirmations.map {
            SteamGuardConfirmation(
                kind: SteamGuardKind(rawValue: $0.confirmationType) ?? .unknown,
                message: $0.associatedMessage
            )
        }

        return SteamAuthChallenge(
            clientID: response.clientID,
            requestID: response.requestID,
            steamID: nil,
            pollInterval: max(Double(response.interval ?? 5), 1),
            confirmations: confirmations,
            challengeURL: response.challengeURL
        )
    }

    /// Supplies a Steam Guard code for a pending session.
    public func submitGuardCode(
        challenge: SteamAuthChallenge,
        code: String,
        kind: SteamGuardKind
    ) async throws {
        var payload = ProtobufEncoder()
        payload.writeUInt64(1, challenge.clientID)
        payload.writeFixed64(2, UInt64(challenge.steamID ?? "0") ?? 0)
        payload.writeString(3, code.trimmingCharacters(in: .whitespacesAndNewlines))
        payload.writeInt32(4, Int32(kind.rawValue))

        _ = try await sendProtobufRaw(payload, method: "UpdateAuthSessionWithSteamGuardCode")
    }

    /// Polls a pending session. Steam answers with tokens once the guard is
    /// satisfied (and with an empty response while it is not).
    public func pollAuthSessionStatus(challenge: SteamAuthChallenge) async throws -> SteamAuthTokens? {
        var payload = ProtobufEncoder()
        payload.writeUInt64(1, challenge.clientID)
        payload.writeBytes(2, Data(base64Encoded: challenge.requestID) ?? Data())

        let envelope: PollAuthSessionStatusEnvelope = try await sendProtobuf(
            payload,
            method: "PollAuthSessionStatus"
        )

        guard let response = envelope.response, let accessToken = response.accessToken, !accessToken.isEmpty else {
            return nil
        }

        return SteamAuthTokens(
            accessToken: accessToken,
            refreshToken: response.refreshToken,
            accountName: response.accountName,
            newGuardData: response.newGuardData
        )
    }

    /// Exchanges a refresh token for a fresh access token (the refresh path
    /// used when the stored access token has expired).
    public func generateAccessTokenForApp(refreshToken: String, steamID: String) async throws -> SteamAuthTokens {
        var payload = ProtobufEncoder()
        payload.writeString(1, refreshToken)
        payload.writeFixed64(2, UInt64(steamID) ?? 0)

        let envelope: GenerateAccessTokenEnvelope = try await sendProtobuf(
            payload,
            method: "GenerateAccessTokenForApp"
        )

        guard let response = envelope.response,
              let accessToken = response.accessToken,
              !accessToken.isEmpty else {
            throw SteamAuthError.sessionExpired
        }

        return SteamAuthTokens(
            accessToken: accessToken,
            refreshToken: response.refreshToken,
            accountName: nil,
            newGuardData: nil
        )
    }

    // MARK: - Transport

    private func endpointURL(method: String) throws -> URL {
        // format=json is required: with a protobuf request body Steam would
        // otherwise answer with a binary protobuf payload (application/octet-stream).
        guard let url = URL(string: Self.baseURLString + "/IAuthenticationService/" + method + "/v1/?format=json") else {
            throw SteamAuthError.malformedResponse("could not build the endpoint URL for " + method)
        }
        return url
    }

    /// Sends a protobuf request body and decodes the JSON envelope, mapping the
    /// EResult response header onto typed errors.
    private func sendProtobuf<T: Decodable>(
        _ payload: ProtobufEncoder,
        method: String
    ) async throws -> T {
        let data = try await sendProtobufRaw(payload, method: method)
        return try decodeEnvelope(data, method: method)
    }

    @discardableResult
    private func sendProtobufRaw(_ payload: ProtobufEncoder, method: String) async throws -> Data {
        let boundary = "----SKICEAuthBoundary" + UUID().uuidString
        var body = Data()
        body.append(Data(("--" + boundary + "\r\n").utf8))
        body.append(Data(("Content-Disposition: form-data; name=\"input_protobuf_encoded\"\r\n\r\n").utf8))
        body.append(Data(payload.base64String.utf8))
        body.append(Data(("\r\n--" + boundary + "--\r\n").utf8))

        var request = APIClient.makeRequest(
            url: try endpointURL(method: method),
            method: "POST",
            headers: [
                "Accept": "application/json, text/plain, */*",
                "Content-Type": "multipart/form-data; boundary=" + boundary
            ],
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        request.httpBody = body

        return try await send(request, method: method)
    }

    private func sendJSON<T: Decodable>(_ request: URLRequest, method: String) async throws -> T {
        let data = try await send(request, method: method)
        return try decodeEnvelope(data, method: method)
    }

    private func send(_ request: URLRequest, method: String) async throws -> Data {
        let response: APIResponse
        do {
            response = try await transport.send(request)
        } catch {
            DebugLogger.shared.warning(
                "SteamAuth " + method + " transport failure: " + (error.localizedDescription),
                category: "SteamAuth"
            )
            throw SteamAuthError.transport(error.localizedDescription)
        }

        let eresult = response.headers["x-eresult"].flatMap { Int($0) } ?? 1

        DebugLogger.shared.info(
            "SteamAuth " + method + " responded",
            category: "SteamAuth",
            httpStatusCode: response.statusCode
        )

        guard response.statusCode == 200 else {
            throw SteamAuthError.malformedResponse("HTTP " + String(response.statusCode))
        }

        if eresult != 1 {
            DebugLogger.shared.warning(
                "SteamAuth " + method + " returned EResult " + String(eresult),
                category: "SteamAuth",
                httpStatusCode: response.statusCode
            )
            throw Self.mapEResult(eresult)
        }

        guard !response.data.isEmpty else {
            DebugLogger.shared.error(
                "SteamAuth " + method + " returned an empty body for a successful EResult",
                category: "SteamAuth"
            )
            throw SteamAuthError.malformedResponse("empty body for EResult 1")
        }

        return response.data
    }

    private func decodeEnvelope<T: Decodable>(_ data: Data, method: String) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            DebugLogger.shared.error(
                "SteamAuth " + method + " response decode failed: " + error.localizedDescription,
                category: "SteamAuth"
            )
            throw SteamAuthError.malformedResponse("could not decode the " + method + " response")
        }
    }

    private static func mapEResult(_ code: Int) -> SteamAuthError {
        switch code {
        case 5: return .invalidCredentials
        case 18: return .accountNotFound
        case 25, 86: return .rateLimited
        case 65, 87, 88: return .invalidGuardCode
        case 71: return .guardCodeExpired
        case 26, 27: return .sessionExpired
        case 43: return .accountDisabled
        case 10, 20: return .serverUnavailable
        default: return .unexpectedResult(code)
        }
    }
}

// MARK: - Wire models

/// Decodes a uint64 that Steam may render either as a JSON number or a string.
public struct SteamUInt64: Decodable, Sendable {
    public let value: UInt64

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(UInt64.self) {
            value = number
        } else if let text = try? container.decode(String.self) {
            value = UInt64(text) ?? 0
        } else {
            value = 0
        }
    }
}

public struct SteamRSAPublicKey: Sendable, Equatable {
    public let modulusHex: String
    public let exponentHex: String
    public let timestamp: UInt64

    public init(modulusHex: String, exponentHex: String, timestamp: UInt64) {
        self.modulusHex = modulusHex
        self.exponentHex = exponentHex
        self.timestamp = timestamp
    }
}

struct PasswordRSAPublicKeyEnvelope: Decodable, Sendable {
    struct Payload: Decodable, Sendable {
        let publickeyMod: String
        let publickeyExp: String
        let timestamp: UInt64

        enum CodingKeys: String, CodingKey {
            case publickeyMod = "publickey_mod"
            case publickeyExp = "publickey_exp"
            case timestamp
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            publickeyMod = try container.decode(String.self, forKey: .publickeyMod)
            publickeyExp = try container.decode(String.self, forKey: .publickeyExp)
            timestamp = (try? container.decode(SteamUInt64.self, forKey: .timestamp))?.value ?? 0
        }
    }
    let response: Payload?
}

struct BeginAuthSessionEnvelope: Decodable, Sendable {
    struct Confirmation: Decodable, Sendable {
        let confirmationType: Int
        let associatedMessage: String?

        enum CodingKeys: String, CodingKey {
            case confirmationType = "confirmation_type"
            case associatedMessage = "associated_message"
        }
    }

    struct Payload: Decodable, Sendable {
        let clientID: UInt64
        let requestID: String
        let interval: Float?
        let allowedConfirmations: [Confirmation]
        let steamID: String?

        enum CodingKeys: String, CodingKey {
            case clientID = "client_id"
            case requestID = "request_id"
            case interval
            case allowedConfirmations = "allowed_confirmations"
            case steamID = "steamid"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            clientID = try container.decode(SteamUInt64.self, forKey: .clientID).value
            requestID = (try? container.decode(String.self, forKey: .requestID)) ?? ""
            interval = try? container.decode(Float.self, forKey: .interval)
            allowedConfirmations = (try? container.decode([Confirmation].self, forKey: .allowedConfirmations)) ?? []
            if let raw = try? container.decode(SteamUInt64.self, forKey: .steamID), raw.value != 0 {
                steamID = String(raw.value)
            } else {
                steamID = nil
            }
        }
    }
    let response: Payload?
}

struct PollAuthSessionStatusEnvelope: Decodable, Sendable {
    struct Payload: Decodable, Sendable {
        let refreshToken: String?
        let accessToken: String?
        let accountName: String?
        let newGuardData: String?

        enum CodingKeys: String, CodingKey {
            case refreshToken = "refresh_token"
            case accessToken = "access_token"
            case accountName = "account_name"
            case newGuardData = "new_guard_data"
        }
    }
    let response: Payload?
}

struct GenerateAccessTokenEnvelope: Decodable, Sendable {
    struct Payload: Decodable, Sendable {
        let accessToken: String?
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
        }
    }
    let response: Payload?
}

struct BeginAuthSessionViaQREnvelope: Decodable, Sendable {
    struct Payload: Decodable, Sendable {
        let clientID: UInt64
        let requestID: String
        let interval: Float?
        let allowedConfirmations: [BeginAuthSessionEnvelope.Confirmation]
        let challengeURL: String?

        enum CodingKeys: String, CodingKey {
            case clientID = "client_id"
            case requestID = "request_id"
            case interval
            case allowedConfirmations = "allowed_confirmations"
            case challengeURL = "challenge_url"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            clientID = try container.decode(SteamUInt64.self, forKey: .clientID).value
            requestID = (try? container.decode(String.self, forKey: .requestID)) ?? ""
            interval = try? container.decode(Float.self, forKey: .interval)
            allowedConfirmations = (try? container.decode([BeginAuthSessionEnvelope.Confirmation].self, forKey: .allowedConfirmations)) ?? []
            challengeURL = try? container.decode(String.self, forKey: .challengeURL)
        }
    }
    let response: Payload?
}

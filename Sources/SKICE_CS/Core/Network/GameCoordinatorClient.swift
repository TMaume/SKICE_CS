import Foundation
import CryptoKit
import zlib

/// Errors surfaced by the Game Coordinator client.
public enum GameCoordinatorError: LocalizedError, Sendable {
    case notSignedIn
    case invalidSteamID
    case noCMReachable
    case logonDenied(Int32)
    case malformedResponse(String)
    case disconnected(String)
    case connectionClosed
    case signedInElsewhere
    case timeout

    public var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in to Steam first to read your loadout."
        case .invalidSteamID:
            return "The Steam session has no valid SteamID64."
        case .noCMReachable:
            return "Steam returned no reachable connection server."
        case .logonDenied(let code):
            return "Steam rejected the Game Coordinator logon (EResult \(code))."
        case .malformedResponse(let detail):
            return "Unexpected Game Coordinator response: \(detail)"
        case .disconnected(let detail):
            return "Lost connection to the Game Coordinator: \(detail)"
        case .connectionClosed:
            return "The Game Coordinator closed the connection."
        case .signedInElsewhere:
            return "Steam signed this app out because your account is signed in on another device. Close Steam on your other devices, then try again."
        case .timeout:
            return "The Game Coordinator did not answer in time."
        }
    }
}

// MARK: - Extensive GC logging

/// Logs a verbose Game Coordinator diagnostic only when "Extensive GC Logging"
/// is enabled (Settings > Developer). Errors and warnings always log; this gate
/// keeps the debug console from being flooded by wire frames and decode traces.
func gcInfo(_ message: String) {
    guard DebugLogger.extensiveGCLoggingEnabled else { return }
    DebugLogger.shared.info(message, category: "GameCoordinator")
}

// MARK: - Little-endian framing helpers

extension Data {
    func readUInt32LE(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        var value: UInt32 = 0
        for i in 0..<4 {
            value |= UInt32(self[offset + i]) << (8 * i)
        }
        return value
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var v = value
        for _ in 0..<4 {
            append(UInt8(v & 0xFF))
            v >>= 8
        }
    }

    /// Hex dump of the first N bytes, for wire-level diagnostics.
    func hexPrefix(_ limit: Int = 96) -> String {
        let bytes = prefix(limit)
        let hex = bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
        let suffix = count > limit ? "… (\(count) bytes)" : " (\(count) bytes)"
        return hex + suffix
    }
}

/// Logs the WebSocket connection lifecycle so failures are visible in the
/// in-app debug console (connection opened / closed / failed with reason).
final class GCWebSocketSessionDelegate: NSObject, URLSessionWebSocketDelegate {
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        gcInfo("GC WebSocket opened")
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let reasonText = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "nil"
        gcInfo(
            "GC WebSocket closed: code=\(closeCode.rawValue) reason=\(reasonText)"
        )
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            DebugLogger.shared.error(
                "GC WebSocket task failed: \(error.localizedDescription) (\(error))",
                category: "GameCoordinator"
            )
        }
    }
}

/// Game Coordinator client: connects to a Steam CM over WebSocket, logs on with
/// the stored refresh token, and reads the player's CS2 loadout.
///
/// Read-only by design (ROADMAP section 0.2): it only ever sends the logon,
/// heartbeat, "now playing", and GC hello messages, and never writes to or
/// injects into the game. Framing follows node-steam-user's CM WebSocket
/// protocol: a 32-bit EMsg (with the 0x80000000 protobuf bit set), a 32-bit
/// header length, then the CMsgProtoBufHeader and body protobufs.
public actor GameCoordinatorClient {
    public static let shared = GameCoordinatorClient()

    // EMsg values (verified against node-steam-user enums/EMsg.js and Valve's
    // SteamDatabase/Protobufs).
    private static let protoMask: UInt32 = 0x8000_0000
    private static let emsgClientLogon: UInt32 = 5514
    private static let emsgClientLogOnResponse: UInt32 = 751
    private static let emsgClientLoggedOff: UInt32 = 757
    private static let emsgClientHeartBeat: UInt32 = 703
    private static let emsgClientGamesPlayed: UInt32 = 742
    private static let emsgClientToGC: UInt32 = 5452
    private static let emsgClientFromGC: UInt32 = 5453
    private static let emsgGCClientHello: UInt32 = 4006
    private static let emsgGCClientWelcome: UInt32 = 4004
    private static let emsgMatchmakingClient2GCHello: UInt32 = 9109
    private static let emsgMatchmakingGC2ClientHello: UInt32 = 9110
    private static let emsgClientRequestPlayersProfile: UInt32 = 9127
    private static let emsgPlayersProfile: UInt32 = 9128
    private static let emsgMulti: UInt32 = 1

    private static let cs2AppID: UInt32 = 730
    private static let protocolVersion: UInt64 = 65580
    /// EOSType.IOSUnknown, written sign-extended into the uint32 client_os_type
    /// field (the same encoding node-steam-user produces for negative EOSType
    /// values).
    private static let clientOSType: Int32 = -600

    private var socket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var sessionDelegate: GCWebSocketSessionDelegate?
    private var heartbeatTask: Task<Void, Never>?
    private var currentSteamID: UInt64 = 0
    private var currentSessionID: Int32 = 0
    /// Frames received but not yet consumed by a stage. Survives across stages
    /// so a batched CM reply is never dropped when a stage returns early.
    private var frameBuffer: [(emsg: UInt32, header: Data, body: Data)] = []

    public init() {}

    // MARK: - Public

    public func fetchItemInspections(steamID64: UInt64, refreshToken: String) async throws -> [GCItemInspection] {
        defer { teardown() }
        currentSteamID = steamID64
        currentSessionID = 0

        gcInfo("GC start: steamID64=\(steamID64)")
        Self.logTokenClaims(refreshToken)

        let endpoint = try await Self.fetchCMWebSocketEndpoint()
        gcInfo("GC using CM endpoint \(endpoint)")
        guard let url = URL(string: "wss://" + endpoint + "/cmsocket/") else {
            throw GameCoordinatorError.noCMReachable
        }

        let delegate = GCWebSocketSessionDelegate()
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 30
        let urlSession = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        sessionDelegate = delegate
        session = urlSession

        let ws = urlSession.webSocketTask(with: url)
        socket = ws
        ws.resume()

        gcInfo("GC sending ClientLogon")
        try await sendLogon(refreshToken: refreshToken)
        gcInfo("GC ClientLogon sent")
        let heartbeatSeconds = try await awaitLogonResponse()
        startHeartbeat(interval: max(heartbeatSeconds, 10))

        try await sendGamesPlayed()
        try await sendGCHello()

        gcInfo("GC awaiting ClientWelcome")
        return try await awaitWelcomeAndDecode()
    }

    /// Connects, logs on, then requests and decodes the player's ranked ladders
    /// (Premier / competitive / wingman). Read-only: it only sends the logon,
    /// heartbeat, now-playing, hello, and matchmaking-hello messages.
    public func fetchPlayerRanking(steamID64: UInt64, refreshToken: String) async throws -> [PlayerRankingInfo] {
        defer { teardown() }
        currentSteamID = steamID64
        currentSessionID = 0

        gcInfo("GC ranking start: steamID64=\(steamID64)")
        Self.logTokenClaims(refreshToken)

        let endpoint = try await Self.fetchCMWebSocketEndpoint()
        gcInfo("GC ranking using CM endpoint \(endpoint)")
        guard let url = URL(string: "wss://" + endpoint + "/cmsocket/") else {
            throw GameCoordinatorError.noCMReachable
        }

        let delegate = GCWebSocketSessionDelegate()
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 30
        let urlSession = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        sessionDelegate = delegate
        session = urlSession

        let ws = urlSession.webSocketTask(with: url)
        socket = ws
        ws.resume()

        gcInfo("GC ranking sending ClientLogon")
        try await sendLogon(refreshToken: refreshToken)
        let heartbeatSeconds = try await awaitLogonResponse()
        startHeartbeat(interval: max(heartbeatSeconds, 10))

        try await sendGamesPlayed()
        try await sendGCHello()
        try await sendMatchmakingClient2GCHello()
        try await sendClientRequestPlayersProfile(accountID: UInt32(truncatingIfNeeded: steamID64))

        gcInfo("GC ranking awaiting ranking message")
        return try await awaitRankingAndDecode()
    }

    // MARK: - Token diagnostics

    /// Logs the JWT claims of the refresh token (sub, aud, exp) without ever
    /// logging the token value itself. This diagnoses audience mismatches, which
    /// are the usual reason a refresh token is rejected at GC logon.
    private static func logTokenClaims(_ token: String) {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else {
            DebugLogger.shared.warning("GC refresh token is not a JWT (parts=\(parts.count))", category: "GameCoordinator")
            return
        }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload.append("=") }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            DebugLogger.shared.warning("GC could not decode refresh token claims", category: "GameCoordinator")
            return
        }
        let sub = json["sub"] ?? "nil"
        let aud = json["aud"] ?? "nil"
        let exp = json["exp"] ?? "nil"
        let iss = json["iss"] ?? "nil"
        gcInfo("GC token claims: iss=\(iss) sub=\(sub) aud=\(aud) exp=\(exp)")
    }

    // MARK: - Send helpers

    private static func header(steamID64: UInt64, sessionID: Int32, routingAppID: UInt32? = nil) -> ProtobufEncoder {
        var header = ProtobufEncoder()
        header.writeFixed64(1, steamID64)                    // steamid
        header.writeInt32(2, sessionID)                      // client_sessionid
        if let routingAppID {
            header.writeUInt64(3, UInt64(routingAppID))      // routing_appid
        }
        return header
    }

    private func send(_ emsg: UInt32, header: ProtobufEncoder, body: ProtobufEncoder) async throws {
        guard let socket else { throw GameCoordinatorError.disconnected("not connected") }
        var frame = Data()
        frame.appendUInt32LE(emsg | Self.protoMask)
        frame.appendUInt32LE(UInt32(header.data.count))
        frame.append(header.data)
        frame.append(body.data)
        gcInfo("GC send emsg=\(emsg) frame=\(frame.hexPrefix())")
        do {
            try await socket.send(.data(frame))
        } catch {
            DebugLogger.shared.error("GC send failed emsg=\(emsg): \(error.localizedDescription) (\(error))", category: "GameCoordinator")
            throw error
        }
    }

    private func sendLogon(refreshToken: String) async throws {
        var body = ProtobufEncoder()
        body.writeUInt64(1, Self.protocolVersion)            // protocol_version
        body.writeString(6, "english")                       // client_language
        body.writeInt32(7, Self.clientOSType)                // client_os_type
        body.writeBool(8, true)                              // should_remember_password
        body.writeFixed64(22, currentSteamID)                // client_supplied_steam_id
        body.writeBytes(30, Self.machineID())                // machine_id
        body.writeString(108, refreshToken)                  // access_token (Steam refresh token)
        try await send(
            Self.emsgClientLogon,
            header: Self.header(steamID64: currentSteamID, sessionID: currentSessionID),
            body: body
        )
    }

    private func sendGamesPlayed() async throws {
        var game = ProtobufEncoder()
        game.writeFixed64(2, UInt64(Self.cs2AppID))          // GamePlayed.game_id
        var body = ProtobufEncoder()
        body.writeMessage(1, game)                           // games_played
        try await send(
            Self.emsgClientGamesPlayed,
            header: Self.header(steamID64: currentSteamID, sessionID: currentSessionID),
            body: body
        )
    }

    private func sendGCHello() async throws {
        var hello = ProtobufEncoder()
        hello.writeUInt64(1, 2_000_244)                      // version
        hello.writeUInt64(4, 0)                              // client_launcher
        hello.writeUInt64(9, 0)                              // steam_launcher

        // Inner framed GC payload: [uint32 msgtype|mask][uint32 headerLen=0][body]
        var inner = Data()
        inner.appendUInt32LE(Self.emsgGCClientHello | Self.protoMask)
        inner.appendUInt32LE(0)
        inner.append(hello.data)

        var gcMessage = ProtobufEncoder()
        gcMessage.writeUInt64(1, UInt64(Self.cs2AppID))                       // appid
        gcMessage.writeUInt64(2, UInt64(Self.emsgGCClientHello | Self.protoMask)) // msgtype
        gcMessage.writeBytes(3, inner)                                        // payload

        try await send(
            Self.emsgClientToGC,
            header: Self.header(steamID64: currentSteamID, sessionID: currentSessionID, routingAppID: Self.cs2AppID),
            body: gcMessage
        )
    }

    /// Sends the empty CMsgGCCStrike15_v2_MatchmakingClient2GCHello, which asks
    /// the GC for the player's account data (ranking). The GC answers with
    /// MatchmakingGC2ClientHello (9110).
    private func sendMatchmakingClient2GCHello() async throws {
        // Inner framed GC payload: [uint32 msgtype|mask][uint32 headerLen=0][empty body]
        var inner = Data()
        inner.appendUInt32LE(Self.emsgMatchmakingClient2GCHello | Self.protoMask)
        inner.appendUInt32LE(0)

        var gcMessage = ProtobufEncoder()
        gcMessage.writeUInt64(1, UInt64(Self.cs2AppID))
        gcMessage.writeUInt64(2, UInt64(Self.emsgMatchmakingClient2GCHello | Self.protoMask))
        gcMessage.writeBytes(3, inner)

        try await send(
            Self.emsgClientToGC,
            header: Self.header(steamID64: currentSteamID, sessionID: currentSessionID, routingAppID: Self.cs2AppID),
            body: gcMessage
        )
    }

    /// Asks the GC for a player profile; the reply (PlayersProfile, 9128) carries
    /// the ranked ladders. account_id is the low 32 bits of the SteamID64 and
    /// request_level mirrors the reference client (node-globaloffensive: 32).
    private func sendClientRequestPlayersProfile(accountID: UInt32) async throws {
        var body = ProtobufEncoder()
        body.writeUInt64(3, UInt64(accountID))   // account_id
        body.writeUInt64(4, 32)                  // request_level

        var inner = Data()
        inner.appendUInt32LE(Self.emsgClientRequestPlayersProfile | Self.protoMask)
        inner.appendUInt32LE(0)
        inner.append(body.data)

        var gcMessage = ProtobufEncoder()
        gcMessage.writeUInt64(1, UInt64(Self.cs2AppID))
        gcMessage.writeUInt64(2, UInt64(Self.emsgClientRequestPlayersProfile | Self.protoMask))
        gcMessage.writeBytes(3, inner)

        try await send(
            Self.emsgClientToGC,
            header: Self.header(steamID64: currentSteamID, sessionID: currentSessionID, routingAppID: Self.cs2AppID),
            body: gcMessage
        )
    }

    private func sendHeartbeat() async {
        var body = ProtobufEncoder()
        body.writeBool(1, true)                              // send_reply
        try? await send(
            Self.emsgClientHeartBeat,
            header: Self.header(steamID64: currentSteamID, sessionID: currentSessionID),
            body: body
        )
    }

    // MARK: - Receive / decode

    /// Receives one WebSocket message and expands it. The CM wraps replies in
    /// EMsg 1 (k_EMsgMulti) envelopes whose message_body holds one or more
    /// length-prefixed sub-frames; those are flattened here so callers just see
    /// ordinary (emsg, header, body) frames.
    private func receiveFrames(timeout: TimeInterval) async throws -> [(emsg: UInt32, header: Data, body: Data)] {
        guard let socket else { throw GameCoordinatorError.disconnected("not connected") }
        let data = try await Self.receive(socket, timeout: timeout)
        gcInfo("GC recv \(data.hexPrefix())")
        let frames = Self.expandFrames(data)
        for frame in frames {
            gcInfo("GC frame emsg=\(frame.emsg) headerLen=\(frame.header.count) bodyLen=\(frame.body.count)")
        }
        return frames
    }

    /// Parses a single framed message into (emsg, header, body).
    private static func parseFrame(_ data: Data) -> (emsg: UInt32, header: Data, body: Data)? {
        guard let rawEMsg = data.readUInt32LE(at: 0),
              let headerLen = data.readUInt32LE(at: 4) else { return nil }
        let emsg = rawEMsg & ~protoMask
        let headerStart = 8
        let bodyStart = headerStart + Int(headerLen)
        guard bodyStart <= data.count else { return nil }
        let header = data.subdata(in: headerStart..<bodyStart)
        let body = data.subdata(in: bodyStart..<data.count)
        return (emsg, header, body)
    }

    /// Expands a received message. Non-Multi messages pass through as-is; a
    /// k_EMsgMulti envelope is decoded, optionally gunzipped, and split into its
    /// length-prefixed sub-frames.
    private static func expandFrames(_ data: Data) -> [(emsg: UInt32, header: Data, body: Data)] {
        guard let top = parseFrame(data) else {
            DebugLogger.shared.warning("GC expand: could not parse top frame", category: "GameCoordinator")
            return []
        }
        if top.emsg != emsgMulti { return [top] }

        var decoder = ProtobufDecoder(top.body)
        var sizeUnzipped: UInt64 = 0
        var messageBody = Data()
        while let (field, wire) = decoder.readTag() {
            switch field {
            case 1:
                if wire == 0, let value = decoder.readVarint() { sizeUnzipped = value }
            case 2:
                if wire == 2, let value = decoder.readLengthDelimited() { messageBody = value }
            default:
                decoder.skip(wireType: wire)
            }
        }

        gcInfo("GC multi: sizeUnzipped=\(sizeUnzipped) body=\(messageBody.count) bytes")

        var payload = messageBody
        if sizeUnzipped != 0 {
            if let inflated = gunzip(payload) {
                gcInfo("GC multi gunzipped \(payload.count) -> \(inflated.count) bytes")
                payload = inflated
            } else {
                DebugLogger.shared.warning("GC multi gunzip failed, using raw payload", category: "GameCoordinator")
            }
        }

        var frames: [(emsg: UInt32, header: Data, body: Data)] = []
        var offset = 0
        while offset + 4 <= payload.count {
            guard let subSize = payload.readUInt32LE(at: offset) else { break }
            let start = offset + 4
            let end = start + Int(subSize)
            guard end <= payload.count else {
                DebugLogger.shared.warning("GC multi sub-frame overruns payload at \(offset)", category: "GameCoordinator")
                break
            }
            if let sub = parseFrame(payload.subdata(in: start..<end)) {
                frames.append(sub)
            } else {
                DebugLogger.shared.warning("GC multi sub-frame parse failed at \(offset)", category: "GameCoordinator")
            }
            offset = end
        }
        gcInfo("GC multi yielded \(frames.count) sub-frames")
        return frames
    }

    // MARK: - gzip inflate (zlib)

    /// Decompresses a gzip payload using zlib's built-in gzip support
    /// (windowBits = 15 + 16). This is the reliable path: zlib parses the gzip
    /// header, inflates the DEFLATE stream, and verifies the CRC32 trailer, so
    /// the full size_unzipped payload is recovered.
    private static func gunzip(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }

        var stream = z_stream()
        // 15 (MAX_WBITS) + 16 enables gzip decoding; 47 (32 + 15) also works for
        // auto-detecting gzip vs zlib. We use 15 + 16 = 31 for gzip only.
        let windowBits: Int32 = 15 + 16
        let initStatus = inflateInit2_(&stream, windowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else {
            DebugLogger.shared.warning("GC gunzip inflateInit2 failed: \(initStatus)", category: "GameCoordinator")
            return nil
        }
        defer { inflateEnd(&stream) }

        let chunkSize = 64 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { buffer.deallocate() }

        var output = Data()
        var status: Int32 = Z_OK

        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            stream.next_in = UnsafeMutablePointer(mutating: base)
            stream.avail_in = uInt(raw.count)

            while status != Z_STREAM_END {
                stream.next_out = buffer
                stream.avail_out = uInt(chunkSize)
                status = inflate(&stream, Z_NO_FLUSH)
                let written = chunkSize - Int(stream.avail_out)
                if written > 0 {
                    output.append(buffer, count: written)
                }
                if status != Z_OK && status != Z_STREAM_END {
                    DebugLogger.shared.warning("GC gunzip inflate error: \(status)", category: "GameCoordinator")
                    return
                }
                if written == 0 && stream.avail_in == 0 && status != Z_STREAM_END { break } // no progress
            }
        }

        return output.isEmpty ? nil : output
    }

    private enum ReceiveOutcome { case data(Data); case closed; case timeout }

    private static func receive(_ socket: URLSessionWebSocketTask, timeout: TimeInterval) async throws -> Data {
        let outcome = await withTaskGroup(of: ReceiveOutcome.self) { group -> ReceiveOutcome in
            group.addTask {
                do {
                    // URLSessionWebSocketTask.receive() is not cancellation-aware:
                    // cancelling the Swift task alone leaves it parked, so the task
                    // group would wait forever. Cancel the socket itself so the
                    // receive unblocks when the deadline fires.
                    let message = try await withTaskCancellationHandler {
                        try await socket.receive()
                    } onCancel: {
                        socket.cancel(with: .goingAway, reason: nil)
                    }
                    switch message {
                    case .data(let data): return .data(data)
                    case .string(let text): return .data(Data(text.utf8))
                    @unknown default: return .closed
                    }
                } catch {
                    DebugLogger.shared.error("GC receive error: \(error.localizedDescription) (\(error))", category: "GameCoordinator")
                    return .closed
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return .timeout
            }
            let first = await group.next() ?? .timeout
            group.cancelAll()
            return first
        }
        switch outcome {
        case .data(let data): return data
        case .closed: throw GameCoordinatorError.connectionClosed
        case .timeout: throw GameCoordinatorError.timeout
        }
    }

    /// If the frame is a CMsgClientLoggedOff, returns its EResult; otherwise nil.
    private static func loggedOffResult(_ frame: (emsg: UInt32, header: Data, body: Data)) -> Int32? {
        guard frame.emsg == emsgClientLoggedOff else { return nil }
        var decoder = ProtobufDecoder(frame.body)
        while let (field, wire) = decoder.readTag() {
            if field == 1, let value = decoder.readVarint() {
                return Int32(bitPattern: UInt32(truncatingIfNeeded: value))
            }
            decoder.skip(wireType: wire)
        }
        return nil
    }

    /// Maps a ClientLoggedOff EResult to the right error. EResult 6
    /// (LoggedInElsewhere) means another Steam client took over the session.
    private static func loggedOffError(_ eresult: Int32) -> GameCoordinatorError {
        if eresult == 6 {
            return .signedInElsewhere
        }
        return .disconnected("Steam logged the app off (EResult \(eresult)).")
    }

    /// Reads the client_sessionid the CM assigned, from a CMsgProtoBufHeader.
    private static func sessionID(fromHeader header: Data) -> Int32? {
        var decoder = ProtobufDecoder(header)
        while let (field, wire) = decoder.readTag() {
            if field == 2, let value = decoder.readVarint() {
                return Int32(bitPattern: UInt32(truncatingIfNeeded: value))
            }
            decoder.skip(wireType: wire)
        }
        return nil
    }

    private func awaitLogonResponse() async throws -> Int32 {
        while true {
            for frame in [try await nextFrame(timeout: 15)] {
                if let eresult = Self.loggedOffResult(frame) {
                    gcInfo("GC logged off during logon: EResult \(eresult)")
                    throw Self.loggedOffError(eresult)
                }
                guard frame.emsg == Self.emsgClientLogOnResponse else {
                    gcInfo("GC awaitLogon: skipping emsg=\(frame.emsg)")
                    continue
                }

                if let assigned = Self.sessionID(fromHeader: frame.header) {
                    currentSessionID = assigned
                }

                var decoder = ProtobufDecoder(frame.body)
                var eresult: Int32 = 2
                var heartbeatSeconds: Int32 = 30
                while let (field, wire) = decoder.readTag() {
                    switch field {
                    case 1:
                        if let value = decoder.readVarint() {
                            eresult = Int32(bitPattern: UInt32(truncatingIfNeeded: value))
                        }
                    case 3:
                        if let value = decoder.readVarint() {
                            heartbeatSeconds = Int32(bitPattern: UInt32(truncatingIfNeeded: value))
                        }
                    default:
                        decoder.skip(wireType: wire)
                    }
                }

                gcInfo("GC logon response: EResult \(eresult) heartbeat \(heartbeatSeconds)")
                guard eresult == 1 else { throw GameCoordinatorError.logonDenied(eresult) }
                return heartbeatSeconds
            }
        }
    }

    private func awaitWelcomeAndDecode() async throws -> [GCItemInspection] {
        while true {
            for frame in [try await nextFrame(timeout: 15)] {
                if let eresult = Self.loggedOffResult(frame) {
                    gcInfo("GC logged off during welcome: EResult \(eresult)")
                    throw Self.loggedOffError(eresult)
                }
                guard frame.emsg == Self.emsgClientFromGC else {
                    gcInfo("GC awaitWelcome: skipping emsg=\(frame.emsg)")
                    continue
                }

                var gcDecoder = ProtobufDecoder(frame.body)
                var msgtype: UInt32 = 0
                var payload = Data()
                while let (field, wire) = gcDecoder.readTag() {
                    switch field {
                    case 2:
                        if let value = gcDecoder.readVarint() {
                            msgtype = UInt32(truncatingIfNeeded: value)
                        }
                    case 3:
                        if let value = gcDecoder.readLengthDelimited() { payload = value }
                    default:
                        gcDecoder.skip(wireType: wire)
                    }
                }

                let innerType = msgtype & ~Self.protoMask
                gcInfo("GC ClientFromGC innerType=\(innerType)")
                guard innerType == Self.emsgGCClientWelcome else { continue }

                gcInfo("GC received ClientWelcome")
                guard let headerLen = payload.readUInt32LE(at: 4) else {
                    throw GameCoordinatorError.malformedResponse("GC welcome frame too short")
                }
                let welcomeStart = 8 + Int(headerLen)
                guard welcomeStart <= payload.count else {
                    throw GameCoordinatorError.malformedResponse("GC welcome header overruns payload")
                }
                let welcome = payload.subdata(in: welcomeStart..<payload.count)
                let inspections = GameCoordinatorDecoder.decodeWelcome(welcome)
                gcInfo("GC decoded \(inspections.count) item inspections")
                return inspections
            }
        }
    }

    /// Receives until the GC sends MatchmakingGC2ClientHello (9110), then
    /// decodes the player's ranked ladders from it.
    private func awaitRankingAndDecode() async throws -> [PlayerRankingInfo] {
        let deadline = Date().addingTimeInterval(20)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { break }
            var frames: [(emsg: UInt32, header: Data, body: Data)] = []
            do {
                frames = [try await nextFrame(timeout: min(15, remaining))]
            } catch GameCoordinatorError.timeout {
                break
            }
            for frame in frames {
                if let eresult = Self.loggedOffResult(frame) {
                    gcInfo("GC ranking logged off: EResult \(eresult)")
                    throw Self.loggedOffError(eresult)
                }
                guard frame.emsg == Self.emsgClientFromGC else {
                    gcInfo("GC ranking awaiting: skipping emsg=\(frame.emsg)")
                    continue
                }

                var gcDecoder = ProtobufDecoder(frame.body)
                var msgtype: UInt32 = 0
                var payload = Data()
                while let (field, wire) = gcDecoder.readTag() {
                    switch field {
                    case 2:
                        if let value = gcDecoder.readVarint() {
                            msgtype = UInt32(truncatingIfNeeded: value)
                        }
                    case 3:
                        if let value = gcDecoder.readLengthDelimited() { payload = value }
                    default:
                        gcDecoder.skip(wireType: wire)
                    }
                }

                let innerType = msgtype & ~Self.protoMask
                gcInfo("GC ranking ClientFromGC innerType=\(innerType)")
                guard innerType == Self.emsgMatchmakingGC2ClientHello || innerType == Self.emsgPlayersProfile else { continue }

                guard let headerLen = payload.readUInt32LE(at: 4) else {
                    throw GameCoordinatorError.malformedResponse("GC ranking frame too short")
                }
                let bodyStart = 8 + Int(headerLen)
                guard bodyStart <= payload.count else {
                    throw GameCoordinatorError.malformedResponse("GC ranking header overruns payload")
                }
                let body = payload.subdata(in: bodyStart..<payload.count)
                let rankings: [PlayerRankingInfo]
                if innerType == Self.emsgPlayersProfile {
                    rankings = GameCoordinatorDecoder.decodePlayersProfile(body)
                } else {
                    rankings = GameCoordinatorDecoder.decodeMatchmakingHello(body)
                }
                gcInfo("GC decoded \(rankings.count) ranking entries")
                return rankings
            }
        }
        gcInfo("GC ranking: no ranking message before giving up")
        throw GameCoordinatorError.timeout
    }

    /// Returns the next frame, draining frames buffered by an earlier stage
    /// first. Keeps a batched CM reply from being dropped when a stage (logon,
    /// welcome, ranking) returns as soon as it sees its target message.
    private func nextFrame(timeout: TimeInterval) async throws -> (emsg: UInt32, header: Data, body: Data) {
        while frameBuffer.isEmpty {
            frameBuffer.append(contentsOf: try await receiveFrames(timeout: timeout))
        }
        return frameBuffer.removeFirst()
    }

    // MARK: - Machine ID

    private static let machineIDDefaultsKey = "com.dtl21.SKICEcs.gcMachineID"

    /// A persistent machine ID in the BinaryKV shape node-steam-user produces
    /// (MessageObject with three SHA-1 hashes). Steam's CM expects a machine_id
    /// for non-anonymous logons; we reuse the stored one so the device is stable.
    private static func machineID() -> Data {
        if let existing = UserDefaults.standard.data(forKey: machineIDDefaultsKey), !existing.isEmpty {
            return existing
        }
        let blob = buildMachineID(bb3: UUID().uuidString, ff2: UUID().uuidString, b3: UUID().uuidString)
        UserDefaults.standard.set(blob, forKey: machineIDDefaultsKey)
        return blob
    }

    private static func buildMachineID(bb3: String, ff2: String, b3: String) -> Data {
        func sha1Hex(_ string: String) -> String {
            let digest = Insecure.SHA1.hash(data: Data(string.utf8))
            return digest.map { String(format: "%02x", $0) }.joined()
        }

        var data = Data()
        data.append(0)
        data.append(contentsOf: "MessageObject".utf8); data.append(0)

        data.append(1)
        data.append(contentsOf: "BB3".utf8); data.append(0)
        data.append(contentsOf: sha1Hex(bb3).utf8); data.append(0)

        data.append(1)
        data.append(contentsOf: "FF2".utf8); data.append(0)
        data.append(contentsOf: sha1Hex(ff2).utf8); data.append(0)

        data.append(1)
        data.append(contentsOf: "3B3".utf8); data.append(0)
        data.append(contentsOf: sha1Hex(b3).utf8); data.append(0)

        data.append(8)
        data.append(8)
        return data
    }

    // MARK: - Lifecycle

    private func startHeartbeat(interval: Int32) {
        heartbeatTask?.cancel()
        let seconds = UInt64(max(interval, 10))
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.sendHeartbeat()
            }
        }
    }

    private func teardown() {
        frameBuffer.removeAll()
        heartbeatTask?.cancel()
        heartbeatTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        session?.invalidateAndCancel()
        session = nil
        sessionDelegate = nil
    }

    // MARK: - CM server discovery

    private struct CMListEnvelope: Decodable {
        struct Response: Decodable {
            let serverlist: [CMServer]
        }
        let response: Response?
    }

    private struct CMServer: Decodable {
        let endpoint: String
        let type: String
        let realm: String
    }

    private static let cmListURL = URL(
        string: "https://api.steampowered.com/ISteamDirectory/GetCMListForConnect/v1/?cellid=0&cmtype=websockets"
    )!

    private static let fallbackEndpoints = [
        "cmp1-sea1.steamserver.net:443",
        "cmp2-sea1.steamserver.net:443",
        "cmp1-lax1.steamserver.net:443"
    ]

    private static func fetchCMWebSocketEndpoint() async throws -> String {
        let request = APIClient.makeRequest(url: cmListURL, cachePolicy: .reloadIgnoringLocalCacheData)
        if let response = try? await APIClient.shared.send(request),
           let envelope = try? JSONDecoder().decode(CMListEnvelope.self, from: response.data),
           let list = envelope.response?.serverlist, !list.isEmpty {
            gcInfo("GC CM list: \(list.count) servers")
            let candidates = list.filter {
                $0.type == "websockets" && $0.realm == "steamglobal" && $0.endpoint.hasSuffix(":443")
            }
            if let first = candidates.first { return first.endpoint }
            if let any = list.first(where: { $0.type == "websockets" }) { return any.endpoint }
        } else {
            DebugLogger.shared.warning("GC CM list fetch failed, using fallback", category: "GameCoordinator")
        }
        if let fallback = fallbackEndpoints.first { return fallback }
        throw GameCoordinatorError.noCMReachable
    }
}

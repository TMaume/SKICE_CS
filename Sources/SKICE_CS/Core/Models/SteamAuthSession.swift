import Foundation
import Observation

/// Coarse authentication state other modules can consume. Game Coordinator
/// features (roadmap M2) are expected to gate on this instead of talking to
/// Steam's login endpoints themselves.
public enum SteamAuthState: String, Sendable, Equatable {
    case signedOut
    case authenticating
    case awaitingGuardCode
    case awaitingRemoteApproval
    case signedIn
    case expired
    case failed
}

/// Observable owner of the Tier B Steam session.
///
/// It drives the login flow (credentials -> Steam Guard -> tokens), keeps the
/// tokens in the Keychain through SteamAuthTokenStore, and publishes the auth
/// state. It never sends credentials or tokens anywhere except Steam itself.
@Observable
@MainActor
public final class SteamAuthSession {
    // MARK: - Published state

    public private(set) var state: SteamAuthState = .signedOut
    public private(set) var guardOptions: [SteamGuardConfirmation] = []
    public private(set) var statusMessage: String?
    public private(set) var errorMessage: String?
    public private(set) var isBusy: Bool = false
    public private(set) var sessionSteamID64: String?
    public private(set) var accountName: String?
    public private(set) var accessTokenExpiry: Date?

    // MARK: - Dependencies

    private let client: SteamAuthClient
    private let store: SteamAuthTokenStore
    private var pollTask: Task<Void, Never>?
    private var pendingChallenge: SteamAuthChallenge?

    /// How long to keep polling for a remote (mobile app) approval.
    private let pollTimeout: TimeInterval = 300

    public init(client: SteamAuthClient = .shared, store: SteamAuthTokenStore = .shared) {
        self.client = client
        self.store = store
        reloadPersistedState()
    }

    // MARK: - Derived state

    public var isSignedIn: Bool {
        state == .signedIn
    }

    /// True when the flow is waiting for the user to type a Steam Guard code.
    public var isAwaitingGuardCode: Bool {
        state == .awaitingGuardCode
    }

    /// Guard options that accept a typed code.
    public var codeGuardOptions: [SteamGuardConfirmation] {
        guardOptions.filter { $0.kind.requiresCodeEntry }
    }

    public var hasPersistedRefreshToken: Bool {
        store.hasPersistedSession
    }

    /// Human-readable summary of the session for UI and for other modules.
    public var stateSummary: String {
        switch state {
        case .signedOut: return "Signed out"
        case .authenticating: return "Signing in…"
        case .awaitingGuardCode: return "Steam Guard code required"
        case .awaitingRemoteApproval: return "Approve in the Steam app"
        case .signedIn: return "Signed in"
        case .expired: return "Session expired"
        case .failed: return "Sign-in failed"
        }
    }

    // MARK: - Persistence

    /// Rebuilds the published state from the Keychain (called at launch).
    public func reloadPersistedState() {
        sessionSteamID64 = store.sessionSteamID64
        accountName = store.accountName
        accessTokenExpiry = store.accessTokenExpiry

        guard store.hasPersistedSession else {
            state = .signedOut
            return
        }

        if store.accessToken != nil && !store.isAccessTokenExpired {
            state = .signedIn
        } else {
            // A refresh token is present: the session can be revived, but the
            // access token itself is stale.
            state = .expired
        }
    }

    // MARK: - Sign in

    /// Runs the credentials login. Ends either signed in, waiting for a guard,
    /// or in an explicit error state.
    public func signIn(
        accountName: String,
        password: String,
        platformType: SteamTokenPlatformType = .steamClient
    ) async {
        let account = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.isEmpty, !password.isEmpty else {
            fail(with: "Enter both your Steam account name and password.")
            return
        }

        cancelPolling()
        errorMessage = nil
        statusMessage = nil
        state = .authenticating
        isBusy = true
        defer { isBusy = false }

        DebugLogger.shared.info("SteamAuth starting a credentials session", category: "SteamAuth")

        do {
            let outcome = try await client.beginAuthSession(
                accountName: account,
                password: password,
                platformType: platformType,
                guardData: store.storedGuardData
            )

            switch outcome {
            case .guardRequired(let challenge):
                pendingChallenge = challenge
                guardOptions = challenge.confirmations
                applyGuardState(for: challenge)
            case .authorized(let tokens):
                try persist(tokens: tokens, challenge: nil)
            }
        } catch {
            fail(with: error.localizedDescription)
        }
    }

    private func applyGuardState(for challenge: SteamAuthChallenge) {
        if challenge.confirmations.contains(where: { $0.kind.requiresCodeEntry }) {
            state = .awaitingGuardCode
            statusMessage = "Steam sent a Steam Guard code. Enter it to finish signing in."
            DebugLogger.shared.info("SteamAuth waiting for a Steam Guard code", category: "SteamAuth")
            return
        }

        if challenge.confirmations.contains(where: { $0.kind.isRemoteApproval }) {
            state = .awaitingRemoteApproval
            statusMessage = "Approve this sign-in in the Steam mobile app."
            DebugLogger.shared.info("SteamAuth waiting for a mobile app approval", category: "SteamAuth")
            startPolling()
            return
        }

        if challenge.confirmations.allSatisfy({ $0.kind.isSatisfiedAutomatically }) {
            startPolling()
            return
        }

        state = .awaitingGuardCode
        statusMessage = "Steam asked for a guard this app does not support. Try the Steam mobile app."
    }

    /// Submits a typed Steam Guard code, then waits for the tokens.
    public func submitGuardCode(_ code: String, kind: SteamGuardKind? = nil) async {
        guard let challenge = pendingChallenge else {
            fail(with: "No pending Steam sign-in. Start again.")
            return
        }

        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Enter the Steam Guard code."
            return
        }

        let resolvedKind = kind
            ?? codeGuardOptions.first?.kind
            ?? .emailCode

        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            try await client.submitGuardCode(challenge: challenge, code: trimmed, kind: resolvedKind)
            DebugLogger.shared.info("SteamAuth submitted a Steam Guard code", category: "SteamAuth")
            statusMessage = "Code accepted. Waiting for Steam to release the session…"
            state = .awaitingRemoteApproval
            startPolling()
        } catch {
            fail(with: error.localizedDescription)
        }
    }

    // MARK: - Polling

    private func startPolling() {
        cancelPolling()
        guard let challenge = pendingChallenge else { return }

        pollTask = Task { [weak self] in
            guard let self else { return }
            let deadline = Date().addingTimeInterval(self.pollTimeout)

            while !Task.isCancelled && Date() < deadline {
                let interval = challenge.pollInterval
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { return }

                do {
                    if let tokens = try await self.client.pollAuthSessionStatus(challenge: challenge) {
                        try self.persist(tokens: tokens, challenge: challenge)
                        return
                    }
                } catch let authError as SteamAuthError {
                    if case .sessionExpired = authError {
                        self.fail(with: authError.localizedDescription)
                        return
                    }
                    DebugLogger.shared.warning(
                        "SteamAuth poll error: " + authError.localizedDescription,
                        category: "SteamAuth"
                    )
                } catch {
                    DebugLogger.shared.warning(
                        "SteamAuth poll error: " + error.localizedDescription,
                        category: "SteamAuth"
                    )
                }
            }

            if !Task.isCancelled {
                self.fail(with: "Steam did not confirm the sign-in in time. Try again.")
            }
        }
    }

    private func cancelPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Tokens

    private func persist(tokens: SteamAuthTokens, challenge: SteamAuthChallenge?) throws {
        let steamID = challenge?.steamID ?? store.sessionSteamID64
        try store.save(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            steamID64: steamID,
            accountName: tokens.accountName ?? store.accountName,
            guardData: tokens.newGuardData.flatMap { Data($0.utf8) }
        )

        pendingChallenge = nil
        guardOptions = []
        cancelPolling()
        reloadPersistedState()

        state = .signedIn
        statusMessage = store.hasPersistedSession
            ? "Steam session stored in the local Keychain."
            : "Signed in, but Steam returned no refresh token: the session will not survive an access-token expiry."
        errorMessage = nil

        DebugLogger.shared.info(
            "SteamAuth session established (refresh token stored: " + (store.hasPersistedSession ? "yes" : "no") + ")",
            category: "SteamAuth"
        )
    }

    /// Mints a new access token from the stored refresh token when the current
    /// one is missing or expired. Later GC work calls this before connecting.
    @discardableResult
    public func ensureFreshAccessToken() async -> Bool {
        guard store.hasPersistedSession else {
            state = .signedOut
            return false
        }
        guard store.isAccessTokenExpired else {
            reloadPersistedState()
            return store.accessToken != nil
        }
        guard let refreshToken = store.refreshToken, let steamID = store.sessionSteamID64 else {
            state = .expired
            return false
        }

        isBusy = true
        defer { isBusy = false }

        do {
            let tokens = try await client.generateAccessTokenForApp(refreshToken: refreshToken, steamID: steamID)
            try store.save(
                accessToken: tokens.accessToken,
                refreshToken: tokens.refreshToken,
                steamID64: steamID,
                accountName: store.accountName,
                guardData: nil
            )
            reloadPersistedState()
            state = .signedIn
            DebugLogger.shared.info("SteamAuth refreshed the access token", category: "SteamAuth")
            return true
        } catch {
            fail(with: error.localizedDescription)
            return false
        }
    }

    // MARK: - Sign out

    /// Drops the local session. Only local state is touched: the refresh token
    /// is simply forgotten by this device.
    public func signOut() {
        cancelPolling()
        do {
            try store.clear()
            DebugLogger.shared.warning("SteamAuth cleared the stored Steam session", category: "SteamAuth")
        } catch {
            DebugLogger.shared.error(
                "SteamAuth could not clear the stored session: " + error.localizedDescription,
                category: "SteamAuth"
            )
        }

        pendingChallenge = nil
        guardOptions = []
        statusMessage = "Signed out. The stored Steam tokens were removed from the Keychain."
        errorMessage = nil
        reloadPersistedState()
        state = .signedOut
    }

    /// Abandons a pending attempt without touching stored tokens.
    public func cancelPendingSignIn() {
        cancelPolling()
        pendingChallenge = nil
        guardOptions = []
        statusMessage = nil
        errorMessage = nil
        reloadPersistedState()
    }

    // MARK: - Helpers

    private func fail(with message: String) {
        cancelPolling()
        errorMessage = message
        statusMessage = nil
        state = store.hasPersistedSession ? .expired : .failed
        DebugLogger.shared.error("SteamAuth failure: " + message, category: "SteamAuth")
    }
}

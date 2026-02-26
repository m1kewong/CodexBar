import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct iOSCodexOAuthCredentials: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let idToken: String?
    public let accountID: String?
    public let lastRefresh: Date?

    public init(
        accessToken: String,
        refreshToken: String,
        idToken: String?,
        accountID: String?,
        lastRefresh: Date?)
    {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.accountID = accountID
        self.lastRefresh = lastRefresh
    }

    public var needsRefresh: Bool {
        guard let lastRefresh else { return true }
        let eightDays: TimeInterval = 8 * 24 * 60 * 60
        return Date().timeIntervalSince(lastRefresh) > eightDays
    }
}

public struct iOSCodexUsageResponse: Decodable, Sendable {
    public let planType: PlanType?
    public let rateLimit: RateLimitDetails?
    public let credits: CreditDetails?

    private enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case credits
    }

    public enum PlanType: Sendable, Decodable, Equatable {
        case guest
        case free
        case go
        case plus
        case pro
        case freeWorkspace
        case team
        case business
        case education
        case quorum
        case k12
        case enterprise
        case edu
        case unknown(String)

        public var rawValue: String {
            switch self {
            case .guest: "guest"
            case .free: "free"
            case .go: "go"
            case .plus: "plus"
            case .pro: "pro"
            case .freeWorkspace: "free_workspace"
            case .team: "team"
            case .business: "business"
            case .education: "education"
            case .quorum: "quorum"
            case .k12: "k12"
            case .enterprise: "enterprise"
            case .edu: "edu"
            case let .unknown(value): value
            }
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            switch value {
            case "guest": self = .guest
            case "free": self = .free
            case "go": self = .go
            case "plus": self = .plus
            case "pro": self = .pro
            case "free_workspace": self = .freeWorkspace
            case "team": self = .team
            case "business": self = .business
            case "education": self = .education
            case "quorum": self = .quorum
            case "k12": self = .k12
            case "enterprise": self = .enterprise
            case "edu": self = .edu
            default:
                self = .unknown(value)
            }
        }
    }

    public struct RateLimitDetails: Decodable, Sendable {
        public let primaryWindow: WindowSnapshot?
        public let secondaryWindow: WindowSnapshot?

        private enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    public struct WindowSnapshot: Decodable, Sendable {
        public let usedPercent: Int
        public let resetAt: Int
        public let limitWindowSeconds: Int

        private enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAt = "reset_at"
            case limitWindowSeconds = "limit_window_seconds"
        }
    }

    public struct CreditDetails: Decodable, Sendable {
        public let hasCredits: Bool
        public let unlimited: Bool
        public let balance: Double?

        private enum CodingKeys: String, CodingKey {
            case hasCredits = "has_credits"
            case unlimited
            case balance
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.hasCredits = (try? container.decode(Bool.self, forKey: .hasCredits)) ?? false
            self.unlimited = (try? container.decode(Bool.self, forKey: .unlimited)) ?? false
            if let balance = try? container.decode(Double.self, forKey: .balance) {
                self.balance = balance
            } else if let balance = try? container.decode(String.self, forKey: .balance),
                      let value = Double(balance)
            {
                self.balance = value
            } else {
                self.balance = nil
            }
        }
    }
}

public enum iOSCodexOAuthFetchError: LocalizedError, Sendable {
    case unauthorized
    case invalidResponse
    case serverError(Int, String?)
    case networkError(Error)

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Codex OAuth token expired or invalid. Please sign in again."
        case .invalidResponse:
            return "Invalid response from Codex usage API."
        case let .serverError(code, message):
            if let message, !message.isEmpty {
                return "Codex API error \(code): \(message)"
            }
            return "Codex API error \(code)."
        case let .networkError(error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

public enum iOSCodexDeviceAuthError: LocalizedError, Sendable {
    case invalidResponse
    case serverError(statusCode: Int, message: String?)
    case networkError(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Codex auth endpoint."
        case let .serverError(statusCode, message):
            let suffix = message?.nilIfEmpty.map { ": \($0)" } ?? "."
            switch statusCode {
            case 401, 403:
                return "Codex device sign-in was rejected (HTTP \(statusCode))\(suffix) Check VPN/ad blocker/Private Relay and try again."
            case 429:
                return "Codex device sign-in is rate-limited (HTTP 429). Please wait a minute and retry."
            default:
                return "Codex device sign-in failed (HTTP \(statusCode))\(suffix)"
            }
        case let .networkError(error):
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet:
                    return "Codex sign-in failed: no internet connection on this device."
                case .timedOut:
                    return "Codex sign-in timed out. Check network quality and retry."
                case .networkConnectionLost:
                    return "Codex sign-in failed: network connection was interrupted."
                case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                    return "Codex sign-in failed: auth host could not be reached."
                case .secureConnectionFailed, .appTransportSecurityRequiresSecureConnection:
                    return "Codex sign-in failed: secure connection to auth server was blocked."
                case .badServerResponse:
                    return "Codex sign-in failed: server response was rejected. Check VPN/ad blocker/Private Relay and try again."
                default:
                    break
                }
            }
            return "Network error during Codex sign-in: \(error.localizedDescription)"
        }
    }
}

public enum iOSCodexJWT {
    public struct AuthClaims: Equatable, Sendable {
        public let accountID: String?
        public let planType: String?

        public init(accountID: String?, planType: String?) {
            self.accountID = accountID
            self.planType = planType
        }
    }

    public static func extractAuthClaims(from idToken: String?) -> AuthClaims {
        guard let idToken else { return .init(accountID: nil, planType: nil) }
        guard let payload = Self.decodePayload(idToken) else { return .init(accountID: nil, planType: nil) }

        let auth = payload["https://api.openai.com/auth"] as? [String: Any]
        let accountID = (auth?["chatgpt_account_id"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let planType = ((auth?["chatgpt_plan_type"] as? String)
            ?? (payload["chatgpt_plan_type"] as? String))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return AuthClaims(accountID: accountID?.nilIfEmpty, planType: planType?.nilIfEmpty)
    }

    private static func decodePayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 {
            payload.append("=")
        }
        guard let data = Data(base64Encoded: payload) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

public struct iOSCodexOAuthDeviceCode: Decodable, Sendable {
    public let deviceAuthID: String
    public let userCode: String
    public let intervalSeconds: Int
    public let verificationURL: String

    private enum CodingKeys: String, CodingKey {
        case deviceAuthID = "device_auth_id"
        case userCode = "user_code"
        case userCodeAlt = "usercode"
        case interval
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.deviceAuthID = try container.decode(String.self, forKey: .deviceAuthID)
        if let userCode = try? container.decode(String.self, forKey: .userCode) {
            self.userCode = userCode
        } else {
            self.userCode = try container.decode(String.self, forKey: .userCodeAlt)
        }

        if let intervalString = try? container.decode(String.self, forKey: .interval),
           let value = Int(intervalString.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            self.intervalSeconds = value
        } else if let intervalInt = try? container.decode(Int.self, forKey: .interval) {
            self.intervalSeconds = intervalInt
        } else {
            self.intervalSeconds = 5
        }

        self.verificationURL = ""
    }

    public init(deviceAuthID: String, userCode: String, intervalSeconds: Int, verificationURL: String) {
        self.deviceAuthID = deviceAuthID
        self.userCode = userCode
        self.intervalSeconds = intervalSeconds
        self.verificationURL = verificationURL
    }
}

public struct iOSCodexOAuthDeviceGrant: Decodable, Sendable {
    public let authorizationCode: String
    public let codeChallenge: String
    public let codeVerifier: String

    private enum CodingKeys: String, CodingKey {
        case authorizationCode = "authorization_code"
        case codeChallenge = "code_challenge"
        case codeVerifier = "code_verifier"
    }
}

public struct iOSCodexDeviceAuthFlow: Sendable {
    public static let issuer = "https://auth.openai.com"
    public static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    public init() {}

    public func requestDeviceCode(
        issuer: String = Self.issuer,
        clientID: String = Self.clientID) async throws -> iOSCodexOAuthDeviceCode
    {
        let base = issuer.trimmingCharacters(in: .whitespacesAndNewlines).trimmingTrailingSlash()
        guard let url = URL(string: "\(base)/api/accounts/deviceauth/usercode") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        Self.applyDefaultHeaders(to: &request)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["client_id": clientID])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw iOSCodexDeviceAuthError.invalidResponse
            }

            guard http.statusCode == 200 else {
                throw Self.makeServerError(statusCode: http.statusCode, data: data)
            }

            let raw = try JSONDecoder().decode(iOSCodexOAuthDeviceCode.self, from: data)
            return iOSCodexOAuthDeviceCode(
                deviceAuthID: raw.deviceAuthID,
                userCode: raw.userCode,
                intervalSeconds: max(0, raw.intervalSeconds),
                verificationURL: "\(base)/codex/device")
        } catch let error as iOSCodexDeviceAuthError {
            throw error
        } catch {
            throw iOSCodexDeviceAuthError.networkError(error)
        }
    }

    public func completeDeviceCodeLogin(
        _ code: iOSCodexOAuthDeviceCode,
        issuer: String = Self.issuer,
        clientID: String = Self.clientID) async throws -> iOSCodexOAuthCredentials
    {
        let base = issuer.trimmingCharacters(in: .whitespacesAndNewlines).trimmingTrailingSlash()
        let grant = try await self.pollForDeviceGrant(code, issuer: base)
        return try await self.exchangeCodeForTokens(
            authorizationCode: grant.authorizationCode,
            codeVerifier: grant.codeVerifier,
            issuer: base,
            clientID: clientID)
    }

    public func exchangeCodeForTokens(
        authorizationCode: String,
        codeVerifier: String,
        issuer: String = Self.issuer,
        clientID: String = Self.clientID) async throws -> iOSCodexOAuthCredentials
    {
        let base = issuer.trimmingCharacters(in: .whitespacesAndNewlines).trimmingTrailingSlash()
        guard let url = URL(string: "\(base)/oauth/token") else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        Self.applyDefaultHeaders(to: &request)

        let redirectURI = "\(base)/deviceauth/callback"
        let body: [String: String] = [
            "grant_type": "authorization_code",
            "code": authorizationCode,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": codeVerifier,
        ]
        request.httpBody = Self.formURLEncodedBody(body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw iOSCodexDeviceAuthError.invalidResponse
            }
            guard http.statusCode == 200 else {
                throw Self.makeServerError(statusCode: http.statusCode, data: data)
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw iOSCodexDeviceAuthError.invalidResponse
            }
            let accessToken = (json["access_token"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let refreshToken = (json["refresh_token"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let idToken = (json["id_token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !accessToken.isEmpty else { throw iOSCodexDeviceAuthError.invalidResponse }

            let claims = iOSCodexJWT.extractAuthClaims(from: idToken)
            return iOSCodexOAuthCredentials(
                accessToken: accessToken,
                refreshToken: refreshToken,
                idToken: idToken,
                accountID: claims.accountID,
                lastRefresh: Date())
        } catch let error as iOSCodexDeviceAuthError {
            throw error
        } catch {
            throw iOSCodexDeviceAuthError.networkError(error)
        }
    }

    private func pollForDeviceGrant(
        _ code: iOSCodexOAuthDeviceCode,
        issuer: String) async throws -> iOSCodexOAuthDeviceGrant
    {
        guard let url = URL(string: "\(issuer)/api/accounts/deviceauth/token") else {
            throw URLError(.badURL)
        }
        let timeout: TimeInterval = 15 * 60
        let started = Date()

        while Date().timeIntervalSince(started) < timeout {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            Self.applyDefaultHeaders(to: &request)
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "device_auth_id": code.deviceAuthID,
                "user_code": code.userCode,
            ])

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            if (200...299).contains(http.statusCode) {
                return try JSONDecoder().decode(iOSCodexOAuthDeviceGrant.self, from: data)
            }

            if http.statusCode == 403 || http.statusCode == 404 {
                let interval = max(0, code.intervalSeconds)
                try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                continue
            }

            throw Self.makeServerError(statusCode: http.statusCode, data: data)
        }

        throw URLError(.timedOut)
    }

    private static func applyDefaultHeaders(to request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CodexBar iOS", forHTTPHeaderField: "User-Agent")
    }

    private static func makeServerError(statusCode: Int, data: Data?) -> iOSCodexDeviceAuthError {
        .serverError(statusCode: statusCode, message: self.extractErrorMessage(from: data))
    }

    private static func extractErrorMessage(from data: Data?) -> String? {
        guard let data, !data.isEmpty else { return nil }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let message = json["error_description"] as? String {
                return message.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            }
            if let message = json["message"] as? String {
                return message.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            }
            if let error = json["error"] as? String {
                return error.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            }
            if let error = json["error"] as? [String: Any] {
                if let code = error["code"] as? String, let message = error["message"] as? String {
                    return "\(code): \(message)".trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                }
                if let message = error["message"] as? String {
                    return message.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                }
                if let code = error["code"] as? String {
                    return code.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                }
            }
            if let reason = json["reason"] as? String {
                return reason.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            }
        }

        let plain = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let plain, !plain.isEmpty else { return nil }
        return String(plain.prefix(180))
    }

    private static func formURLEncodedBody(_ parameters: [String: String]) -> Data {
        let pairs = parameters
            .map { key, value in
                "\(Self.formEncode(key))=\(Self.formEncode(value))"
            }
            .joined(separator: "&")
        return Data(pairs.utf8)
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

public enum iOSCodexTokenRefresher {
    private static let endpoint = URL(string: "https://auth.openai.com/oauth/token")!
    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    public enum RefreshError: LocalizedError, Sendable {
        case expired
        case revoked
        case reused
        case networkError(Error)
        case invalidResponse(String)

        public var errorDescription: String? {
            switch self {
            case .expired:
                "Codex refresh token expired. Please sign in again."
            case .revoked:
                "Codex refresh token was revoked. Please sign in again."
            case .reused:
                "Codex refresh token was already used. Please sign in again."
            case let .networkError(error):
                "Network error during token refresh: \(error.localizedDescription)"
            case let .invalidResponse(message):
                "Invalid refresh response: \(message)"
            }
        }
    }

    public static func refresh(_ credentials: iOSCodexOAuthCredentials) async throws -> iOSCodexOAuthCredentials {
        guard !credentials.refreshToken.isEmpty else {
            return credentials
        }

        var request = URLRequest(url: self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": self.clientID,
            "grant_type": "refresh_token",
            "refresh_token": credentials.refreshToken,
            "scope": "openid profile email",
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw RefreshError.invalidResponse("No HTTP response")
            }

            if http.statusCode == 401 {
                if let errorCode = self.extractErrorCode(from: data) {
                    switch errorCode.lowercased() {
                    case "refresh_token_expired":
                        throw RefreshError.expired
                    case "refresh_token_reused":
                        throw RefreshError.reused
                    case "refresh_token_invalidated":
                        throw RefreshError.revoked
                    default:
                        throw RefreshError.expired
                    }
                }
                throw RefreshError.expired
            }

            guard http.statusCode == 200 else {
                throw RefreshError.invalidResponse("Status \(http.statusCode)")
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw RefreshError.invalidResponse("Invalid JSON")
            }

            let newAccess = (json["access_token"] as? String ?? credentials.accessToken)
            let newRefresh = (json["refresh_token"] as? String ?? credentials.refreshToken)
            let newID = (json["id_token"] as? String ?? credentials.idToken)
            let claims = iOSCodexJWT.extractAuthClaims(from: newID)

            return iOSCodexOAuthCredentials(
                accessToken: newAccess,
                refreshToken: newRefresh,
                idToken: newID,
                accountID: claims.accountID ?? credentials.accountID,
                lastRefresh: Date())
        } catch let error as RefreshError {
            throw error
        } catch {
            throw RefreshError.networkError(error)
        }
    }

    private static func extractErrorCode(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = json["error"] as? [String: Any], let code = error["code"] as? String {
            return code
        }
        if let error = json["error"] as? String {
            return error
        }
        return json["code"] as? String
    }
}

public enum iOSCodexUsageFetcher {
    private static let defaultChatGPTBaseURL = "https://chatgpt.com/backend-api/"
    private static let chatGPTUsagePath = "/wham/usage"
    private static let codexUsagePath = "/api/codex/usage"

    public static func fetchUsage(credentials: iOSCodexOAuthCredentials) async throws -> iOSCodexUsageResponse {
        var request = URLRequest(url: self.resolveUsageURL())
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("CodexBar iOS", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let accountID = credentials.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw iOSCodexOAuthFetchError.invalidResponse
            }

            switch http.statusCode {
            case 200...299:
                do {
                    return try JSONDecoder().decode(iOSCodexUsageResponse.self, from: data)
                } catch {
                    throw iOSCodexOAuthFetchError.invalidResponse
                }
            case 401, 403:
                throw iOSCodexOAuthFetchError.unauthorized
            default:
                let body = String(data: data, encoding: .utf8)
                throw iOSCodexOAuthFetchError.serverError(http.statusCode, body)
            }
        } catch let error as iOSCodexOAuthFetchError {
            throw error
        } catch {
            throw iOSCodexOAuthFetchError.networkError(error)
        }
    }

    private static func resolveUsageURL() -> URL {
        let normalized = self.normalizeChatGPTBaseURL(self.defaultChatGPTBaseURL)
        let path = normalized.contains("/backend-api") ? Self.chatGPTUsagePath : Self.codexUsagePath
        let full = normalized + path
        return URL(string: full) ?? URL(string: Self.defaultChatGPTBaseURL + Self.chatGPTUsagePath)!
    }

    private static func normalizeChatGPTBaseURL(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { trimmed = Self.defaultChatGPTBaseURL }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        if trimmed.hasPrefix("https://chatgpt.com") || trimmed.hasPrefix("https://chat.openai.com"),
           !trimmed.contains("/backend-api")
        {
            trimmed += "/backend-api"
        }
        return trimmed
    }
}

public enum iOSCodexUsageMapper {
    public static func makeSnapshot(
        from usage: iOSCodexUsageResponse,
        credentials: iOSCodexOAuthCredentials,
        generatedAt: Date = Date()) -> iOSWidgetSnapshot
    {
        let claimsPlan = iOSCodexJWT.extractAuthClaims(from: credentials.idToken).planType
        let planType = usage.planType?.rawValue ?? claimsPlan

        let entry = iOSWidgetSnapshot.ProviderEntry(
            providerID: "codex",
            updatedAt: generatedAt,
            primary: self.makeWindow(usage.rateLimit?.primaryWindow),
            secondary: self.makeWindow(usage.rateLimit?.secondaryWindow),
            tertiary: nil,
            planType: planType,
            creditsRemaining: usage.credits?.balance,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])

        return iOSWidgetSnapshot(
            entries: [entry],
            enabledProviderIDs: ["codex"],
            generatedAt: generatedAt)
    }

    private static func makeWindow(_ window: iOSCodexUsageResponse.WindowSnapshot?) -> iOSWidgetSnapshot.RateWindow? {
        guard let window else { return nil }
        return iOSWidgetSnapshot.RateWindow(
            usedPercent: Double(window.usedPercent),
            windowMinutes: window.limitWindowSeconds / 60,
            resetsAt: Date(timeIntervalSince1970: TimeInterval(window.resetAt)),
            resetDescription: nil)
    }
}

extension String {
    fileprivate var nilIfEmpty: String? {
        self.isEmpty ? nil : self
    }

    fileprivate func trimmingTrailingSlash() -> String {
        var value = self
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }
}

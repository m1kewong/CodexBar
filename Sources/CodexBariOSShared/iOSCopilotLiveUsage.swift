import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct iOSCopilotUsageResponse: Sendable, Decodable {
    public struct QuotaSnapshot: Sendable, Decodable {
        public let entitlement: Double
        public let remaining: Double
        public let percentRemaining: Double
        public let quotaID: String

        private enum CodingKeys: String, CodingKey {
            case entitlement
            case remaining
            case percentRemaining = "percent_remaining"
            case quotaID = "quota_id"
        }
    }

    public struct QuotaSnapshots: Sendable, Decodable {
        public let premiumInteractions: QuotaSnapshot?
        public let chat: QuotaSnapshot?

        private enum CodingKeys: String, CodingKey {
            case premiumInteractions = "premium_interactions"
            case chat
        }
    }

    public let quotaSnapshots: QuotaSnapshots
    public let copilotPlan: String
    public let assignedDate: String
    public let quotaResetDate: String

    private enum CodingKeys: String, CodingKey {
        case quotaSnapshots = "quota_snapshots"
        case copilotPlan = "copilot_plan"
        case assignedDate = "assigned_date"
        case quotaResetDate = "quota_reset_date"
    }
}

public enum iOSCopilotUsageMapper {
    public static func makeSnapshot(
        from response: iOSCopilotUsageResponse,
        generatedAt: Date = Date()) -> iOSWidgetSnapshot
    {
        let primary = self.makeRateWindow(response.quotaSnapshots.premiumInteractions)
        let secondary = self.makeRateWindow(response.quotaSnapshots.chat)
        let entry = iOSWidgetSnapshot.ProviderEntry(
            providerID: "copilot",
            updatedAt: generatedAt,
            primary: primary,
            secondary: secondary,
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])

        return iOSWidgetSnapshot(
            entries: [entry],
            enabledProviderIDs: ["copilot"],
            generatedAt: generatedAt)
    }

    private static func makeRateWindow(_ snapshot: iOSCopilotUsageResponse.QuotaSnapshot?) -> iOSWidgetSnapshot.RateWindow? {
        guard let snapshot else { return nil }
        let usedPercent = max(0, min(100, 100 - snapshot.percentRemaining))
        return iOSWidgetSnapshot.RateWindow(
            usedPercent: usedPercent,
            windowMinutes: nil,
            resetsAt: nil,
            resetDescription: nil)
    }
}

public struct iOSCopilotUsageFetcher: Sendable {
    private let token: String

    public init(token: String) {
        self.token = token
    }

    public func fetch() async throws -> iOSCopilotUsageResponse {
        guard let url = URL(string: "https://api.github.com/copilot_internal/user") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("token \(self.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("vscode/1.96.2", forHTTPHeaderField: "Editor-Version")
        request.setValue("copilot-chat/0.26.7", forHTTPHeaderField: "Editor-Plugin-Version")
        request.setValue("GitHubCopilotChat/0.26.7", forHTTPHeaderField: "User-Agent")
        request.setValue("2025-04-01", forHTTPHeaderField: "X-Github-Api-Version")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw URLError(.userAuthenticationRequired)
        }
        guard http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(iOSCopilotUsageResponse.self, from: data)
    }
}

public struct iOSCopilotDeviceFlow: Sendable {
    private let clientID = "Iv1.b507a08c87ecfe98"
    private let scopes = "read:user"

    public struct DeviceCodeResponse: Decodable, Sendable {
        public let deviceCode: String
        public let userCode: String
        public let verificationURI: String
        public let expiresIn: Int
        public let interval: Int

        private enum CodingKeys: String, CodingKey {
            case deviceCode = "device_code"
            case userCode = "user_code"
            case verificationURI = "verification_uri"
            case expiresIn = "expires_in"
            case interval
        }
    }

    public struct AccessTokenResponse: Decodable, Sendable {
        public let accessToken: String
        public let tokenType: String
        public let scope: String

        private enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case tokenType = "token_type"
            case scope
        }
    }

    public init() {}

    public func requestDeviceCode() async throws -> DeviceCodeResponse {
        let url = URL(string: "https://github.com/login/device/code")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formURLEncodedBody([
            "client_id": self.clientID,
            "scope": self.scopes,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
    }

    public func pollForToken(deviceCode: String, interval: Int) async throws -> String {
        let url = URL(string: "https://github.com/login/oauth/access_token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formURLEncodedBody([
            "client_id": self.clientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        ])

        while true {
            try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            try Task.checkCancellation()

            let (data, _) = try await URLSession.shared.data(for: request)

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? String
            {
                if error == "authorization_pending" {
                    continue
                }
                if error == "slow_down" {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    continue
                }
                if error == "expired_token" {
                    throw URLError(.timedOut)
                }
                throw URLError(.userAuthenticationRequired)
            }

            if let tokenResponse = try? JSONDecoder().decode(AccessTokenResponse.self, from: data) {
                return tokenResponse.accessToken
            }
        }
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

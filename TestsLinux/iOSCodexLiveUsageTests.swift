import Foundation
import Testing
@testable import CodexBariOSShared

@Suite
struct iOSCodexLiveUsageTests {
    @Test
    func mapCodexUsageResponseWithPlusPlan() throws {
        let json = """
        {
          "plan_type": "plus",
          "rate_limit": {
            "primary_window": {
              "used_percent": 20,
              "reset_at": 1765238400,
              "limit_window_seconds": 18000
            },
            "secondary_window": {
              "used_percent": 10,
              "reset_at": 1765310000,
              "limit_window_seconds": 604800
            }
          },
          "credits": {
            "has_credits": true,
            "unlimited": false,
            "balance": 45.5
          }
        }
        """
        let data = try #require(json.data(using: .utf8))
        let response = try JSONDecoder().decode(iOSCodexUsageResponse.self, from: data)

        let credentials = iOSCodexOAuthCredentials(
            accessToken: "a",
            refreshToken: "r",
            idToken: nil,
            accountID: "account-123",
            lastRefresh: Date(timeIntervalSince1970: 0))
        let snapshot = iOSCodexUsageMapper.makeSnapshot(from: response, credentials: credentials, generatedAt: Date())
        let summary = try #require(snapshot.providerSummaries.first)

        #expect(summary.providerID == "codex")
        #expect(summary.sessionRemainingPercent == 80)
        #expect(summary.weeklyRemainingPercent == 90)
        #expect(summary.creditsRemaining == 45.5)
        #expect(summary.planType == "plus")
    }

    @Test
    func extractAccountIDFromIDTokenClaims() throws {
        let claims = #"{"https://api.openai.com/auth":{"chatgpt_account_id":"acc-xyz","chatgpt_plan_type":"plus"}}"#
        let payload = Data(claims.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let token = "header.\(payload).sig"

        let parsed = iOSCodexJWT.extractAuthClaims(from: token)
        #expect(parsed.accountID == "acc-xyz")
        #expect(parsed.planType == "plus")
    }
}

import Foundation
import Testing
@testable import CodexBariOSShared

@Suite
struct iOSCopilotLiveUsageTests {
    @Test
    func mapCopilotUsageResponseIntoWidgetSnapshot() throws {
        let json = """
        {
          "quota_snapshots": {
            "premium_interactions": {
              "entitlement": 300,
              "remaining": 120,
              "percent_remaining": 40,
              "quota_id": "premium_interactions"
            },
            "chat": {
              "entitlement": 500,
              "remaining": 450,
              "percent_remaining": 90,
              "quota_id": "chat"
            }
          },
          "copilot_plan": "individual",
          "assigned_date": "2026-02-01",
          "quota_reset_date": "2026-03-01"
        }
        """

        let data = try #require(json.data(using: .utf8))
        let response = try JSONDecoder().decode(iOSCopilotUsageResponse.self, from: data)
        let snapshot = iOSCopilotUsageMapper.makeSnapshot(from: response, generatedAt: Date(timeIntervalSince1970: 0))
        let summary = try #require(snapshot.providerSummaries.first)

        #expect(summary.providerID == "copilot")
        #expect(summary.sessionRemainingPercent == 40)
        #expect(summary.weeklyRemainingPercent == 90)
    }

    @Test
    func mapHandlesMissingSecondaryQuota() throws {
        let json = """
        {
          "quota_snapshots": {
            "premium_interactions": {
              "entitlement": 200,
              "remaining": 100,
              "percent_remaining": 50,
              "quota_id": "premium_interactions"
            }
          },
          "copilot_plan": "business",
          "assigned_date": "2026-02-01",
          "quota_reset_date": "2026-03-01"
        }
        """
        let data = try #require(json.data(using: .utf8))
        let response = try JSONDecoder().decode(iOSCopilotUsageResponse.self, from: data)
        let snapshot = iOSCopilotUsageMapper.makeSnapshot(from: response, generatedAt: Date(timeIntervalSince1970: 0))
        let summary = try #require(snapshot.providerSummaries.first)

        #expect(summary.sessionRemainingPercent == 50)
        #expect(summary.weeklyRemainingPercent == nil)
    }
}

import Foundation
import Testing
@testable import CodexBariOSShared

@Suite
struct iOSAdditionalProvidersLiveUsageTests {
    @Test
    func mapZaiUsageIntoWidgetSnapshot() throws {
        let json = """
        {
          "code": 200,
          "msg": "Operation successful",
          "data": {
            "limits": [
              {
                "type": "TIME_LIMIT",
                "unit": 5,
                "number": 1,
                "usage": 100,
                "currentValue": 100,
                "remaining": 0,
                "percentage": 100
              },
              {
                "type": "TOKENS_LIMIT",
                "unit": 3,
                "number": 5,
                "usage": 40000000,
                "currentValue": 13628365,
                "remaining": 26371635,
                "percentage": 34,
                "nextResetTime": 1768507567547
              }
            ],
            "planName": "Pro"
          },
          "success": true
        }
        """

        let snapshot = try iOSZaiUsageFetcher._parseUsageSnapshotForTesting(
            Data(json.utf8),
            now: Date(timeIntervalSince1970: 0))
        let widget = iOSZaiUsageMapper.makeSnapshot(from: snapshot, generatedAt: Date(timeIntervalSince1970: 0))
        let summary = try #require(widget.providerSummaries.first)

        #expect(summary.providerID == "zai")
        #expect(summary.planType == "Pro")
        #expect(abs((summary.sessionRemainingPercent ?? 0) - 65.9290875) < 0.001)
        #expect(summary.weeklyRemainingPercent == 0)
    }

    @Test
    func mapSyntheticUsageIntoWidgetSnapshot() throws {
        let json = """
        {
          "plan": "Starter",
          "quotas": [
            { "name": "Monthly", "limit": 1000, "used": 250, "reset_at": "2025-01-01T00:00:00Z" },
            { "name": "Daily", "max": 200, "remaining": 50, "window_minutes": 1440 }
          ]
        }
        """

        let snapshot = try iOSSyntheticUsageFetcher._parseUsageSnapshotForTesting(
            Data(json.utf8),
            now: Date(timeIntervalSince1970: 0))
        let widget = iOSSyntheticUsageMapper.makeSnapshot(from: snapshot, generatedAt: Date(timeIntervalSince1970: 0))
        let summary = try #require(widget.providerSummaries.first)

        #expect(summary.providerID == "synthetic")
        #expect(summary.planType == "Starter")
        #expect(summary.sessionRemainingPercent == 75)
        #expect(summary.weeklyRemainingPercent == 25)
    }

    @Test
    func parseKimiK2SummaryAndMapSnapshot() throws {
        let json = """
        {
          "data": {
            "usage": {
              "total": 120,
              "credits_remaining": 30,
              "average_tokens": 42,
              "updated_at": "2024-01-02T03:04:05Z"
            }
          }
        }
        """

        let summary = try iOSKimiK2UsageFetcher._parseSummaryForTesting(Data(json.utf8))
        let widget = iOSKimiK2UsageMapper.makeSnapshot(from: summary, generatedAt: Date(timeIntervalSince1970: 0))
        let providerSummary = try #require(widget.providerSummaries.first)

        #expect(summary.consumed == 120)
        #expect(summary.remaining == 30)
        #expect(summary.averageTokens == 42)
        #expect(providerSummary.providerID == "kimik2")
        #expect(providerSummary.sessionRemainingPercent == 20)
    }

    @Test
    func mapKimiUsageIntoWidgetSnapshot() throws {
        let json = """
        {
          "usages": [
            {
              "scope": "FEATURE_CODING",
              "detail": {
                "limit": "2048",
                "used": "375",
                "remaining": "1673",
                "resetTime": "2026-01-09T15:23:13.373329235Z"
              },
              "limits": [
                {
                  "window": {
                    "duration": 300,
                    "timeUnit": "TIME_UNIT_MINUTE"
                  },
                  "detail": {
                    "limit": "200",
                    "used": "200",
                    "remaining": "0",
                    "resetTime": "2026-01-06T15:05:24.374187075Z"
                  }
                }
              ]
            }
          ]
        }
        """

        let response = try JSONDecoder().decode(iOSKimiUsageResponse.self, from: Data(json.utf8))
        let widget = try iOSKimiUsageMapper.makeSnapshot(from: response, generatedAt: Date(timeIntervalSince1970: 0))
        let summary = try #require(widget.providerSummaries.first)

        #expect(summary.providerID == "kimi")
        #expect(abs((summary.sessionRemainingPercent ?? 0) - 81.689453125) < 0.001)
        #expect(summary.weeklyRemainingPercent == 0)
    }

    @Test
    func parseMiniMaxRemainsAndMapSnapshot() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let start = 1_700_000_000_000
        let end = start + 5 * 60 * 60 * 1000
        let json = """
        {
          "base_resp": { "status_code": 0 },
          "current_subscribe_title": "Max",
          "model_remains": [
            {
              "current_interval_total_count": 1000,
              "current_interval_usage_count": 250,
              "start_time": \(start),
              "end_time": \(end),
              "remains_time": 240000
            }
          ]
        }
        """

        let remains = try iOSMiniMaxUsageFetcher._parseRemainsSnapshotForTesting(Data(json.utf8), now: now)
        let widget = iOSMiniMaxUsageMapper.makeSnapshot(from: remains, generatedAt: now)
        let summary = try #require(widget.providerSummaries.first)

        #expect(summary.providerID == "minimax")
        #expect(summary.planType == "Max")
        #expect(summary.sessionRemainingPercent == 25)
    }
}

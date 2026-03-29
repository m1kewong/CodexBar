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

    @Test
    func parseClaudeUsageAndMapSnapshot() throws {
        let json = """
        {
          "five_hour": {
            "utilization": 35,
            "resets_at": "2026-02-08T15:00:00Z"
          },
          "seven_day": {
            "utilization": 64,
            "resets_at": "2026-02-12T00:00:00Z"
          },
          "seven_day_opus": {
            "utilization": 80
          }
        }
        """

        let usage = try iOSClaudeWebUsageFetcher._parseUsageSnapshotForTesting(
            Data(json.utf8),
            planName: "Claude Pro",
            now: Date(timeIntervalSince1970: 0))
        let widget = iOSClaudeWebUsageMapper.makeSnapshot(from: usage, generatedAt: Date(timeIntervalSince1970: 0))
        let summary = try #require(widget.providerSummaries.first)

        #expect(summary.providerID == "claude")
        #expect(summary.planType == "Claude Pro")
        #expect(summary.sessionRemainingPercent == 65)
        #expect(summary.weeklyRemainingPercent == 36)
    }

    @Test
    func parseCursorUsageAndMapSnapshot() throws {
        let json = """
        {
          "billingCycleEnd": "2026-02-28T00:00:00Z",
          "membershipType": "pro",
          "individualUsage": {
            "plan": { "used": 500, "limit": 2000, "totalPercentUsed": 0.25 },
            "onDemand": { "used": 250, "limit": 1000 }
          }
        }
        """

        let usage = try iOSCursorUsageFetcher._parseUsageSnapshotForTesting(
            Data(json.utf8),
            now: Date(timeIntervalSince1970: 0))
        let widget = iOSCursorUsageMapper.makeSnapshot(from: usage, generatedAt: Date(timeIntervalSince1970: 0))
        let summary = try #require(widget.providerSummaries.first)

        #expect(summary.providerID == "cursor")
        #expect(summary.planType == "pro")
        #expect(summary.sessionRemainingPercent == 75)
        #expect(summary.weeklyRemainingPercent == 75)
    }

    @Test
    func parseOpenCodeUsageAndMapSnapshot() throws {
        let text = """
        rollingUsage: { usagePercent: 30, resetInSec: 3600 },
        weeklyUsage: { usagePercent: 70, resetInSec: 86400 }
        """

        let usage = try iOSOpenCodeUsageFetcher._parseSubscriptionForTesting(text, now: Date(timeIntervalSince1970: 0))
        let widget = iOSOpenCodeUsageMapper.makeSnapshot(from: usage, generatedAt: Date(timeIntervalSince1970: 0))
        let summary = try #require(widget.providerSummaries.first)

        #expect(summary.providerID == "opencode")
        #expect(summary.sessionRemainingPercent == 70)
        #expect(summary.weeklyRemainingPercent == 30)
    }

    @Test
    func parseAmpUsageAndMapSnapshot() throws {
        let html = """
        <script>
        const freeTierUsage = { quota: 1000, used: 250, hourlyReplenishment: 25, windowHours: 12 };
        </script>
        """

        let usage = try iOSAmpUsageFetcher._parseUsageSnapshotForTesting(
            html: html,
            now: Date(timeIntervalSince1970: 0))
        let widget = iOSAmpUsageMapper.makeSnapshot(from: usage, generatedAt: Date(timeIntervalSince1970: 0))
        let summary = try #require(widget.providerSummaries.first)

        #expect(summary.providerID == "amp")
        #expect(summary.planType == "Amp Free")
        #expect(summary.sessionRemainingPercent == 75)
    }

    @Test
    func parseGeminiQuotaAndMapSnapshot() throws {
        let json = """
        {
          "buckets": [
            {
              "remainingFraction": 0.8,
              "resetTime": "2026-02-08T23:00:00Z",
              "modelId": "gemini-2.5-pro"
            },
            {
              "remainingFraction": 0.4,
              "resetTime": "2026-02-08T23:00:00Z",
              "modelId": "gemini-2.5-flash"
            }
          ]
        }
        """

        let usage = try iOSGeminiUsageFetcher._parseUsageSnapshotForTesting(
            Data(json.utf8),
            now: Date(timeIntervalSince1970: 0))
        let widget = iOSGeminiUsageMapper.makeSnapshot(from: usage, generatedAt: Date(timeIntervalSince1970: 0))
        let summary = try #require(widget.providerSummaries.first)

        #expect(summary.providerID == "gemini")
        #expect(summary.sessionRemainingPercent == 80)
        #expect(summary.weeklyRemainingPercent == 40)
    }
}

import Foundation
import Testing
@testable import CodexBariOSShared

@Suite
struct iOSWidgetSnapshotTests {
    @Test
    func decodeSnapshotAndComputeSummaries() throws {
        let json = """
        {
          "entries": [
            {
              "provider": "codex",
              "updatedAt": "2026-02-08T12:00:00Z",
              "primary": {"usedPercent": 25, "windowMinutes": 300, "resetsAt": null, "resetDescription": "Resets in 3h"},
              "secondary": {"usedPercent": 50, "windowMinutes": 10080, "resetsAt": null, "resetDescription": "Resets in 4d"},
              "tertiary": null,
              "creditsRemaining": 123.4,
              "codeReviewRemainingPercent": 80,
              "tokenUsage": {"sessionCostUSD": 1.2, "sessionTokens": 1200, "last30DaysCostUSD": 45.6, "last30DaysTokens": 32000},
              "dailyUsage": []
            }
          ],
          "enabledProviders": ["codex"],
          "generatedAt": "2026-02-08T12:00:00Z"
        }
        """

        let data = try #require(json.data(using: .utf8))
        let snapshot = try iOSWidgetSnapshot.decode(from: data)
        let summaries = snapshot.providerSummaries

        #expect(summaries.count == 1)
        #expect(summaries[0].providerID == "codex")
        #expect(summaries[0].sessionRemainingPercent == 75)
        #expect(summaries[0].weeklyRemainingPercent == 50)
        #expect(summaries[0].creditsRemaining == 123.4)
    }

    @Test
    func selectedProviderFallsBackToFirstAvailable() {
        let snapshot = iOSWidgetSnapshot(
            entries: [
                .init(
                    providerID: "claude",
                    updatedAt: Date(),
                    primary: nil,
                    secondary: nil,
                    tertiary: nil,
                    creditsRemaining: nil,
                    codeReviewRemainingPercent: nil,
                    tokenUsage: nil,
                    dailyUsage: []),
            ],
            enabledProviderIDs: ["claude"],
            generatedAt: Date())

        let selected = snapshot.selectedProviderID(preferred: "codex")
        #expect(selected == "claude")
    }

    @Test
    func providerCatalogProvidesIconSymbolsWithFallback() {
        #expect(iOSProviderCatalog.iconSymbolName(for: "codex") == "terminal.fill")
        #expect(iOSProviderCatalog.iconSymbolName(for: "opencode") == "chevron.left.forwardslash.chevron.right")
        #expect(iOSProviderCatalog.iconSymbolName(for: "unknown-provider") == "questionmark.circle.fill")
    }

    @Test
    func providerCatalogProvidesBrandIconResourceNames() {
        #expect(iOSProviderCatalog.brandIconResourceName(for: "codex") == "ProviderIcon-codex")
        #expect(iOSProviderCatalog.brandIconResourceName(for: "claude") == "ProviderIcon-claude")
        #expect(iOSProviderCatalog.brandIconResourceName(for: "kimik2") == "ProviderIcon-kimi")
        #expect(iOSProviderCatalog.brandIconResourceName(for: "unknown-provider") == nil)
    }

    @Test
    func providerCatalogProvidesAccentTokensWithFallback() {
        #expect(iOSProviderCatalog.accentToken(for: "codex") == .ocean)
        #expect(iOSProviderCatalog.accentToken(for: "gemini") == .violet)
        #expect(iOSProviderCatalog.accentToken(for: "unknown-provider") == .neutral)
    }

    @Test
    func pinnedProviderIDsPrioritizeConfiguredThenCoreThenDefaults() {
        let connectable = ["codex", "copilot", "claude", "gemini", "cursor", "zai"]
        let configured: Set<String> = ["cursor", "copilot"]
        let pinned = iOSProviderCatalog.pinnedProviderIDs(
            connectableProviderIDs: connectable,
            configuredProviderIDs: configured,
            cap: 4)

        #expect(pinned == ["copilot", "cursor", "codex", "claude"])
    }

    @Test
    func pinnedProviderIDsDeduplicatesAndRespectsCap() {
        let connectable = ["codex", "claude", "gemini"]
        let configured: Set<String> = ["codex", "gemini"]
        let pinned = iOSProviderCatalog.pinnedProviderIDs(
            connectableProviderIDs: connectable,
            configuredProviderIDs: configured,
            cap: 2)

        #expect(pinned == ["codex", "gemini"])
    }

    @Test
    func refreshProviderIDsPrioritizeSelectedThenCoreThenConfiguredOrder() {
        let configured = ["zai", "claude", "copilot", "cursor"]
        let prioritized = iOSProviderCatalog.prioritizedRefreshProviderIDs(
            configuredProviderIDs: configured,
            selectedProviderID: "cursor",
            cap: 3)

        #expect(prioritized == ["cursor", "copilot", "claude"])
    }

    @Test
    func refreshProviderIDsIgnoreUnknownSelectionAndDeduplicate() {
        let configured = ["copilot", "copilot", "gemini", "zai"]
        let prioritized = iOSProviderCatalog.prioritizedRefreshProviderIDs(
            configuredProviderIDs: configured,
            selectedProviderID: "codex",
            cap: 0)

        #expect(prioritized == ["copilot", "gemini", "zai"])
    }

    @Test
    func sharedContainerStatusIncludesKnownCandidateGroups() {
        let status = iOSWidgetSnapshotStore.sharedContainerStatus(bundleID: "com.steipete.codexbar.ios")
        #expect(iOSWidgetSnapshotStore.appGroupID == "group.com.steipete.codexbar")
        #expect(status.candidateGroupIDs.contains("group.com.steipete.codexbar"))
        #expect(status.candidateGroupIDs.contains("group.com.steipete.codexbar.debug"))
        #expect(status.candidateGroupIDs.contains("group.com.steipete.codexbar.ios"))
    }
}

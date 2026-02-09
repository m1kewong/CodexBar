import Foundation

public struct iOSWidgetSnapshot: Codable, Equatable, Sendable {
    public struct ProviderEntry: Codable, Equatable, Sendable {
        public let providerID: String
        public let updatedAt: Date
        public let primary: RateWindow?
        public let secondary: RateWindow?
        public let tertiary: RateWindow?
        public let planType: String?
        public let creditsRemaining: Double?
        public let codeReviewRemainingPercent: Double?
        public let tokenUsage: TokenUsageSummary?
        public let dailyUsage: [DailyUsagePoint]

        public init(
            providerID: String,
            updatedAt: Date,
            primary: RateWindow?,
            secondary: RateWindow?,
            tertiary: RateWindow?,
            planType: String? = nil,
            creditsRemaining: Double?,
            codeReviewRemainingPercent: Double?,
            tokenUsage: TokenUsageSummary?,
            dailyUsage: [DailyUsagePoint])
        {
            self.providerID = providerID
            self.updatedAt = updatedAt
            self.primary = primary
            self.secondary = secondary
            self.tertiary = tertiary
            self.planType = planType
            self.creditsRemaining = creditsRemaining
            self.codeReviewRemainingPercent = codeReviewRemainingPercent
            self.tokenUsage = tokenUsage
            self.dailyUsage = dailyUsage
        }

        private enum CodingKeys: String, CodingKey {
            case providerID = "provider"
            case updatedAt
            case primary
            case secondary
            case tertiary
            case planType = "plan_type"
            case creditsRemaining
            case codeReviewRemainingPercent
            case tokenUsage
            case dailyUsage
        }
    }

    public struct RateWindow: Codable, Equatable, Sendable {
        public let usedPercent: Double
        public let windowMinutes: Int?
        public let resetsAt: Date?
        public let resetDescription: String?

        public init(usedPercent: Double, windowMinutes: Int?, resetsAt: Date?, resetDescription: String?) {
            self.usedPercent = usedPercent
            self.windowMinutes = windowMinutes
            self.resetsAt = resetsAt
            self.resetDescription = resetDescription
        }

        public var remainingPercent: Double {
            max(0, 100 - self.usedPercent)
        }
    }

    public struct TokenUsageSummary: Codable, Equatable, Sendable {
        public let sessionCostUSD: Double?
        public let sessionTokens: Int?
        public let last30DaysCostUSD: Double?
        public let last30DaysTokens: Int?

        public init(
            sessionCostUSD: Double?,
            sessionTokens: Int?,
            last30DaysCostUSD: Double?,
            last30DaysTokens: Int?)
        {
            self.sessionCostUSD = sessionCostUSD
            self.sessionTokens = sessionTokens
            self.last30DaysCostUSD = last30DaysCostUSD
            self.last30DaysTokens = last30DaysTokens
        }
    }

    public struct DailyUsagePoint: Codable, Equatable, Sendable {
        public let dayKey: String
        public let totalTokens: Int?
        public let costUSD: Double?

        public init(dayKey: String, totalTokens: Int?, costUSD: Double?) {
            self.dayKey = dayKey
            self.totalTokens = totalTokens
            self.costUSD = costUSD
        }
    }

    public struct ProviderSummary: Equatable, Sendable {
        public let providerID: String
        public let displayName: String
        public let updatedAt: Date
        public let sessionRemainingPercent: Double?
        public let weeklyRemainingPercent: Double?
        public let planType: String?
        public let creditsRemaining: Double?
        public let codeReviewRemainingPercent: Double?
        public let todayCostUSD: Double?
        public let last30DaysCostUSD: Double?
        public let todayTokens: Int?
        public let last30DaysTokens: Int?
    }

    public let entries: [ProviderEntry]
    public let enabledProviderIDs: [String]
    public let generatedAt: Date

    public init(entries: [ProviderEntry], enabledProviderIDs: [String], generatedAt: Date) {
        self.entries = entries
        self.enabledProviderIDs = enabledProviderIDs
        self.generatedAt = generatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case entries
        case enabledProviderIDs = "enabledProviders"
        case generatedAt
    }

    public var providerSummaries: [ProviderSummary] {
        self.entries.map { entry in
            ProviderSummary(
                providerID: entry.providerID,
                displayName: iOSProviderCatalog.displayName(for: entry.providerID),
                updatedAt: entry.updatedAt,
                sessionRemainingPercent: entry.primary?.remainingPercent,
                weeklyRemainingPercent: entry.secondary?.remainingPercent,
                planType: entry.planType,
                creditsRemaining: entry.creditsRemaining,
                codeReviewRemainingPercent: entry.codeReviewRemainingPercent,
                todayCostUSD: entry.tokenUsage?.sessionCostUSD,
                last30DaysCostUSD: entry.tokenUsage?.last30DaysCostUSD,
                todayTokens: entry.tokenUsage?.sessionTokens,
                last30DaysTokens: entry.tokenUsage?.last30DaysTokens)
        }
    }

    public var availableProviderIDs: [String] {
        let source = self.enabledProviderIDs.isEmpty ? self.entries.map(\.providerID) : self.enabledProviderIDs
        var seen: Set<String> = []
        return source.filter { seen.insert($0).inserted }
    }

    public func selectedProviderID(preferred: String?) -> String? {
        let available = self.availableProviderIDs
        guard !available.isEmpty else { return nil }
        if let preferred, available.contains(preferred) {
            return preferred
        }
        return available.first
    }

    public static func decode(from data: Data) throws -> iOSWidgetSnapshot {
        try self.decoder.decode(iOSWidgetSnapshot.self, from: data)
    }

    public func encode() throws -> Data {
        try Self.encoder.encode(self)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public enum iOSWidgetSnapshotStore {
    public static let appGroupID = "group.com.steipete.codexbar"
    private static let filename = "widget-snapshot.json"
    private static let selectedProviderKey = "widgetSelectedProvider"

    public static func load(bundleID: String? = Bundle.main.bundleIdentifier) -> iOSWidgetSnapshot? {
        guard let url = self.snapshotURL(bundleID: bundleID) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? iOSWidgetSnapshot.decode(from: data)
    }

    public static func save(_ snapshot: iOSWidgetSnapshot, bundleID: String? = Bundle.main.bundleIdentifier) {
        guard let url = self.snapshotURL(bundleID: bundleID) else { return }
        guard let data = try? snapshot.encode() else { return }
        try? data.write(to: url, options: [.atomic])
    }

    public static func loadSelectedProviderID(bundleID: String? = Bundle.main.bundleIdentifier) -> String? {
        guard let defaults = self.sharedDefaults(bundleID: bundleID) else { return nil }
        return defaults.string(forKey: self.selectedProviderKey)
    }

    public static func saveSelectedProviderID(_ providerID: String, bundleID: String? = Bundle.main.bundleIdentifier) {
        guard let defaults = self.sharedDefaults(bundleID: bundleID) else { return }
        defaults.set(providerID, forKey: self.selectedProviderKey)
    }

    private static func sharedDefaults(bundleID: String?) -> UserDefaults? {
        guard let groupID = self.groupID(for: bundleID) else { return nil }
        return UserDefaults(suiteName: groupID)
    }

    private static func snapshotURL(bundleID: String?) -> URL? {
        let fm = FileManager.default
        if let groupID = self.groupID(for: bundleID),
           let container = fm.containerURL(forSecurityApplicationGroupIdentifier: groupID)
        {
            return container.appendingPathComponent(self.filename, isDirectory: false)
        }

        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("CodexBar", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(self.filename, isDirectory: false)
    }

    private static func groupID(for bundleID: String?) -> String? {
        guard let bundleID, !bundleID.isEmpty else { return self.appGroupID }
        if bundleID.contains(".debug") {
            return "group.com.steipete.codexbar.debug"
        }
        return self.appGroupID
    }
}

public enum iOSProviderCatalog {
    public enum AccentToken: String, Equatable, Sendable {
        case ocean
        case violet
        case amber
        case indigo
        case mint
        case rose
        case cyan
        case neutral
    }

    public static func displayName(for providerID: String) -> String {
        self.metadata[providerID]?.displayName ?? self.fallbackDisplayName(for: providerID)
    }

    public static func iconSymbolName(for providerID: String) -> String {
        self.metadata[providerID]?.iconSymbolName ?? "questionmark.circle.fill"
    }

    public static func brandIconResourceName(for providerID: String) -> String? {
        self.metadata[providerID]?.iconResourceName
    }

    public static func accentToken(for providerID: String) -> AccentToken {
        self.metadata[providerID]?.accentToken ?? .neutral
    }

    public static func pinnedProviderIDs(
        connectableProviderIDs: [String],
        configuredProviderIDs: Set<String>,
        coreProviderIDs: [String] = ["codex", "claude", "gemini"],
        cap: Int = 4) -> [String]
    {
        guard cap > 0 else {
            return []
        }

        let connectableSet = Set(connectableProviderIDs)
        var result: [String] = []

        for providerID in connectableProviderIDs where configuredProviderIDs.contains(providerID) {
            guard !result.contains(providerID) else { continue }
            result.append(providerID)
            if result.count == cap {
                return result
            }
        }

        for providerID in coreProviderIDs where connectableSet.contains(providerID) {
            guard !result.contains(providerID) else { continue }
            result.append(providerID)
            if result.count == cap {
                return result
            }
        }

        for providerID in connectableProviderIDs {
            guard !result.contains(providerID) else { continue }
            result.append(providerID)
            if result.count == cap {
                break
            }
        }

        return result
    }

    private static func fallbackDisplayName(for providerID: String) -> String {
        providerID
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map(\.capitalized)
            .joined(separator: " ")
    }

    private struct ProviderMetadata {
        let displayName: String
        let iconSymbolName: String
        let iconResourceName: String
        let accentToken: AccentToken
    }

    private static let metadata: [String: ProviderMetadata] = [
        "codex": .init(
            displayName: "Codex",
            iconSymbolName: "terminal.fill",
            iconResourceName: "ProviderIcon-codex",
            accentToken: .ocean),
        "claude": .init(
            displayName: "Claude",
            iconSymbolName: "quote.bubble.fill",
            iconResourceName: "ProviderIcon-claude",
            accentToken: .amber),
        "gemini": .init(
            displayName: "Gemini",
            iconSymbolName: "sparkles",
            iconResourceName: "ProviderIcon-gemini",
            accentToken: .violet),
        "antigravity": .init(
            displayName: "Antigravity",
            iconSymbolName: "atom",
            iconResourceName: "ProviderIcon-antigravity",
            accentToken: .mint),
        "cursor": .init(
            displayName: "Cursor",
            iconSymbolName: "cursorarrow",
            iconResourceName: "ProviderIcon-cursor",
            accentToken: .indigo),
        "opencode": .init(
            displayName: "OpenCode",
            iconSymbolName: "chevron.left.forwardslash.chevron.right",
            iconResourceName: "ProviderIcon-opencode",
            accentToken: .cyan),
        "zai": .init(displayName: "z.ai", iconSymbolName: "globe", iconResourceName: "ProviderIcon-zai", accentToken: .violet),
        "factory": .init(
            displayName: "Droid",
            iconSymbolName: "shippingbox.fill",
            iconResourceName: "ProviderIcon-factory",
            accentToken: .rose),
        "copilot": .init(
            displayName: "Copilot",
            iconSymbolName: "paperplane.fill",
            iconResourceName: "ProviderIcon-copilot",
            accentToken: .indigo),
        "minimax": .init(
            displayName: "MiniMax",
            iconSymbolName: "dial.medium.fill",
            iconResourceName: "ProviderIcon-minimax",
            accentToken: .rose),
        "vertexai": .init(
            displayName: "Vertex AI",
            iconSymbolName: "triangle.fill",
            iconResourceName: "ProviderIcon-vertexai",
            accentToken: .mint),
        "kiro": .init(
            displayName: "Kiro",
            iconSymbolName: "shield.fill",
            iconResourceName: "ProviderIcon-kiro",
            accentToken: .indigo),
        "augment": .init(
            displayName: "Augment",
            iconSymbolName: "plus.rectangle.on.rectangle",
            iconResourceName: "ProviderIcon-augment",
            accentToken: .cyan),
        "jetbrains": .init(
            displayName: "JetBrains",
            iconSymbolName: "keyboard.fill",
            iconResourceName: "ProviderIcon-jetbrains",
            accentToken: .amber),
        "kimi": .init(
            displayName: "Kimi",
            iconSymbolName: "moon.stars.fill",
            iconResourceName: "ProviderIcon-kimi",
            accentToken: .violet),
        "kimik2": .init(
            displayName: "Kimi K2",
            iconSymbolName: "moon.fill",
            iconResourceName: "ProviderIcon-kimi",
            accentToken: .indigo),
        "amp": .init(
            displayName: "Amp",
            iconSymbolName: "bolt.fill",
            iconResourceName: "ProviderIcon-amp",
            accentToken: .amber),
        "synthetic": .init(
            displayName: "Synthetic",
            iconSymbolName: "cpu.fill",
            iconResourceName: "ProviderIcon-synthetic",
            accentToken: .cyan),
    ]
}

public enum iOSWidgetPreviewData {
    public static func snapshot() -> iOSWidgetSnapshot {
        iOSWidgetSnapshot(
            entries: [
                .init(
                    providerID: "codex",
                    updatedAt: Date(),
                    primary: .init(
                        usedPercent: 32,
                        windowMinutes: 300,
                        resetsAt: nil,
                        resetDescription: "Resets in 3h"),
                    secondary: .init(
                        usedPercent: 58,
                        windowMinutes: 10080,
                        resetsAt: nil,
                        resetDescription: "Resets in 4d"),
                    tertiary: nil,
                    planType: "plus",
                    creditsRemaining: 1243.4,
                    codeReviewRemainingPercent: 77,
                    tokenUsage: .init(
                        sessionCostUSD: 12.4,
                        sessionTokens: 420_000,
                        last30DaysCostUSD: 923.8,
                        last30DaysTokens: 12_400_000),
                    dailyUsage: [
                        .init(dayKey: "2026-02-02", totalTokens: 120_000, costUSD: 15.2),
                        .init(dayKey: "2026-02-03", totalTokens: 80000, costUSD: 10.1),
                        .init(dayKey: "2026-02-04", totalTokens: 140_000, costUSD: 17.9),
                        .init(dayKey: "2026-02-05", totalTokens: 90000, costUSD: 11.4),
                        .init(dayKey: "2026-02-06", totalTokens: 160_000, costUSD: 19.8),
                    ]),
            ],
            enabledProviderIDs: ["codex"],
            generatedAt: Date())
    }
}

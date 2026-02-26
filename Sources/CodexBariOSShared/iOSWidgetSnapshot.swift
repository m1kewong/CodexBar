import Foundation
#if canImport(Security)
import Security
#endif

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
    public struct SharedContainerStatus: Equatable, Sendable {
        public let candidateGroupIDs: [String]
        public let writableGroupID: String?
        public let runtimeEntitledGroupIDs: [String]

        public init(
            candidateGroupIDs: [String],
            writableGroupID: String?,
            runtimeEntitledGroupIDs: [String] = [])
        {
            self.candidateGroupIDs = candidateGroupIDs
            self.writableGroupID = writableGroupID
            self.runtimeEntitledGroupIDs = runtimeEntitledGroupIDs
        }
    }

    public static let appGroupID = "group.com.steipete.codexbar"
    private static let filename = "widget-snapshot.json"
    private static let selectedProviderKey = "widgetSelectedProvider"

    public static func load(bundleID: String? = Bundle.main.bundleIdentifier) -> iOSWidgetSnapshot? {
        let urls = self.snapshotURLs(bundleID: bundleID)
        guard !urls.isEmpty else { return nil }

        for (index, url) in urls.enumerated() {
            guard let data = try? Data(contentsOf: url) else { continue }
            guard let snapshot = try? iOSWidgetSnapshot.decode(from: data) else { continue }
            if index > 0 {
                self.save(snapshot, bundleID: bundleID)
            }
            return snapshot
        }

        return nil
    }

    @discardableResult
    public static func save(_ snapshot: iOSWidgetSnapshot, bundleID: String? = Bundle.main.bundleIdentifier) -> Bool {
        let data: Data
        if let encoded = try? snapshot.encode() {
            data = encoded
        } else {
            let sanitized = snapshot.sanitizedForPersistence()
            guard let encoded = try? sanitized.encode() else { return false }
            data = encoded
        }

        if let url = self.writableSnapshotURL(bundleID: bundleID)?.0 {
            try? data.write(to: url, options: [.atomic])
            return true
        }

        // App-local fallback keeps iOS app usage visible even when App Group sharing is unavailable.
        try? data.write(to: self.legacySnapshotURL(), options: [.atomic])
        return false
    }

    public static func sharedContainerStatus(bundleID: String? = Bundle.main.bundleIdentifier) -> SharedContainerStatus {
        let candidateGroupIDs = self.groupIDs(for: bundleID)
        let writableGroupID = self.writableSnapshotURL(bundleID: bundleID)?.1
        let runtimeEntitledGroupIDs = self.runtimeEntitledGroupIDs()
        return SharedContainerStatus(
            candidateGroupIDs: candidateGroupIDs,
            writableGroupID: writableGroupID,
            runtimeEntitledGroupIDs: runtimeEntitledGroupIDs)
    }

    public static func loadSelectedProviderID(bundleID: String? = Bundle.main.bundleIdentifier) -> String? {
        if let defaults = self.sharedDefaults(bundleID: bundleID),
           let providerID = defaults.string(forKey: self.selectedProviderKey)
        {
            return providerID
        }
        return UserDefaults.standard.string(forKey: self.selectedProviderKey)
    }

    public static func saveSelectedProviderID(_ providerID: String, bundleID: String? = Bundle.main.bundleIdentifier) {
        if let defaults = self.sharedDefaults(bundleID: bundleID) {
            defaults.set(providerID, forKey: self.selectedProviderKey)
            return
        }
        UserDefaults.standard.set(providerID, forKey: self.selectedProviderKey)
    }

    private static func sharedDefaults(bundleID: String?) -> UserDefaults? {
        for groupID in self.groupIDs(for: bundleID) {
            if let defaults = UserDefaults(suiteName: groupID) {
                return defaults
            }
        }
        return nil
    }

    private static func snapshotURL(bundleID: String?) -> URL? {
        self.snapshotURLs(bundleID: bundleID).first
    }

    private static func writableSnapshotURL(bundleID: String?) -> (URL, String)? {
        let fm = FileManager.default
        for groupID in self.groupIDs(for: bundleID) {
            if let container = fm.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
                return (container.appendingPathComponent(self.filename, isDirectory: false), groupID)
            }
        }
        return nil
    }

    private static func snapshotURLs(bundleID: String?) -> [URL] {
        let fm = FileManager.default
        var urls: [URL] = []
        for groupID in self.groupIDs(for: bundleID) {
            if let container = fm.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
                urls.append(container.appendingPathComponent(self.filename, isDirectory: false))
            }
        }

        let legacy = self.legacySnapshotURL()
        urls.append(legacy)
        return urls
    }

    private static func legacySnapshotURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("CodexBar", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(self.filename, isDirectory: false)
    }

    private static func groupIDs(for bundleID: String?) -> [String] {
        var groups: [String] = [self.appGroupID]

        if let bundleID, !bundleID.isEmpty {
            groups.append(self.appGroupID + ".debug")
            groups.append("group." + bundleID)
        }

        groups.append("group.com.steipete.codexbar.ios")
        groups.append("group.com.steipete.codexbar.ios.debug")
        var seen: Set<String> = []
        return groups.filter { seen.insert($0).inserted }
    }

    private static func runtimeEntitledGroupIDs() -> [String] {
        #if canImport(Security) && os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let entitlementValue = SecTaskCopyValueForEntitlement(
                  task,
                  "com.apple.security.application-groups" as CFString,
                  nil)
        else {
            return []
        }

        if let groups = entitlementValue as? [String] {
            return groups
        }
        if let group = entitlementValue as? String {
            return [group]
        }
        return []
        #else
        return []
        #endif
    }
}

extension iOSWidgetSnapshot {
    func sanitizedForPersistence() -> iOSWidgetSnapshot {
        iOSWidgetSnapshot(
            entries: self.entries.map { $0.sanitizedForPersistence() },
            enabledProviderIDs: self.enabledProviderIDs,
            generatedAt: self.generatedAt)
    }
}

extension iOSWidgetSnapshot.ProviderEntry {
    func sanitizedForPersistence() -> iOSWidgetSnapshot.ProviderEntry {
        iOSWidgetSnapshot.ProviderEntry(
            providerID: self.providerID,
            updatedAt: self.updatedAt,
            primary: self.primary?.sanitizedForPersistence(),
            secondary: self.secondary?.sanitizedForPersistence(),
            tertiary: self.tertiary?.sanitizedForPersistence(),
            planType: self.planType,
            creditsRemaining: self.creditsRemaining?.finiteOrNil,
            codeReviewRemainingPercent: self.codeReviewRemainingPercent?.finiteOrNil,
            tokenUsage: self.tokenUsage?.sanitizedForPersistence(),
            dailyUsage: self.dailyUsage.map { $0.sanitizedForPersistence() })
    }
}

extension iOSWidgetSnapshot.RateWindow {
    func sanitizedForPersistence() -> iOSWidgetSnapshot.RateWindow {
        let boundedUsedPercent = max(0, min(100, self.usedPercent.finiteOrZero))
        return iOSWidgetSnapshot.RateWindow(
            usedPercent: boundedUsedPercent,
            windowMinutes: self.windowMinutes,
            resetsAt: self.resetsAt,
            resetDescription: self.resetDescription)
    }
}

extension iOSWidgetSnapshot.TokenUsageSummary {
    func sanitizedForPersistence() -> iOSWidgetSnapshot.TokenUsageSummary {
        iOSWidgetSnapshot.TokenUsageSummary(
            sessionCostUSD: self.sessionCostUSD?.finiteOrNil,
            sessionTokens: self.sessionTokens,
            last30DaysCostUSD: self.last30DaysCostUSD?.finiteOrNil,
            last30DaysTokens: self.last30DaysTokens)
    }
}

extension iOSWidgetSnapshot.DailyUsagePoint {
    func sanitizedForPersistence() -> iOSWidgetSnapshot.DailyUsagePoint {
        iOSWidgetSnapshot.DailyUsagePoint(
            dayKey: self.dayKey,
            totalTokens: self.totalTokens,
            costUSD: self.costUSD?.finiteOrNil)
    }
}

extension Double {
    var finiteOrNil: Double? {
        self.isFinite ? self : nil
    }

    var finiteOrZero: Double {
        self.isFinite ? self : 0
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

    public static func prioritizedRefreshProviderIDs(
        configuredProviderIDs: [String],
        selectedProviderID: String?,
        coreProviderIDs: [String] = ["codex", "copilot", "claude", "gemini"],
        cap: Int = 0) -> [String]
    {
        var dedupedConfigured: [String] = []
        var configuredSet: Set<String> = []
        for providerID in configuredProviderIDs where configuredSet.insert(providerID).inserted {
            dedupedConfigured.append(providerID)
        }

        guard !dedupedConfigured.isEmpty else { return [] }
        var result: [String] = []

        if let selectedProviderID,
           configuredSet.contains(selectedProviderID)
        {
            result.append(selectedProviderID)
        }

        for providerID in coreProviderIDs where configuredSet.contains(providerID) {
            guard !result.contains(providerID) else { continue }
            result.append(providerID)
        }

        for providerID in dedupedConfigured where !result.contains(providerID) {
            result.append(providerID)
        }

        if cap > 0 {
            return Array(result.prefix(cap))
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
        "zai": .init(
            displayName: "z.ai",
            iconSymbolName: "globe",
            iconResourceName: "ProviderIcon-zai",
            accentToken: .violet),
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

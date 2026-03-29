import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - z.ai

public enum iOSZaiLimitType: String, Sendable {
    case timeLimit = "TIME_LIMIT"
    case tokensLimit = "TOKENS_LIMIT"
}

public enum iOSZaiLimitUnit: Int, Sendable {
    case unknown = 0
    case days = 1
    case hours = 3
    case minutes = 5
}

public struct iOSZaiUsageDetail: Sendable, Codable {
    public let modelCode: String
    public let usage: Int
}

public struct iOSZaiLimitEntry: Sendable {
    public let type: iOSZaiLimitType
    public let unit: iOSZaiLimitUnit
    public let number: Int
    public let usage: Int
    public let currentValue: Int
    public let remaining: Int
    public let percentage: Double
    public let usageDetails: [iOSZaiUsageDetail]
    public let nextResetTime: Date?

    public var usedPercent: Double {
        if self.usage > 0 {
            let used = max(0, min(self.usage, max(self.usage - self.remaining, self.currentValue)))
            return min(100, max(0, (Double(used) / Double(self.usage)) * 100))
        }
        return min(100, max(0, self.percentage))
    }

    public var windowMinutes: Int? {
        guard self.number > 0 else { return nil }
        switch self.unit {
        case .minutes: return self.number
        case .hours: return self.number * 60
        case .days: return self.number * 24 * 60
        case .unknown: return nil
        }
    }

    public var windowLabel: String? {
        guard self.number > 0 else { return nil }
        let unit: String? = switch self.unit {
        case .minutes: "minute"
        case .hours: "hour"
        case .days: "day"
        case .unknown: nil
        }
        guard let unit else { return nil }
        return "\(self.number) \(self.number == 1 ? unit : "\(unit)s") window"
    }
}

public struct iOSZaiUsageSnapshot: Sendable {
    public let tokenLimit: iOSZaiLimitEntry?
    public let timeLimit: iOSZaiLimitEntry?
    public let planName: String?
    public let updatedAt: Date
}

public enum iOSZaiUsageError: LocalizedError, Sendable {
    case invalidCredentials
    case networkError(String)
    case apiError(String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "Invalid z.ai API credentials."
        case let .networkError(message):
            "z.ai network error: \(message)"
        case let .apiError(message):
            "z.ai API error: \(message)"
        case let .parseFailed(message):
            "Failed to parse z.ai usage: \(message)"
        }
    }
}

private struct iOSZaiQuotaLimitResponse: Decodable {
    let code: Int
    let msg: String
    let data: iOSZaiQuotaLimitData?
    let success: Bool

    var isSuccess: Bool {
        self.success && self.code == 200
    }
}

private struct iOSZaiQuotaLimitData: Decodable {
    let limits: [iOSZaiLimitRaw]
    let planName: String?

    private enum CodingKeys: String, CodingKey {
        case limits
        case planName
        case plan
        case planType = "plan_type"
        case packageName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.limits = try container.decodeIfPresent([iOSZaiLimitRaw].self, forKey: .limits) ?? []
        let rawPlan = try [
            container.decodeIfPresent(String.self, forKey: .planName),
            container.decodeIfPresent(String.self, forKey: .plan),
            container.decodeIfPresent(String.self, forKey: .planType),
            container.decodeIfPresent(String.self, forKey: .packageName),
        ].compactMap(\.self).first
        let trimmed = rawPlan?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.planName = (trimmed?.isEmpty ?? true) ? nil : trimmed
    }
}

private struct iOSZaiLimitRaw: Codable {
    let type: String
    let unit: Int
    let number: Int
    let usage: Int
    let currentValue: Int
    let remaining: Int
    let percentage: Int
    let usageDetails: [iOSZaiUsageDetail]?
    let nextResetTime: Int?

    func toLimitEntry() -> iOSZaiLimitEntry? {
        guard let limitType = iOSZaiLimitType(rawValue: self.type) else { return nil }
        let unit = iOSZaiLimitUnit(rawValue: self.unit) ?? .unknown
        let resetAt = self.nextResetTime.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
        return iOSZaiLimitEntry(
            type: limitType,
            unit: unit,
            number: self.number,
            usage: self.usage,
            currentValue: self.currentValue,
            remaining: self.remaining,
            percentage: Double(self.percentage),
            usageDetails: self.usageDetails ?? [],
            nextResetTime: resetAt)
    }
}

public enum iOSZaiUsageFetcher {
    private static let quotaURL = URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")!

    public static func fetchUsage(apiKey: String) async throws -> iOSZaiUsageSnapshot {
        let token = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw iOSZaiUsageError.invalidCredentials }

        var request = URLRequest(url: Self.quotaURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw iOSZaiUsageError.networkError("Invalid response")
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                throw iOSZaiUsageError.invalidCredentials
            }
            guard http.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                throw iOSZaiUsageError.apiError(body)
            }
            return try Self.parseUsageSnapshot(data, now: Date())
        } catch let error as iOSZaiUsageError {
            throw error
        } catch {
            throw iOSZaiUsageError.networkError(error.localizedDescription)
        }
    }

    public static func _parseUsageSnapshotForTesting(_ data: Data, now: Date = Date()) throws -> iOSZaiUsageSnapshot {
        try Self.parseUsageSnapshot(data, now: now)
    }

    private static func parseUsageSnapshot(_ data: Data, now: Date) throws -> iOSZaiUsageSnapshot {
        let decoder = JSONDecoder()
        let response = try decoder.decode(iOSZaiQuotaLimitResponse.self, from: data)
        guard response.isSuccess else {
            throw iOSZaiUsageError.apiError(response.msg)
        }
        guard let payload = response.data else {
            throw iOSZaiUsageError.parseFailed("Missing data")
        }

        var tokenLimit: iOSZaiLimitEntry?
        var timeLimit: iOSZaiLimitEntry?
        for limit in payload.limits {
            guard let entry = limit.toLimitEntry() else { continue }
            switch entry.type {
            case .tokensLimit:
                tokenLimit = entry
            case .timeLimit:
                timeLimit = entry
            }
        }

        return iOSZaiUsageSnapshot(
            tokenLimit: tokenLimit,
            timeLimit: timeLimit,
            planName: payload.planName,
            updatedAt: now)
    }
}

public enum iOSZaiUsageMapper {
    public static func makeSnapshot(from usage: iOSZaiUsageSnapshot, generatedAt: Date = Date()) -> iOSWidgetSnapshot {
        let primary = usage.tokenLimit ?? usage.timeLimit
        let secondary = (usage.tokenLimit != nil && usage.timeLimit != nil) ? usage.timeLimit : nil

        let entry = iOSWidgetSnapshot.ProviderEntry(
            providerID: "zai",
            updatedAt: generatedAt,
            primary: primary.map(Self.rateWindow(for:)),
            secondary: secondary.map(Self.rateWindow(for:)),
            tertiary: nil,
            planType: usage.planName,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])

        return iOSWidgetSnapshot(
            entries: [entry],
            enabledProviderIDs: ["zai"],
            generatedAt: generatedAt)
    }

    private static func rateWindow(for limit: iOSZaiLimitEntry) -> iOSWidgetSnapshot.RateWindow {
        let resetDescription: String? = {
            if let label = limit.windowLabel {
                return label
            }
            if limit.type == .timeLimit {
                return "Monthly"
            }
            return nil
        }()
        return iOSWidgetSnapshot.RateWindow(
            usedPercent: limit.usedPercent,
            windowMinutes: limit.type == .tokensLimit ? limit.windowMinutes : nil,
            resetsAt: limit.nextResetTime,
            resetDescription: resetDescription)
    }
}

// MARK: - Synthetic

public struct iOSSyntheticQuotaEntry: Sendable {
    public let label: String?
    public let usedPercent: Double
    public let windowMinutes: Int?
    public let resetsAt: Date?
    public let resetDescription: String?
}

public struct iOSSyntheticUsageSnapshot: Sendable {
    public let quotas: [iOSSyntheticQuotaEntry]
    public let planName: String?
    public let updatedAt: Date
}

public enum iOSSyntheticUsageError: LocalizedError, Sendable {
    case invalidCredentials
    case networkError(String)
    case apiError(String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "Invalid Synthetic API credentials."
        case let .networkError(message):
            "Synthetic network error: \(message)"
        case let .apiError(message):
            "Synthetic API error: \(message)"
        case let .parseFailed(message):
            "Failed to parse Synthetic usage: \(message)"
        }
    }
}

public enum iOSSyntheticUsageFetcher {
    private static let quotaURL = URL(string: "https://api.synthetic.new/v2/quotas")!

    public static func fetchUsage(apiKey: String, now: Date = Date()) async throws -> iOSSyntheticUsageSnapshot {
        let token = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw iOSSyntheticUsageError.invalidCredentials }

        var request = URLRequest(url: Self.quotaURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw iOSSyntheticUsageError.networkError("Invalid response")
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                throw iOSSyntheticUsageError.invalidCredentials
            }
            guard http.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                throw iOSSyntheticUsageError.apiError(body)
            }
            return try Self.parseUsageSnapshot(data, now: now)
        } catch let error as iOSSyntheticUsageError {
            throw error
        } catch {
            throw iOSSyntheticUsageError.networkError(error.localizedDescription)
        }
    }

    public static func _parseUsageSnapshotForTesting(_ data: Data, now: Date = Date()) throws -> iOSSyntheticUsageSnapshot {
        try Self.parseUsageSnapshot(data, now: now)
    }

    private static func parseUsageSnapshot(_ data: Data, now: Date) throws -> iOSSyntheticUsageSnapshot {
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        let root: [String: Any] = {
            if let dict = object as? [String: Any] { return dict }
            if let array = object as? [Any] { return ["quotas": array] }
            return [:]
        }()

        let planName = Self.planName(from: root)
        let quotaObjects = Self.quotaObjects(from: root)
        let quotas = quotaObjects.compactMap { Self.parseQuota($0) }

        guard !quotas.isEmpty else {
            throw iOSSyntheticUsageError.parseFailed("Missing quota data.")
        }

        return iOSSyntheticUsageSnapshot(quotas: quotas, planName: planName, updatedAt: now)
    }

    private static func quotaObjects(from root: [String: Any]) -> [[String: Any]] {
        let dataDict = root["data"] as? [String: Any]
        let candidates: [Any?] = [
            root["quotas"],
            root["quota"],
            root["limits"],
            root["usage"],
            root["entries"],
            root["subscription"],
            root["data"],
            dataDict?["quotas"],
            dataDict?["quota"],
            dataDict?["limits"],
            dataDict?["usage"],
            dataDict?["entries"],
            dataDict?["subscription"],
        ]

        for candidate in candidates {
            if let array = candidate as? [[String: Any]] { return array }
            if let array = candidate as? [Any] {
                let dicts = array.compactMap { $0 as? [String: Any] }
                if !dicts.isEmpty { return dicts }
            }
            if let dict = candidate as? [String: Any], Self.isQuotaPayload(dict) {
                return [dict]
            }
        }
        return []
    }

    private static func planName(from root: [String: Any]) -> String? {
        if let direct = Self.firstString(in: root, keys: Self.planKeys) { return direct }
        if let dataDict = root["data"] as? [String: Any],
           let plan = Self.firstString(in: dataDict, keys: Self.planKeys)
        {
            return plan
        }
        return nil
    }

    private static func parseQuota(_ payload: [String: Any]) -> iOSSyntheticQuotaEntry? {
        let label = Self.firstString(in: payload, keys: Self.labelKeys)
        let percentUsed = Self.normalizedPercent(Self.firstDouble(in: payload, keys: Self.percentUsedKeys))
        let percentRemaining = Self.normalizedPercent(Self.firstDouble(in: payload, keys: Self.percentRemainingKeys))

        var usedPercent = percentUsed
        if usedPercent == nil, let remaining = percentRemaining {
            usedPercent = 100 - remaining
        }

        if usedPercent == nil {
            var limit = Self.firstDouble(in: payload, keys: Self.limitKeys)
            var used = Self.firstDouble(in: payload, keys: Self.usedKeys)
            var remaining = Self.firstDouble(in: payload, keys: Self.remainingKeys)

            if limit == nil, let used, let remaining {
                limit = used + remaining
            }
            if used == nil, let limit, let remaining {
                used = limit - remaining
            }
            if remaining == nil, let limit, let used {
                remaining = max(0, limit - used)
            }
            if let limit, let used, limit > 0 {
                usedPercent = (used / limit) * 100
            }
        }

        guard let usedPercent else { return nil }
        let windowMinutes = Self.windowMinutes(from: payload)
        let resetsAt = Self.firstDate(in: payload, keys: Self.resetKeys)
        let resetDescription = resetsAt == nil ? Self.windowDescription(minutes: windowMinutes) : nil

        return iOSSyntheticQuotaEntry(
            label: label,
            usedPercent: max(0, min(usedPercent, 100)),
            windowMinutes: windowMinutes,
            resetsAt: resetsAt,
            resetDescription: resetDescription)
    }

    private static func isQuotaPayload(_ payload: [String: Any]) -> Bool {
        let keySets = [Self.limitKeys, Self.usedKeys, Self.remainingKeys, Self.percentUsedKeys, Self.percentRemainingKeys]
        return keySets.contains { Self.firstDouble(in: payload, keys: $0) != nil }
    }

    private static func windowMinutes(from payload: [String: Any]) -> Int? {
        if let value = Self.firstInt(in: payload, keys: Self.windowMinutesKeys) { return value }
        if let value = Self.firstDouble(in: payload, keys: Self.windowHoursKeys) { return Int((value * 60).rounded()) }
        if let value = Self.firstDouble(in: payload, keys: Self.windowDaysKeys) { return Int((value * 24 * 60).rounded()) }
        if let value = Self.firstDouble(in: payload, keys: Self.windowSecondsKeys) { return Int((value / 60).rounded()) }
        return nil
    }

    private static func windowDescription(minutes: Int?) -> String? {
        guard let minutes, minutes > 0 else { return nil }
        let dayMinutes = 24 * 60
        if minutes % dayMinutes == 0 {
            let days = minutes / dayMinutes
            return "\(days) day\(days == 1 ? "" : "s") window"
        }
        if minutes % 60 == 0 {
            let hours = minutes / 60
            return "\(hours) hour\(hours == 1 ? "" : "s") window"
        }
        return "\(minutes) minute\(minutes == 1 ? "" : "s") window"
    }

    private static func normalizedPercent(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return value <= 1 ? value * 100 : value
    }

    private static func firstString(in payload: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = payload[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private static func firstDouble(in payload: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = Self.doubleValue(payload[key]) { return value }
        }
        return nil
    }

    private static func firstInt(in payload: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = Self.intValue(payload[key]) { return value }
        }
        return nil
    }

    private static func firstDate(in payload: [String: Any], keys: [String]) -> Date? {
        for key in keys {
            if let value = payload[key], let date = Self.dateValue(value) {
                return date
            }
        }
        return nil
    }

    private static func doubleValue(_ raw: Any?) -> Double? {
        switch raw {
        case let value as Double:
            return value
        case let value as NSNumber:
            return value.doubleValue
        case let value as String:
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func intValue(_ raw: Any?) -> Int? {
        switch raw {
        case let value as Int:
            return value
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func dateValue(_ raw: Any) -> Date? {
        if let number = Self.doubleValue(raw) {
            if number > 1_000_000_000_000 { return Date(timeIntervalSince1970: number / 1000) }
            if number > 1_000_000_000 { return Date(timeIntervalSince1970: number) }
        }
        if let string = raw as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if let number = Double(trimmed) {
                return Self.dateValue(number)
            }
            return Self.parseISODate(trimmed)
        }
        return nil
    }

    private static func parseISODate(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) {
            return date
        }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }

    private static let planKeys = [
        "plan",
        "planName",
        "plan_name",
        "subscription",
        "subscriptionPlan",
        "tier",
        "package",
        "packageName",
    ]

    private static let labelKeys = ["name", "label", "type", "period", "scope", "title", "id"]
    private static let percentUsedKeys = ["percentUsed", "usedPercent", "usagePercent", "usage_percent", "used_percent", "percent_used", "percent"]
    private static let percentRemainingKeys = ["percentRemaining", "remainingPercent", "remaining_percent", "percent_remaining"]
    private static let limitKeys = ["limit", "quota", "max", "total", "capacity", "allowance"]
    private static let usedKeys = ["used", "usage", "requests", "requestCount", "request_count", "consumed", "spent"]
    private static let remainingKeys = ["remaining", "left", "available", "balance"]
    private static let resetKeys = ["resetAt", "reset_at", "resetsAt", "resets_at", "renewAt", "renew_at", "renewsAt", "renews_at", "periodEnd", "period_end", "expiresAt", "expires_at", "endAt", "end_at"]
    private static let windowMinutesKeys = ["windowMinutes", "window_minutes", "periodMinutes", "period_minutes"]
    private static let windowHoursKeys = ["windowHours", "window_hours", "periodHours", "period_hours"]
    private static let windowDaysKeys = ["windowDays", "window_days", "periodDays", "period_days"]
    private static let windowSecondsKeys = ["windowSeconds", "window_seconds", "periodSeconds", "period_seconds"]
}

public enum iOSSyntheticUsageMapper {
    public static func makeSnapshot(from usage: iOSSyntheticUsageSnapshot, generatedAt: Date = Date()) -> iOSWidgetSnapshot {
        let primary = usage.quotas.first
        let secondary = usage.quotas.dropFirst().first
        let entry = iOSWidgetSnapshot.ProviderEntry(
            providerID: "synthetic",
            updatedAt: generatedAt,
            primary: primary.map(Self.rateWindow(for:)),
            secondary: secondary.map(Self.rateWindow(for:)),
            tertiary: nil,
            planType: usage.planName,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])
        return iOSWidgetSnapshot(entries: [entry], enabledProviderIDs: ["synthetic"], generatedAt: generatedAt)
    }

    private static func rateWindow(for quota: iOSSyntheticQuotaEntry) -> iOSWidgetSnapshot.RateWindow {
        iOSWidgetSnapshot.RateWindow(
            usedPercent: quota.usedPercent,
            windowMinutes: quota.windowMinutes,
            resetsAt: quota.resetsAt,
            resetDescription: quota.resetDescription)
    }
}

// MARK: - Kimi K2

public struct iOSKimiK2UsageSummary: Sendable {
    public let consumed: Double
    public let remaining: Double
    public let averageTokens: Double?
    public let updatedAt: Date
}

public enum iOSKimiK2UsageError: LocalizedError, Sendable {
    case missingCredentials
    case networkError(String)
    case apiError(String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            "Missing Kimi K2 API key."
        case let .networkError(message):
            "Kimi K2 network error: \(message)"
        case let .apiError(message):
            "Kimi K2 API error: \(message)"
        case let .parseFailed(message):
            "Failed to parse Kimi K2 response: \(message)"
        }
    }
}

public enum iOSKimiK2UsageFetcher {
    private static let creditsURL = URL(string: "https://kimi-k2.ai/api/user/credits")!

    public static func fetchUsage(apiKey: String) async throws -> iOSKimiK2UsageSummary {
        let token = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw iOSKimiK2UsageError.missingCredentials }

        var request = URLRequest(url: Self.creditsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw iOSKimiK2UsageError.networkError("Invalid response")
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                throw iOSKimiK2UsageError.missingCredentials
            }
            guard http.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                throw iOSKimiK2UsageError.apiError(body)
            }
            return try Self.parseSummary(data: data, headers: http.allHeaderFields)
        } catch let error as iOSKimiK2UsageError {
            throw error
        } catch {
            throw iOSKimiK2UsageError.networkError(error.localizedDescription)
        }
    }

    public static func _parseSummaryForTesting(_ data: Data, headers: [AnyHashable: Any] = [:]) throws -> iOSKimiK2UsageSummary {
        try Self.parseSummary(data: data, headers: headers)
    }

    private static func parseSummary(data: Data, headers: [AnyHashable: Any]) throws -> iOSKimiK2UsageSummary {
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let dictionary = json as? [String: Any]
        else {
            throw iOSKimiK2UsageError.parseFailed("Root JSON is not an object.")
        }

        let contexts = Self.contexts(from: dictionary)
        let consumed = Self.doubleValue(for: Self.consumedPaths, in: contexts) ?? 0
        let remaining = Self.doubleValue(for: Self.remainingPaths, in: contexts)
            ?? Self.doubleValueFromHeaders(headers: headers, key: "x-credits-remaining")
            ?? 0
        let averageTokens = Self.doubleValue(for: Self.averageTokenPaths, in: contexts)
        let updatedAt = Self.dateValue(for: Self.timestampPaths, in: contexts) ?? Date()

        return iOSKimiK2UsageSummary(
            consumed: consumed,
            remaining: max(0, remaining),
            averageTokens: averageTokens,
            updatedAt: updatedAt)
    }

    private static func contexts(from dictionary: [String: Any]) -> [[String: Any]] {
        var contexts: [[String: Any]] = [dictionary]
        if let data = dictionary["data"] as? [String: Any] {
            contexts.append(data)
            if let dataUsage = data["usage"] as? [String: Any] { contexts.append(dataUsage) }
            if let dataCredits = data["credits"] as? [String: Any] { contexts.append(dataCredits) }
        }
        if let result = dictionary["result"] as? [String: Any] {
            contexts.append(result)
            if let resultUsage = result["usage"] as? [String: Any] { contexts.append(resultUsage) }
            if let resultCredits = result["credits"] as? [String: Any] { contexts.append(resultCredits) }
        }
        if let usage = dictionary["usage"] as? [String: Any] { contexts.append(usage) }
        if let credits = dictionary["credits"] as? [String: Any] { contexts.append(credits) }
        return contexts
    }

    private static func doubleValue(for paths: [[String]], in contexts: [[String: Any]]) -> Double? {
        for path in paths {
            if let raw = Self.value(for: path, in: contexts), let value = Self.double(from: raw) {
                return value
            }
        }
        return nil
    }

    private static func dateValue(for paths: [[String]], in contexts: [[String: Any]]) -> Date? {
        for path in paths {
            if let raw = Self.value(for: path, in: contexts), let date = Self.date(from: raw) {
                return date
            }
        }
        return nil
    }

    private static func value(for path: [String], in contexts: [[String: Any]]) -> Any? {
        for context in contexts {
            var cursor: Any? = context
            for key in path {
                if let dict = cursor as? [String: Any] {
                    cursor = dict[key]
                } else {
                    cursor = nil
                }
            }
            if cursor != nil { return cursor }
        }
        return nil
    }

    private static func double(from raw: Any) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? String { return Double(value) }
        return nil
    }

    private static func date(from raw: Any) -> Date? {
        if let value = raw as? Date { return value }
        if let value = raw as? Double { return Self.dateFromNumeric(value) }
        if let value = raw as? Int { return Self.dateFromNumeric(Double(value)) }
        if let value = raw as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if let numeric = Double(trimmed) {
                return Self.dateFromNumeric(numeric)
            }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: trimmed) {
                return date
            }
            let fallback = ISO8601DateFormatter()
            fallback.formatOptions = [.withInternetDateTime]
            return fallback.date(from: trimmed)
        }
        return nil
    }

    private static func dateFromNumeric(_ value: Double) -> Date? {
        guard value > 0 else { return nil }
        if value > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: value / 1000)
        }
        return Date(timeIntervalSince1970: value)
    }

    private static func doubleValueFromHeaders(headers: [AnyHashable: Any], key: String) -> Double? {
        for (headerKey, value) in headers {
            guard let headerKey = headerKey as? String else { continue }
            if headerKey.lowercased() == key.lowercased() {
                return Self.double(from: value)
            }
        }
        return nil
    }

    private static let consumedPaths: [[String]] = [
        ["total_credits_consumed"],
        ["totalCreditsConsumed"],
        ["total_credits_used"],
        ["totalCreditsUsed"],
        ["credits_consumed"],
        ["creditsConsumed"],
        ["consumedCredits"],
        ["usedCredits"],
        ["total"],
        ["usage", "total"],
        ["usage", "consumed"],
    ]
    private static let remainingPaths: [[String]] = [
        ["credits_remaining"],
        ["creditsRemaining"],
        ["remaining_credits"],
        ["remainingCredits"],
        ["available_credits"],
        ["availableCredits"],
        ["credits_left"],
        ["creditsLeft"],
        ["usage", "credits_remaining"],
        ["usage", "remaining"],
    ]
    private static let averageTokenPaths: [[String]] = [
        ["average_tokens_per_request"],
        ["averageTokensPerRequest"],
        ["average_tokens"],
        ["averageTokens"],
        ["avg_tokens"],
        ["avgTokens"],
    ]
    private static let timestampPaths: [[String]] = [
        ["updated_at"],
        ["updatedAt"],
        ["timestamp"],
        ["time"],
        ["last_update"],
        ["lastUpdated"],
    ]
}

public enum iOSKimiK2UsageMapper {
    public static func makeSnapshot(from summary: iOSKimiK2UsageSummary, generatedAt: Date = Date()) -> iOSWidgetSnapshot {
        let total = max(0, summary.consumed + summary.remaining)
        let usedPercent: Double = total > 0 ? min(100, max(0, (summary.consumed / total) * 100)) : 0
        let usedText = String(format: "%.0f", summary.consumed)
        let totalText = String(format: "%.0f", total)

        let entry = iOSWidgetSnapshot.ProviderEntry(
            providerID: "kimik2",
            updatedAt: generatedAt,
            primary: iOSWidgetSnapshot.RateWindow(
                usedPercent: usedPercent,
                windowMinutes: nil,
                resetsAt: nil,
                resetDescription: total > 0 ? "Credits: \(usedText)/\(totalText)" : nil),
            secondary: nil,
            tertiary: nil,
            planType: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])

        return iOSWidgetSnapshot(entries: [entry], enabledProviderIDs: ["kimik2"], generatedAt: generatedAt)
    }
}

// MARK: - Kimi

public enum iOSKimiUsageError: LocalizedError, Sendable, Equatable {
    case missingToken
    case invalidToken
    case invalidRequest(String)
    case networkError(String)
    case apiError(String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            "Kimi auth token is missing."
        case .invalidToken:
            "Kimi auth token is invalid or expired."
        case let .invalidRequest(message):
            "Invalid request: \(message)"
        case let .networkError(message):
            "Kimi network error: \(message)"
        case let .apiError(message):
            "Kimi API error: \(message)"
        case let .parseFailed(message):
            "Failed to parse Kimi usage: \(message)"
        }
    }
}

public struct iOSKimiUsageResponse: Codable, Sendable {
    public let usages: [iOSKimiUsage]
}

public struct iOSKimiUsage: Codable, Sendable {
    public let scope: String
    public let detail: iOSKimiUsageDetail
    public let limits: [iOSKimiRateLimit]?
}

public struct iOSKimiUsageDetail: Codable, Sendable {
    public let limit: String
    public let used: String?
    public let remaining: String?
    public let resetTime: String
}

public struct iOSKimiRateLimit: Codable, Sendable {
    public let window: iOSKimiWindow
    public let detail: iOSKimiUsageDetail
}

public struct iOSKimiWindow: Codable, Sendable {
    public let duration: Int
    public let timeUnit: String
}

public struct iOSKimiUsageFetcher: Sendable {
    private static let usageURL =
        URL(string: "https://www.kimi.com/apiv2/kimi.gateway.billing.v1.BillingService/GetUsages")!

    private let authToken: String

    public init(authToken: String) {
        self.authToken = authToken
    }

    public func fetch() async throws -> iOSKimiUsageResponse {
        let token = self.authToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw iOSKimiUsageError.missingToken }

        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("kimi-auth=\(token)", forHTTPHeaderField: "Cookie")
        request.setValue("https://www.kimi.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.kimi.com/code/console", forHTTPHeaderField: "Referer")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("web", forHTTPHeaderField: "x-msh-platform")
        request.setValue(TimeZone.current.identifier, forHTTPHeaderField: "r-timezone")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["scope": ["FEATURE_CODING"]])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw iOSKimiUsageError.networkError("Invalid response")
            }

            switch http.statusCode {
            case 200:
                return try JSONDecoder().decode(iOSKimiUsageResponse.self, from: data)
            case 401, 403:
                throw iOSKimiUsageError.invalidToken
            case 400:
                throw iOSKimiUsageError.invalidRequest("Bad request")
            default:
                throw iOSKimiUsageError.apiError("HTTP \(http.statusCode)")
            }
        } catch let error as iOSKimiUsageError {
            throw error
        } catch {
            throw iOSKimiUsageError.networkError(error.localizedDescription)
        }
    }
}

public enum iOSKimiUsageMapper {
    public static func makeSnapshot(
        from response: iOSKimiUsageResponse,
        generatedAt: Date = Date()) throws -> iOSWidgetSnapshot
    {
        guard let codingUsage = response.usages.first(where: { $0.scope == "FEATURE_CODING" }) else {
            throw iOSKimiUsageError.parseFailed("FEATURE_CODING scope not found in response")
        }

        let weeklyLimit = Int(codingUsage.detail.limit) ?? 0
        let weeklyRemaining = Int(codingUsage.detail.remaining ?? "")
        let weeklyUsed = Int(codingUsage.detail.used ?? "") ?? {
            guard let weeklyRemaining else { return 0 }
            return max(0, weeklyLimit - weeklyRemaining)
        }()
        let weeklyPercent = weeklyLimit > 0 ? (Double(weeklyUsed) / Double(weeklyLimit)) * 100 : 0

        var secondaryWindow: iOSWidgetSnapshot.RateWindow?
        if let rateLimit = codingUsage.limits?.first {
            let rateLimitValue = Int(rateLimit.detail.limit) ?? 0
            let rateRemaining = Int(rateLimit.detail.remaining ?? "")
            let rateUsed = Int(rateLimit.detail.used ?? "") ?? {
                guard let rateRemaining else { return 0 }
                return max(0, rateLimitValue - rateRemaining)
            }()
            let ratePercent = rateLimitValue > 0 ? (Double(rateUsed) / Double(rateLimitValue)) * 100 : 0
            secondaryWindow = iOSWidgetSnapshot.RateWindow(
                usedPercent: ratePercent,
                windowMinutes: Self.windowMinutes(window: rateLimit.window),
                resetsAt: Self.parseDate(rateLimit.detail.resetTime),
                resetDescription: "Rate: \(rateUsed)/\(rateLimitValue)")
        }

        let entry = iOSWidgetSnapshot.ProviderEntry(
            providerID: "kimi",
            updatedAt: generatedAt,
            primary: iOSWidgetSnapshot.RateWindow(
                usedPercent: weeklyPercent,
                windowMinutes: nil,
                resetsAt: Self.parseDate(codingUsage.detail.resetTime),
                resetDescription: "\(weeklyUsed)/\(weeklyLimit) requests"),
            secondary: secondaryWindow,
            tertiary: nil,
            planType: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])

        return iOSWidgetSnapshot(entries: [entry], enabledProviderIDs: ["kimi"], generatedAt: generatedAt)
    }

    private static func parseDate(_ dateString: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: dateString) {
            return date
        }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: dateString)
    }

    private static func windowMinutes(window: iOSKimiWindow) -> Int? {
        switch window.timeUnit.uppercased() {
        case "TIME_UNIT_MINUTE":
            return window.duration
        case "TIME_UNIT_HOUR":
            return window.duration * 60
        case "TIME_UNIT_DAY":
            return window.duration * 24 * 60
        default:
            return 300
        }
    }

}

// MARK: - MiniMax (API token path)

public struct iOSMiniMaxUsageSnapshot: Sendable {
    public let planName: String?
    public let availablePrompts: Int?
    public let currentPrompts: Int?
    public let remainingPrompts: Int?
    public let windowMinutes: Int?
    public let usedPercent: Double?
    public let resetsAt: Date?
    public let updatedAt: Date
}

public enum iOSMiniMaxUsageError: LocalizedError, Sendable, Equatable {
    case invalidCredentials
    case networkError(String)
    case apiError(String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "MiniMax credentials are invalid or expired."
        case let .networkError(message):
            "MiniMax network error: \(message)"
        case let .apiError(message):
            "MiniMax API error: \(message)"
        case let .parseFailed(message):
            "Failed to parse MiniMax usage: \(message)"
        }
    }
}

private struct iOSMiniMaxCodingPlanPayload: Decodable {
    let baseResp: iOSMiniMaxBaseResponse?
    let data: iOSMiniMaxCodingPlanData

    private enum CodingKeys: String, CodingKey {
        case baseResp = "base_resp"
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.baseResp = try container.decodeIfPresent(iOSMiniMaxBaseResponse.self, forKey: .baseResp)
        if container.contains(.data) {
            let dataDecoder = try container.superDecoder(forKey: .data)
            self.data = try iOSMiniMaxCodingPlanData(from: dataDecoder)
        } else {
            self.data = try iOSMiniMaxCodingPlanData(from: decoder)
        }
    }
}

private struct iOSMiniMaxCodingPlanData: Decodable {
    let baseResp: iOSMiniMaxBaseResponse?
    let currentSubscribeTitle: String?
    let planName: String?
    let comboTitle: String?
    let currentPlanTitle: String?
    let currentComboCard: iOSMiniMaxComboCard?
    let modelRemains: [iOSMiniMaxModelRemains]

    private enum CodingKeys: String, CodingKey {
        case baseResp = "base_resp"
        case currentSubscribeTitle = "current_subscribe_title"
        case planName = "plan_name"
        case comboTitle = "combo_title"
        case currentPlanTitle = "current_plan_title"
        case currentComboCard = "current_combo_card"
        case modelRemains = "model_remains"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.baseResp = try container.decodeIfPresent(iOSMiniMaxBaseResponse.self, forKey: .baseResp)
        self.currentSubscribeTitle = try container.decodeIfPresent(String.self, forKey: .currentSubscribeTitle)
        self.planName = try container.decodeIfPresent(String.self, forKey: .planName)
        self.comboTitle = try container.decodeIfPresent(String.self, forKey: .comboTitle)
        self.currentPlanTitle = try container.decodeIfPresent(String.self, forKey: .currentPlanTitle)
        self.currentComboCard = try container.decodeIfPresent(iOSMiniMaxComboCard.self, forKey: .currentComboCard)
        self.modelRemains = try container.decodeIfPresent([iOSMiniMaxModelRemains].self, forKey: .modelRemains) ?? []
    }
}

private struct iOSMiniMaxComboCard: Decodable {
    let title: String?
}

private struct iOSMiniMaxModelRemains: Decodable {
    let currentIntervalTotalCount: Int?
    let currentIntervalUsageCount: Int?
    let startTime: Int?
    let endTime: Int?
    let remainsTime: Int?

    private enum CodingKeys: String, CodingKey {
        case currentIntervalTotalCount = "current_interval_total_count"
        case currentIntervalUsageCount = "current_interval_usage_count"
        case startTime = "start_time"
        case endTime = "end_time"
        case remainsTime = "remains_time"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.currentIntervalTotalCount = iOSMiniMaxDecoding.decodeInt(container, forKey: .currentIntervalTotalCount)
        self.currentIntervalUsageCount = iOSMiniMaxDecoding.decodeInt(container, forKey: .currentIntervalUsageCount)
        self.startTime = iOSMiniMaxDecoding.decodeInt(container, forKey: .startTime)
        self.endTime = iOSMiniMaxDecoding.decodeInt(container, forKey: .endTime)
        self.remainsTime = iOSMiniMaxDecoding.decodeInt(container, forKey: .remainsTime)
    }
}

private struct iOSMiniMaxBaseResponse: Decodable {
    let statusCode: Int?
    let statusMessage: String?

    private enum CodingKeys: String, CodingKey {
        case statusCode = "status_code"
        case statusMessage = "status_msg"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.statusCode = iOSMiniMaxDecoding.decodeInt(container, forKey: .statusCode)
        self.statusMessage = try container.decodeIfPresent(String.self, forKey: .statusMessage)
    }
}

private enum iOSMiniMaxDecoding {
    static func decodeInt<K: CodingKey>(_ container: KeyedDecodingContainer<K>, forKey key: K) -> Int? {
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? container.decodeIfPresent(Int64.self, forKey: key) { return Int(value) }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}

public enum iOSMiniMaxUsageFetcher {
    private static let remainsURL = URL(string: "https://api.minimax.io/v1/api/openplatform/coding_plan/remains")!

    public static func fetchUsage(apiToken: String, now: Date = Date()) async throws -> iOSMiniMaxUsageSnapshot {
        let token = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw iOSMiniMaxUsageError.invalidCredentials }

        var request = URLRequest(url: Self.remainsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("CodexBar iOS", forHTTPHeaderField: "MM-API-Source")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw iOSMiniMaxUsageError.networkError("Invalid response")
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                throw iOSMiniMaxUsageError.invalidCredentials
            }
            guard http.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                throw iOSMiniMaxUsageError.apiError(body)
            }
            return try Self.parseRemainsSnapshot(data, now: now)
        } catch let error as iOSMiniMaxUsageError {
            throw error
        } catch {
            throw iOSMiniMaxUsageError.networkError(error.localizedDescription)
        }
    }

    public static func _parseRemainsSnapshotForTesting(_ data: Data, now: Date = Date()) throws -> iOSMiniMaxUsageSnapshot {
        try Self.parseRemainsSnapshot(data, now: now)
    }

    private static func parseRemainsSnapshot(_ data: Data, now: Date) throws -> iOSMiniMaxUsageSnapshot {
        let decoder = JSONDecoder()
        let payload = try decoder.decode(iOSMiniMaxCodingPlanPayload.self, from: data)
        let baseResponse = payload.data.baseResp ?? payload.baseResp
        if let status = baseResponse?.statusCode, status != 0 {
            let message = baseResponse?.statusMessage ?? "status_code \(status)"
            let lower = message.lowercased()
            if status == 1004 || lower.contains("cookie") || lower.contains("log in") || lower.contains("login") {
                throw iOSMiniMaxUsageError.invalidCredentials
            }
            throw iOSMiniMaxUsageError.apiError(message)
        }

        guard let first = payload.data.modelRemains.first else {
            throw iOSMiniMaxUsageError.parseFailed("Missing coding plan data.")
        }

        let total = first.currentIntervalTotalCount
        let remaining = first.currentIntervalUsageCount
        let usedPercent = Self.usedPercent(total: total, remaining: remaining)
        let start = Self.dateFromEpoch(first.startTime)
        let end = Self.dateFromEpoch(first.endTime)
        let windowMinutes = Self.windowMinutes(start: start, end: end)
        let resetsAt = Self.resetsAt(end: end, remains: first.remainsTime, now: now)
        let planName = Self.parsePlanName(data: payload.data)

        if planName == nil, total == nil, usedPercent == nil {
            throw iOSMiniMaxUsageError.parseFailed("Missing coding plan data.")
        }

        let currentPrompts: Int? = if let total, let remaining {
            max(0, total - remaining)
        } else {
            nil
        }

        return iOSMiniMaxUsageSnapshot(
            planName: planName,
            availablePrompts: total,
            currentPrompts: currentPrompts,
            remainingPrompts: remaining,
            windowMinutes: windowMinutes,
            usedPercent: usedPercent,
            resetsAt: resetsAt,
            updatedAt: now)
    }

    private static func parsePlanName(data: iOSMiniMaxCodingPlanData) -> String? {
        let candidates = [
            data.currentSubscribeTitle,
            data.planName,
            data.comboTitle,
            data.currentPlanTitle,
            data.currentComboCard?.title,
        ].compactMap(\.self)
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    private static func usedPercent(total: Int?, remaining: Int?) -> Double? {
        guard let total, total > 0, let remaining else { return nil }
        let used = max(0, total - remaining)
        return min(100, max(0, (Double(used) / Double(total)) * 100))
    }

    private static func dateFromEpoch(_ value: Int?) -> Date? {
        guard let raw = value else { return nil }
        if raw > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: TimeInterval(raw) / 1000)
        }
        if raw > 1_000_000_000 {
            return Date(timeIntervalSince1970: TimeInterval(raw))
        }
        return nil
    }

    private static func windowMinutes(start: Date?, end: Date?) -> Int? {
        guard let start, let end else { return nil }
        let minutes = Int(end.timeIntervalSince(start) / 60)
        return minutes > 0 ? minutes : nil
    }

    private static func resetsAt(end: Date?, remains: Int?, now: Date) -> Date? {
        if let end, end > now {
            return end
        }
        guard let remains, remains > 0 else { return nil }
        let seconds: TimeInterval = remains > 1_000_000 ? TimeInterval(remains) / 1000 : TimeInterval(remains)
        return now.addingTimeInterval(seconds)
    }
}

public enum iOSMiniMaxUsageMapper {
    public static func makeSnapshot(from usage: iOSMiniMaxUsageSnapshot, generatedAt: Date = Date()) -> iOSWidgetSnapshot {
        let used = max(0, min(100, usage.usedPercent ?? 0))
        let resetDescription: String? = {
            guard let prompts = usage.availablePrompts, prompts > 0 else {
                return Self.windowDescription(minutes: usage.windowMinutes)
            }
            if let window = Self.windowDescription(minutes: usage.windowMinutes) {
                return "\(prompts) prompts / \(window)"
            }
            return "\(prompts) prompts"
        }()

        let entry = iOSWidgetSnapshot.ProviderEntry(
            providerID: "minimax",
            updatedAt: generatedAt,
            primary: iOSWidgetSnapshot.RateWindow(
                usedPercent: used,
                windowMinutes: usage.windowMinutes,
                resetsAt: usage.resetsAt,
                resetDescription: resetDescription),
            secondary: nil,
            tertiary: nil,
            planType: usage.planName,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])

        return iOSWidgetSnapshot(entries: [entry], enabledProviderIDs: ["minimax"], generatedAt: generatedAt)
    }

    private static func windowDescription(minutes: Int?) -> String? {
        guard let minutes, minutes > 0 else { return nil }
        if minutes % (24 * 60) == 0 {
            let days = minutes / (24 * 60)
            return "\(days) \(days == 1 ? "day" : "days")"
        }
        if minutes % 60 == 0 {
            let hours = minutes / 60
            return "\(hours) \(hours == 1 ? "hour" : "hours")"
        }
        return "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
    }
}

// MARK: - Shared credential parsing

private enum iOSProviderCredentialParsing {
    static func cookieValue(named name: String, in credential: String) -> String? {
        for pair in cookiePairs(from: credential) where pair.name.caseInsensitiveCompare(name) == .orderedSame {
            let value = pair.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }

    static func cookiePairs(from credential: String) -> [(name: String, value: String)] {
        credential.split(separator: ";").compactMap { chunk in
            let parts = chunk.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let rawName = parts.first else { return nil }
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let value = parts.count > 1 ? String(parts[1]) : ""
            return (name, value)
        }
    }

    static func splitCredentialAndContext(_ raw: String, separator: String = "||") -> (credential: String, context: String?) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: separator) else {
            return (trimmed, nil)
        }
        let credential = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let context = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (credential, context.isEmpty ? nil : context)
    }
}

private enum iOSISO8601 {
    static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: value) {
            return date
        }
        let normal = ISO8601DateFormatter()
        normal.formatOptions = [.withInternetDateTime]
        return normal.date(from: value)
    }
}

// MARK: - Claude Web (session cookie)

public struct iOSClaudeWebUsageSnapshot: Sendable {
    public let sessionPercentUsed: Double
    public let sessionResetsAt: Date?
    public let weeklyPercentUsed: Double?
    public let weeklyResetsAt: Date?
    public let opusPercentUsed: Double?
    public let planName: String?
    public let updatedAt: Date
}

public enum iOSClaudeWebUsageError: LocalizedError, Sendable {
    case missingSessionKey
    case unauthorized
    case invalidResponse
    case apiError(String)
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .missingSessionKey:
            "Missing Claude session key. Paste `sessionKey=...` cookie or `sk-ant-...` key."
        case .unauthorized:
            "Claude session is unauthorized or expired."
        case .invalidResponse:
            "Invalid Claude usage response."
        case let .apiError(message):
            "Claude API error: \(message)"
        case let .networkError(message):
            "Claude network error: \(message)"
        }
    }
}

private struct iOSClaudeOrganizationResponse: Decodable {
    let uuid: String
    let capabilities: [String]?

    var hasChatCapability: Bool {
        Set((self.capabilities ?? []).map { $0.lowercased() }).contains("chat")
    }
}

private struct iOSClaudeAccountResponse: Decodable {
    let memberships: [Membership]?

    struct Membership: Decodable {
        let organization: Organization

        struct Organization: Decodable {
            let uuid: String?
            let rateLimitTier: String?
            let billingType: String?

            enum CodingKeys: String, CodingKey {
                case uuid
                case rateLimitTier = "rate_limit_tier"
                case billingType = "billing_type"
            }
        }
    }
}

public enum iOSClaudeWebUsageFetcher {
    private static let apiBaseURL = URL(string: "https://claude.ai/api")!

    public static func fetchUsage(sessionCredential: String) async throws -> iOSClaudeWebUsageSnapshot {
        let sessionKey = try self.parseSessionKey(from: sessionCredential)
        let organizationID = try await self.fetchOrganizationID(sessionKey: sessionKey)
        let usageData = try await self.fetchUsagePayload(sessionKey: sessionKey, organizationID: organizationID)
        let plan = await self.fetchPlanName(sessionKey: sessionKey, organizationID: organizationID)
        return try self.parseUsageSnapshot(data: usageData, planName: plan, now: Date())
    }

    public static func _parseUsageSnapshotForTesting(_ data: Data, planName: String? = nil, now: Date = Date()) throws
        -> iOSClaudeWebUsageSnapshot
    {
        try self.parseUsageSnapshot(data: data, planName: planName, now: now)
    }

    private static func parseSessionKey(from raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("sk-ant-") {
            return trimmed
        }
        if let cookie = iOSProviderCredentialParsing.cookieValue(named: "sessionKey", in: trimmed),
           cookie.hasPrefix("sk-ant-")
        {
            return cookie
        }
        throw iOSClaudeWebUsageError.missingSessionKey
    }

    private static func fetchOrganizationID(sessionKey: String) async throws -> String {
        let url = self.apiBaseURL.appendingPathComponent("organizations")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw iOSClaudeWebUsageError.invalidResponse
        }
        switch http.statusCode {
        case 200:
            let organizations = try JSONDecoder().decode([iOSClaudeOrganizationResponse].self, from: data)
            if let preferred = organizations.first(where: { $0.hasChatCapability }) ?? organizations.first {
                return preferred.uuid
            }
            throw iOSClaudeWebUsageError.invalidResponse
        case 401, 403:
            throw iOSClaudeWebUsageError.unauthorized
        default:
            throw iOSClaudeWebUsageError.apiError("HTTP \(http.statusCode)")
        }
    }

    private static func fetchUsagePayload(sessionKey: String, organizationID: String) async throws -> Data {
        let url = self.apiBaseURL.appendingPathComponent("organizations/\(organizationID)/usage")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw iOSClaudeWebUsageError.invalidResponse
        }
        switch http.statusCode {
        case 200:
            return data
        case 401, 403:
            throw iOSClaudeWebUsageError.unauthorized
        default:
            throw iOSClaudeWebUsageError.apiError("HTTP \(http.statusCode)")
        }
    }

    private static func fetchPlanName(sessionKey: String, organizationID: String) async -> String? {
        let url = self.apiBaseURL.appendingPathComponent("account")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            let account = try JSONDecoder().decode(iOSClaudeAccountResponse.self, from: data)
            let membership = account.memberships?.first(where: { $0.organization.uuid == organizationID })
                ?? account.memberships?.first
            return self.inferPlanName(
                rateLimitTier: membership?.organization.rateLimitTier,
                billingType: membership?.organization.billingType)
        } catch {
            return nil
        }
    }

    private static func inferPlanName(rateLimitTier: String?, billingType: String?) -> String? {
        let tier = rateLimitTier?.lowercased() ?? ""
        let billing = billingType?.lowercased() ?? ""
        if tier.contains("max") { return "Claude Max" }
        if tier.contains("pro") { return "Claude Pro" }
        if tier.contains("team") { return "Claude Team" }
        if tier.contains("enterprise") { return "Claude Enterprise" }
        if billing.contains("stripe"), tier.contains("claude") { return "Claude Pro" }
        return nil
    }

    private static func parseUsageSnapshot(data: Data, planName: String?, now: Date) throws -> iOSClaudeWebUsageSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw iOSClaudeWebUsageError.invalidResponse
        }

        guard let fiveHour = json["five_hour"] as? [String: Any],
              let sessionPercent = (fiveHour["utilization"] as? NSNumber)?.doubleValue,
              let sessionResetRaw = fiveHour["resets_at"] as? String
        else {
            throw iOSClaudeWebUsageError.invalidResponse
        }

        let weekly = json["seven_day"] as? [String: Any]
        let weeklyPercent = (weekly?["utilization"] as? NSNumber)?.doubleValue
        let weeklyResetRaw = weekly?["resets_at"] as? String

        let opus = json["seven_day_opus"] as? [String: Any]
        let opusPercent = (opus?["utilization"] as? NSNumber)?.doubleValue

        return iOSClaudeWebUsageSnapshot(
            sessionPercentUsed: sessionPercent,
            sessionResetsAt: iOSISO8601.parse(sessionResetRaw),
            weeklyPercentUsed: weeklyPercent,
            weeklyResetsAt: iOSISO8601.parse(weeklyResetRaw),
            opusPercentUsed: opusPercent,
            planName: planName,
            updatedAt: now)
    }
}

public enum iOSClaudeWebUsageMapper {
    public static func makeSnapshot(from usage: iOSClaudeWebUsageSnapshot, generatedAt: Date = Date()) -> iOSWidgetSnapshot {
        let entry = iOSWidgetSnapshot.ProviderEntry(
            providerID: "claude",
            updatedAt: generatedAt,
            primary: .init(
                usedPercent: max(0, min(100, usage.sessionPercentUsed)),
                windowMinutes: 5 * 60,
                resetsAt: usage.sessionResetsAt,
                resetDescription: "5h window"),
            secondary: usage.weeklyPercentUsed.map {
                .init(
                    usedPercent: max(0, min(100, $0)),
                    windowMinutes: 7 * 24 * 60,
                    resetsAt: usage.weeklyResetsAt,
                    resetDescription: "7d window")
            },
            tertiary: usage.opusPercentUsed.map {
                .init(
                    usedPercent: max(0, min(100, $0)),
                    windowMinutes: 7 * 24 * 60,
                    resetsAt: usage.weeklyResetsAt,
                    resetDescription: "7d Opus")
            },
            planType: usage.planName,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])

        return iOSWidgetSnapshot(entries: [entry], enabledProviderIDs: ["claude"], generatedAt: generatedAt)
    }
}

// MARK: - Cursor (cookie header)

public struct iOSCursorUsageSnapshot: Sendable {
    public let planPercentUsed: Double
    public let onDemandUsedUSD: Double
    public let onDemandLimitUSD: Double?
    public let billingCycleEnd: Date?
    public let membershipType: String?
    public let updatedAt: Date
}

public enum iOSCursorUsageError: LocalizedError, Sendable {
    case invalidCredentials
    case networkError(String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "Cursor session cookie is invalid or expired."
        case let .networkError(message):
            "Cursor network error: \(message)"
        case let .parseFailed(message):
            "Cursor parse error: \(message)"
        }
    }
}

private struct iOSCursorUsageSummaryResponse: Decodable {
    let billingCycleEnd: String?
    let membershipType: String?
    let individualUsage: IndividualUsage?

    struct IndividualUsage: Decodable {
        let plan: PlanUsage?
        let onDemand: OnDemandUsage?
    }

    struct PlanUsage: Decodable {
        let used: Int?
        let limit: Int?
        let totalPercentUsed: Double?
    }

    struct OnDemandUsage: Decodable {
        let used: Int?
        let limit: Int?
    }

    enum CodingKeys: String, CodingKey {
        case billingCycleEnd
        case membershipType
        case individualUsage
    }
}

public enum iOSCursorUsageFetcher {
    private static let baseURL = URL(string: "https://cursor.com")!

    public static func fetchUsage(cookieHeader: String) async throws -> iOSCursorUsageSnapshot {
        let normalizedCookie = cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCookie.isEmpty else {
            throw iOSCursorUsageError.invalidCredentials
        }

        var request = URLRequest(url: Self.baseURL.appendingPathComponent("api/usage-summary"))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(normalizedCookie, forHTTPHeaderField: "Cookie")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw iOSCursorUsageError.networkError("Invalid response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw iOSCursorUsageError.invalidCredentials
        }
        guard http.statusCode == 200 else {
            throw iOSCursorUsageError.networkError("HTTP \(http.statusCode)")
        }
        return try self.parseUsageSnapshot(data: data, now: Date())
    }

    public static func _parseUsageSnapshotForTesting(_ data: Data, now: Date = Date()) throws -> iOSCursorUsageSnapshot {
        try self.parseUsageSnapshot(data: data, now: now)
    }

    private static func parseUsageSnapshot(data: Data, now: Date) throws -> iOSCursorUsageSnapshot {
        let summary = try JSONDecoder().decode(iOSCursorUsageSummaryResponse.self, from: data)

        let planUsedRaw = Double(summary.individualUsage?.plan?.used ?? 0)
        let planLimitRaw = Double(summary.individualUsage?.plan?.limit ?? 0)
        let planPercentUsed: Double = if planLimitRaw > 0 {
            (planUsedRaw / planLimitRaw) * 100
        } else if let totalPercentUsed = summary.individualUsage?.plan?.totalPercentUsed {
            totalPercentUsed <= 1 ? totalPercentUsed * 100 : totalPercentUsed
        } else {
            0
        }

        let onDemandUsedUSD = Double(summary.individualUsage?.onDemand?.used ?? 0) / 100.0
        let onDemandLimitUSD = summary.individualUsage?.onDemand?.limit.map { Double($0) / 100.0 }
        let billingEnd = iOSISO8601.parse(summary.billingCycleEnd)

        return iOSCursorUsageSnapshot(
            planPercentUsed: max(0, min(100, planPercentUsed)),
            onDemandUsedUSD: onDemandUsedUSD,
            onDemandLimitUSD: onDemandLimitUSD,
            billingCycleEnd: billingEnd,
            membershipType: summary.membershipType,
            updatedAt: now)
    }
}

public enum iOSCursorUsageMapper {
    public static func makeSnapshot(from usage: iOSCursorUsageSnapshot, generatedAt: Date = Date()) -> iOSWidgetSnapshot {
        let secondary: iOSWidgetSnapshot.RateWindow? = {
            guard let limit = usage.onDemandLimitUSD, limit > 0 else { return nil }
            let percent = max(0, min(100, (usage.onDemandUsedUSD / limit) * 100))
            return .init(
                usedPercent: percent,
                windowMinutes: nil,
                resetsAt: usage.billingCycleEnd,
                resetDescription: "On-demand")
        }()

        let entry = iOSWidgetSnapshot.ProviderEntry(
            providerID: "cursor",
            updatedAt: generatedAt,
            primary: .init(
                usedPercent: usage.planPercentUsed,
                windowMinutes: nil,
                resetsAt: usage.billingCycleEnd,
                resetDescription: "Plan usage"),
            secondary: secondary,
            tertiary: nil,
            planType: usage.membershipType,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])

        return iOSWidgetSnapshot(entries: [entry], enabledProviderIDs: ["cursor"], generatedAt: generatedAt)
    }
}

// MARK: - OpenCode (cookie header)

public struct iOSOpenCodeUsageSnapshot: Sendable {
    public let rollingUsagePercent: Double
    public let weeklyUsagePercent: Double
    public let rollingResetInSec: Int
    public let weeklyResetInSec: Int
    public let updatedAt: Date
}

public enum iOSOpenCodeUsageError: LocalizedError, Sendable {
    case invalidCredentials
    case networkError(String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "OpenCode session cookie is invalid or expired."
        case let .networkError(message):
            "OpenCode network error: \(message)"
        case let .parseFailed(message):
            "OpenCode parse error: \(message)"
        }
    }
}

public enum iOSOpenCodeUsageFetcher {
    private static let baseURL = URL(string: "https://opencode.ai")!
    private static let serverURL = URL(string: "https://opencode.ai/_server")!
    private static let workspacesServerID = "def39973159c7f0483d8793a822b8dbb10d067e12c65455fcb4608459ba0234f"
    private static let subscriptionServerID = "7abeebee372f304e050aaaf92be863f4a86490e382f8c79db68fd94040d691b4"

    public static func fetchUsage(cookieCredential: String) async throws -> iOSOpenCodeUsageSnapshot {
        let parsed = iOSProviderCredentialParsing.splitCredentialAndContext(cookieCredential)
        let cookieHeader = parsed.credential
        guard !cookieHeader.isEmpty else {
            throw iOSOpenCodeUsageError.invalidCredentials
        }
        let workspaceID: String
        if let explicit = parsed.context, !explicit.isEmpty {
            workspaceID = explicit
        } else {
            workspaceID = try await self.fetchWorkspaceID(cookieHeader: cookieHeader)
        }
        let subscriptionText = try await self.fetchSubscriptionInfo(
            workspaceID: workspaceID,
            cookieHeader: cookieHeader)
        return try self.parseSubscription(text: subscriptionText, now: Date())
    }

    public static func _parseSubscriptionForTesting(_ text: String, now: Date = Date()) throws -> iOSOpenCodeUsageSnapshot {
        try self.parseSubscription(text: text, now: now)
    }

    private static func fetchWorkspaceID(cookieHeader: String) async throws -> String {
        let text = try await self.fetchServerText(
            serverID: self.workspacesServerID,
            args: nil,
            method: "GET",
            referer: self.baseURL,
            cookieHeader: cookieHeader)
        if self.looksSignedOut(text) {
            throw iOSOpenCodeUsageError.invalidCredentials
        }
        let ids = self.parseWorkspaceIDs(text: text)
        if let first = ids.first {
            return first
        }
        throw iOSOpenCodeUsageError.parseFailed("Missing workspace id")
    }

    private static func fetchSubscriptionInfo(
        workspaceID: String,
        cookieHeader: String) async throws -> String
    {
        let referer = URL(string: "https://opencode.ai/workspace/\(workspaceID)/billing") ?? self.baseURL
        let text = try await self.fetchServerText(
            serverID: self.subscriptionServerID,
            args: [workspaceID],
            method: "GET",
            referer: referer,
            cookieHeader: cookieHeader)
        if self.looksSignedOut(text) {
            throw iOSOpenCodeUsageError.invalidCredentials
        }
        return text
    }

    private static func fetchServerText(
        serverID: String,
        args: [Any]?,
        method: String,
        referer: URL,
        cookieHeader: String) async throws -> String
    {
        let url = self.serverRequestURL(serverID: serverID, args: args, method: method)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue(serverID, forHTTPHeaderField: "X-Server-Id")
        request.setValue("server-fn:\(UUID().uuidString)", forHTTPHeaderField: "X-Server-Instance")
        request.setValue(self.baseURL.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue("text/javascript, application/json;q=0.9, */*;q=0.8", forHTTPHeaderField: "Accept")

        if method.uppercased() != "GET",
           let args,
           let body = try? JSONSerialization.data(withJSONObject: args, options: [])
        {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw iOSOpenCodeUsageError.networkError("Invalid response")
        }

        guard http.statusCode == 200 else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw iOSOpenCodeUsageError.invalidCredentials
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            throw iOSOpenCodeUsageError.networkError("HTTP \(http.statusCode): \(body.prefix(120))")
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw iOSOpenCodeUsageError.parseFailed("Response is not UTF-8")
        }
        return text
    }

    private static func serverRequestURL(serverID: String, args: [Any]?, method: String) -> URL {
        guard method.uppercased() == "GET" else {
            return self.serverURL
        }
        var components = URLComponents(url: self.serverURL, resolvingAgainstBaseURL: false)
        var items = [URLQueryItem(name: "id", value: serverID)]
        if let args, !args.isEmpty,
           let data = try? JSONSerialization.data(withJSONObject: args, options: []),
           let encoded = String(data: data, encoding: .utf8)
        {
            items.append(URLQueryItem(name: "args", value: encoded))
        }
        components?.queryItems = items
        return components?.url ?? self.serverURL
    }

    private static func parseSubscription(text: String, now: Date) throws -> iOSOpenCodeUsageSnapshot {
        guard let rollingPercent = self.extractDouble(
            pattern: #"rollingUsage[^}]*?usagePercent\s*:\s*([0-9]+(?:\.[0-9]+)?)"#,
            text: text),
            let rollingReset = self.extractInt(
                pattern: #"rollingUsage[^}]*?resetInSec\s*:\s*([0-9]+)"#,
                text: text),
            let weeklyPercent = self.extractDouble(
                pattern: #"weeklyUsage[^}]*?usagePercent\s*:\s*([0-9]+(?:\.[0-9]+)?)"#,
                text: text),
            let weeklyReset = self.extractInt(
                pattern: #"weeklyUsage[^}]*?resetInSec\s*:\s*([0-9]+)"#,
                text: text)
        else {
            throw iOSOpenCodeUsageError.parseFailed("Missing usage fields")
        }

        return iOSOpenCodeUsageSnapshot(
            rollingUsagePercent: rollingPercent,
            weeklyUsagePercent: weeklyPercent,
            rollingResetInSec: rollingReset,
            weeklyResetInSec: weeklyReset,
            updatedAt: now)
    }

    private static func parseWorkspaceIDs(text: String) -> [String] {
        let pattern = #"id\s*:\s*\"(wrk_[^\"]+)\""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard let matchRange = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[matchRange])
        }
    }

    private static func extractDouble(pattern: String, text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let matchRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return Double(text[matchRange])
    }

    private static func extractInt(pattern: String, text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let matchRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return Int(text[matchRange])
    }

    private static func looksSignedOut(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("login") || lower.contains("sign in") || lower.contains("auth/authorize")
    }
}

public enum iOSOpenCodeUsageMapper {
    public static func makeSnapshot(from usage: iOSOpenCodeUsageSnapshot, generatedAt: Date = Date()) -> iOSWidgetSnapshot {
        let rollingReset = generatedAt.addingTimeInterval(TimeInterval(usage.rollingResetInSec))
        let weeklyReset = generatedAt.addingTimeInterval(TimeInterval(usage.weeklyResetInSec))

        let entry = iOSWidgetSnapshot.ProviderEntry(
            providerID: "opencode",
            updatedAt: generatedAt,
            primary: .init(
                usedPercent: max(0, min(100, usage.rollingUsagePercent)),
                windowMinutes: 5 * 60,
                resetsAt: rollingReset,
                resetDescription: "5h window"),
            secondary: .init(
                usedPercent: max(0, min(100, usage.weeklyUsagePercent)),
                windowMinutes: 7 * 24 * 60,
                resetsAt: weeklyReset,
                resetDescription: "7d window"),
            tertiary: nil,
            planType: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])

        return iOSWidgetSnapshot(entries: [entry], enabledProviderIDs: ["opencode"], generatedAt: generatedAt)
    }
}

// MARK: - Augment (cookie header)

private struct iOSAugmentCreditsResponse: Codable {
    let usageUnitsRemaining: Double?
    let usageUnitsConsumedThisBillingCycle: Double?
}

private struct iOSAugmentSubscriptionResponse: Codable {
    let planName: String?
    let billingPeriodEnd: String?
}

public struct iOSAugmentUsageSnapshot: Sendable {
    public let creditsRemaining: Double?
    public let creditsUsed: Double?
    public let creditsLimit: Double?
    public let billingCycleEnd: Date?
    public let planName: String?
    public let updatedAt: Date
}

public enum iOSAugmentUsageError: LocalizedError, Sendable {
    case invalidCredentials
    case networkError(String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "Augment session cookie is invalid or expired."
        case let .networkError(message):
            "Augment network error: \(message)"
        case let .parseFailed(message):
            "Augment parse error: \(message)"
        }
    }
}

public enum iOSAugmentUsageFetcher {
    private static let baseURL = URL(string: "https://app.augmentcode.com")!

    public static func fetchUsage(cookieHeader: String) async throws -> iOSAugmentUsageSnapshot {
        let cookie = cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cookie.isEmpty else { throw iOSAugmentUsageError.invalidCredentials }

        async let creditsTask: (iOSAugmentCreditsResponse, Data) = self.fetchCredits(cookieHeader: cookie)
        async let subscriptionTask: (iOSAugmentSubscriptionResponse?, Data?) = self.fetchSubscription(cookieHeader: cookie)

        let (credits, _) = try await creditsTask
        let (subscription, _) = try await subscriptionTask

        let remaining = credits.usageUnitsRemaining
        let used = credits.usageUnitsConsumedThisBillingCycle
        let limit: Double? = {
            guard let remaining, let used else { return nil }
            return remaining + used
        }()

        return iOSAugmentUsageSnapshot(
            creditsRemaining: remaining,
            creditsUsed: used,
            creditsLimit: limit,
            billingCycleEnd: iOSISO8601.parse(subscription?.billingPeriodEnd),
            planName: subscription?.planName,
            updatedAt: Date())
    }

    private static func fetchCredits(cookieHeader: String) async throws -> (iOSAugmentCreditsResponse, Data) {
        var request = URLRequest(url: self.baseURL.appendingPathComponent("api/credits"))
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw iOSAugmentUsageError.networkError("Invalid response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw iOSAugmentUsageError.invalidCredentials
        }
        guard http.statusCode == 200 else {
            throw iOSAugmentUsageError.networkError("HTTP \(http.statusCode)")
        }

        do {
            return (try JSONDecoder().decode(iOSAugmentCreditsResponse.self, from: data), data)
        } catch {
            throw iOSAugmentUsageError.parseFailed(error.localizedDescription)
        }
    }

    private static func fetchSubscription(cookieHeader: String) async throws -> (iOSAugmentSubscriptionResponse?, Data?) {
        var request = URLRequest(url: self.baseURL.appendingPathComponent("api/subscription"))
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw iOSAugmentUsageError.networkError("Invalid response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw iOSAugmentUsageError.invalidCredentials
        }
        guard http.statusCode == 200 else {
            return (nil, nil)
        }
        return (try? JSONDecoder().decode(iOSAugmentSubscriptionResponse.self, from: data), data)
    }
}

public enum iOSAugmentUsageMapper {
    public static func makeSnapshot(from usage: iOSAugmentUsageSnapshot, generatedAt: Date = Date()) -> iOSWidgetSnapshot {
        let usedPercent: Double = {
            guard let used = usage.creditsUsed, let limit = usage.creditsLimit, limit > 0 else { return 0 }
            return max(0, min(100, (used / limit) * 100))
        }()

        let entry = iOSWidgetSnapshot.ProviderEntry(
            providerID: "augment",
            updatedAt: generatedAt,
            primary: .init(
                usedPercent: usedPercent,
                windowMinutes: nil,
                resetsAt: usage.billingCycleEnd,
                resetDescription: "Billing cycle"),
            secondary: nil,
            tertiary: nil,
            planType: usage.planName,
            creditsRemaining: usage.creditsRemaining,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])

        return iOSWidgetSnapshot(entries: [entry], enabledProviderIDs: ["augment"], generatedAt: generatedAt)
    }
}

// MARK: - Factory (cookie header)

private struct iOSFactoryAuthResponse: Codable {
    let organization: Organization?

    struct Organization: Codable {
        let name: String?
        let subscription: Subscription?

        struct Subscription: Codable {
            let factoryTier: String?
            let orbSubscription: OrbSubscription?

            struct OrbSubscription: Codable {
                let plan: Plan?

                struct Plan: Codable {
                    let name: String?
                }
            }
        }
    }
}

private struct iOSFactoryUsageResponse: Codable {
    let usage: Usage?

    struct Usage: Codable {
        let startDate: Int64?
        let endDate: Int64?
        let standard: Bucket?
        let premium: Bucket?

        struct Bucket: Codable {
            let userTokens: Int64?
            let totalAllowance: Int64?
            let usedRatio: Double?
        }
    }
}

public struct iOSFactoryUsageSnapshot: Sendable {
    public let standardUsedPercent: Double
    public let premiumUsedPercent: Double?
    public let periodEnd: Date?
    public let planName: String?
    public let tier: String?
    public let updatedAt: Date
}

public enum iOSFactoryUsageError: LocalizedError, Sendable {
    case invalidCredentials
    case networkError(String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "Factory session cookie is invalid or expired."
        case let .networkError(message):
            "Factory network error: \(message)"
        case let .parseFailed(message):
            "Factory parse error: \(message)"
        }
    }
}

public enum iOSFactoryUsageFetcher {
    private static let baseURL = URL(string: "https://app.factory.ai")!

    public static func fetchUsage(cookieHeader: String) async throws -> iOSFactoryUsageSnapshot {
        let cookie = cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cookie.isEmpty else {
            throw iOSFactoryUsageError.invalidCredentials
        }

        let bearerToken = iOSProviderCredentialParsing.cookieValue(named: "access-token", in: cookie)

        async let authTask = self.fetchAuth(cookieHeader: cookie, bearerToken: bearerToken)
        async let usageTask = self.fetchUsageData(cookieHeader: cookie, bearerToken: bearerToken)

        let auth = try await authTask
        let usage = try await usageTask

        let standardPercent = self.percentUsed(
            used: usage.usage?.standard?.userTokens,
            allowance: usage.usage?.standard?.totalAllowance,
            ratio: usage.usage?.standard?.usedRatio)

        let premiumAllowance = usage.usage?.premium?.totalAllowance ?? 0
        let premiumPercentRaw = self.percentUsed(
            used: usage.usage?.premium?.userTokens,
            allowance: usage.usage?.premium?.totalAllowance,
            ratio: usage.usage?.premium?.usedRatio)
        let premiumPercent = premiumAllowance > 0 ? premiumPercentRaw : nil

        let periodEnd = usage.usage?.endDate.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }

        return iOSFactoryUsageSnapshot(
            standardUsedPercent: standardPercent,
            premiumUsedPercent: premiumPercent,
            periodEnd: periodEnd,
            planName: auth.organization?.subscription?.orbSubscription?.plan?.name,
            tier: auth.organization?.subscription?.factoryTier,
            updatedAt: Date())
    }

    private static func fetchAuth(cookieHeader: String, bearerToken: String?) async throws -> iOSFactoryAuthResponse {
        var request = URLRequest(url: self.baseURL.appendingPathComponent("api/app/auth/me"))
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://app.factory.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://app.factory.ai/", forHTTPHeaderField: "Referer")
        request.setValue("web-app", forHTTPHeaderField: "x-factory-client")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw iOSFactoryUsageError.networkError("Invalid response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw iOSFactoryUsageError.invalidCredentials
        }
        guard http.statusCode == 200 else {
            throw iOSFactoryUsageError.networkError("HTTP \(http.statusCode)")
        }

        do {
            return try JSONDecoder().decode(iOSFactoryAuthResponse.self, from: data)
        } catch {
            throw iOSFactoryUsageError.parseFailed(error.localizedDescription)
        }
    }

    private static func fetchUsageData(cookieHeader: String, bearerToken: String?) async throws -> iOSFactoryUsageResponse {
        var request = URLRequest(url: self.baseURL.appendingPathComponent("api/organization/subscription/usage"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://app.factory.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://app.factory.ai/", forHTTPHeaderField: "Referer")
        request.setValue("web-app", forHTTPHeaderField: "x-factory-client")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["useCache": true], options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw iOSFactoryUsageError.networkError("Invalid response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw iOSFactoryUsageError.invalidCredentials
        }
        guard http.statusCode == 200 else {
            throw iOSFactoryUsageError.networkError("HTTP \(http.statusCode)")
        }

        do {
            return try JSONDecoder().decode(iOSFactoryUsageResponse.self, from: data)
        } catch {
            throw iOSFactoryUsageError.parseFailed(error.localizedDescription)
        }
    }

    private static func percentUsed(used: Int64?, allowance: Int64?, ratio: Double?) -> Double {
        if let ratio {
            if ratio <= 1 { return max(0, min(100, ratio * 100)) }
            return max(0, min(100, ratio))
        }
        guard let used, let allowance, allowance > 0 else { return 0 }
        return max(0, min(100, (Double(used) / Double(allowance)) * 100))
    }
}

public enum iOSFactoryUsageMapper {
    public static func makeSnapshot(from usage: iOSFactoryUsageSnapshot, generatedAt: Date = Date()) -> iOSWidgetSnapshot {
        let planBits = [usage.tier, usage.planName].compactMap { value -> String? in
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let planType = planBits.isEmpty ? nil : planBits.joined(separator: " • ")

        let entry = iOSWidgetSnapshot.ProviderEntry(
            providerID: "factory",
            updatedAt: generatedAt,
            primary: .init(
                usedPercent: usage.standardUsedPercent,
                windowMinutes: nil,
                resetsAt: usage.periodEnd,
                resetDescription: "Standard tokens"),
            secondary: usage.premiumUsedPercent.map {
                .init(
                    usedPercent: $0,
                    windowMinutes: nil,
                    resetsAt: usage.periodEnd,
                    resetDescription: "Premium tokens")
            },
            tertiary: nil,
            planType: planType,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])

        return iOSWidgetSnapshot(entries: [entry], enabledProviderIDs: ["factory"], generatedAt: generatedAt)
    }
}

// MARK: - Amp (cookie header)

public struct iOSAmpUsageSnapshot: Sendable {
    public let freeQuota: Double
    public let freeUsed: Double
    public let hourlyReplenishment: Double
    public let windowHours: Double?
    public let updatedAt: Date
}

public enum iOSAmpUsageError: LocalizedError, Sendable {
    case invalidCredentials
    case parseFailed(String)
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "Amp session cookie is invalid or expired."
        case let .parseFailed(message):
            "Amp parse error: \(message)"
        case let .networkError(message):
            "Amp network error: \(message)"
        }
    }
}

public enum iOSAmpUsageFetcher {
    private static let settingsURL = URL(string: "https://ampcode.com/settings")!

    public static func fetchUsage(cookieHeader: String) async throws -> iOSAmpUsageSnapshot {
        let cookie = cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cookie.isEmpty else { throw iOSAmpUsageError.invalidCredentials }

        var request = URLRequest(url: self.settingsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue(
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            forHTTPHeaderField: "accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw iOSAmpUsageError.networkError("Invalid response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw iOSAmpUsageError.invalidCredentials
        }
        guard http.statusCode == 200 else {
            throw iOSAmpUsageError.networkError("HTTP \(http.statusCode)")
        }

        let html = String(data: data, encoding: .utf8) ?? ""
        return try self.parseUsageSnapshot(html: html, now: Date())
    }

    public static func _parseUsageSnapshotForTesting(html: String, now: Date = Date()) throws -> iOSAmpUsageSnapshot {
        try self.parseUsageSnapshot(html: html, now: now)
    }

    private static func parseUsageSnapshot(html: String, now: Date) throws -> iOSAmpUsageSnapshot {
        guard let usage = self.parseFreeTierUsage(html) else {
            if self.looksSignedOut(html) {
                throw iOSAmpUsageError.invalidCredentials
            }
            throw iOSAmpUsageError.parseFailed("Missing free tier usage data")
        }

        return iOSAmpUsageSnapshot(
            freeQuota: usage.quota,
            freeUsed: usage.used,
            hourlyReplenishment: usage.hourlyReplenishment,
            windowHours: usage.windowHours,
            updatedAt: now)
    }

    private struct FreeTierUsage {
        let quota: Double
        let used: Double
        let hourlyReplenishment: Double
        let windowHours: Double?
    }

    private static func parseFreeTierUsage(_ html: String) -> FreeTierUsage? {
        for token in ["freeTierUsage", "getFreeTierUsage"] {
            if let object = self.extractObject(named: token, in: html),
               let quota = self.number(for: "quota", in: object),
               let used = self.number(for: "used", in: object),
               let hourly = self.number(for: "hourlyReplenishment", in: object)
            {
                return FreeTierUsage(
                    quota: quota,
                    used: used,
                    hourlyReplenishment: hourly,
                    windowHours: self.number(for: "windowHours", in: object))
            }
        }
        return nil
    }

    private static func extractObject(named token: String, in text: String) -> String? {
        guard let tokenRange = text.range(of: token),
              let braceIndex = text[tokenRange.upperBound...].firstIndex(of: "{")
        else {
            return nil
        }

        var depth = 0
        var inString = false
        var escaped = false
        var idx = braceIndex
        while idx < text.endIndex {
            let ch = text[idx]
            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
            } else {
                if ch == "\"" {
                    inString = true
                } else if ch == "{" {
                    depth += 1
                } else if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(text[braceIndex...idx])
                    }
                }
            }
            idx = text.index(after: idx)
        }
        return nil
    }

    private static func number(for key: String, in text: String) -> Double? {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: key))\\b\\s*:\\s*([0-9]+(?:\\.[0-9]+)?)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let valueRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return Double(text[valueRange])
    }

    private static func looksSignedOut(_ html: String) -> Bool {
        let lower = html.lowercased()
        return lower.contains("sign in") || lower.contains("log in") || lower.contains("/login")
    }
}

public enum iOSAmpUsageMapper {
    public static func makeSnapshot(from usage: iOSAmpUsageSnapshot, generatedAt: Date = Date()) -> iOSWidgetSnapshot {
        let quota = max(0, usage.freeQuota)
        let used = max(0, usage.freeUsed)
        let usedPercent = quota > 0 ? min(100, (used / quota) * 100) : 0
        let windowMinutes: Int? = usage.windowHours.map { Int(($0 * 60).rounded()) }

        let resetsAt: Date? = {
            guard quota > 0, usage.hourlyReplenishment > 0 else { return nil }
            let hoursToFull = used / usage.hourlyReplenishment
            return generatedAt.addingTimeInterval(max(0, hoursToFull * 3600))
        }()

        let entry = iOSWidgetSnapshot.ProviderEntry(
            providerID: "amp",
            updatedAt: generatedAt,
            primary: .init(
                usedPercent: usedPercent,
                windowMinutes: windowMinutes,
                resetsAt: resetsAt,
                resetDescription: "Amp Free"),
            secondary: nil,
            tertiary: nil,
            planType: "Amp Free",
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])

        return iOSWidgetSnapshot(entries: [entry], enabledProviderIDs: ["amp"], generatedAt: generatedAt)
    }
}

// MARK: - Gemini (access token)

public struct iOSGeminiModelQuota: Sendable {
    public let modelID: String
    public let percentLeft: Double
    public let resetTime: Date?
}

public struct iOSGeminiUsageSnapshot: Sendable {
    public let modelQuotas: [iOSGeminiModelQuota]
    public let planName: String?
    public let updatedAt: Date
}

public enum iOSGeminiUsageError: LocalizedError, Sendable {
    case invalidCredentials
    case networkError(String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "Gemini access token is invalid or expired."
        case let .networkError(message):
            "Gemini network error: \(message)"
        case let .parseFailed(message):
            "Gemini parse error: \(message)"
        }
    }
}

private struct iOSGeminiQuotaBucket: Decodable {
    let remainingFraction: Double?
    let resetTime: String?
    let modelId: String?
}

private struct iOSGeminiQuotaResponse: Decodable {
    let buckets: [iOSGeminiQuotaBucket]?
}

public enum iOSGeminiUsageFetcher {
    private static let quotaEndpoint = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")!

    public static func fetchUsage(accessToken: String, projectID: String? = nil) async throws -> iOSGeminiUsageSnapshot {
        let token = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw iOSGeminiUsageError.invalidCredentials }

        var request = URLRequest(url: self.quotaEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let projectID, !projectID.isEmpty {
            request.httpBody = Data("{\"project\": \"\(projectID)\"}".utf8)
        } else {
            request.httpBody = Data("{}".utf8)
        }
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw iOSGeminiUsageError.networkError("Invalid response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw iOSGeminiUsageError.invalidCredentials
        }
        guard http.statusCode == 200 else {
            throw iOSGeminiUsageError.networkError("HTTP \(http.statusCode)")
        }

        return try self.parseUsageSnapshot(data: data, now: Date())
    }

    public static func _parseUsageSnapshotForTesting(_ data: Data, now: Date = Date()) throws -> iOSGeminiUsageSnapshot {
        try self.parseUsageSnapshot(data: data, now: now)
    }

    private static func parseUsageSnapshot(data: Data, now: Date) throws -> iOSGeminiUsageSnapshot {
        let response = try JSONDecoder().decode(iOSGeminiQuotaResponse.self, from: data)
        guard let buckets = response.buckets, !buckets.isEmpty else {
            throw iOSGeminiUsageError.parseFailed("Missing quota buckets")
        }

        var modelQuotaMap: [String: (fraction: Double, reset: String?)] = [:]
        for bucket in buckets {
            guard let model = bucket.modelId,
                  let fraction = bucket.remainingFraction
            else {
                continue
            }
            if let existing = modelQuotaMap[model] {
                if fraction < existing.fraction {
                    modelQuotaMap[model] = (fraction, bucket.resetTime)
                }
            } else {
                modelQuotaMap[model] = (fraction, bucket.resetTime)
            }
        }

        let quotas = modelQuotaMap
            .sorted(by: { $0.key < $1.key })
            .map { model, payload in
                iOSGeminiModelQuota(
                    modelID: model,
                    percentLeft: max(0, min(100, payload.fraction * 100)),
                    resetTime: iOSISO8601.parse(payload.reset))
            }

        if quotas.isEmpty {
            throw iOSGeminiUsageError.parseFailed("No model quotas")
        }

        return iOSGeminiUsageSnapshot(modelQuotas: quotas, planName: nil, updatedAt: now)
    }
}

public enum iOSGeminiUsageMapper {
    public static func makeSnapshot(from usage: iOSGeminiUsageSnapshot, generatedAt: Date = Date()) -> iOSWidgetSnapshot {
        let lower = usage.modelQuotas.map { ($0.modelID.lowercased(), $0) }
        let pro = lower.filter { $0.0.contains("pro") }.map(\.1).min(by: { $0.percentLeft < $1.percentLeft })
        let flash = lower.filter { $0.0.contains("flash") }.map(\.1).min(by: { $0.percentLeft < $1.percentLeft })
        let fallback = usage.modelQuotas.min(by: { $0.percentLeft < $1.percentLeft })
        let primaryQuota = pro ?? fallback

        let primary = primaryQuota.map {
            iOSWidgetSnapshot.RateWindow(
                usedPercent: 100 - $0.percentLeft,
                windowMinutes: 24 * 60,
                resetsAt: $0.resetTime,
                resetDescription: "Daily")
        }

        let secondary = flash.map {
            iOSWidgetSnapshot.RateWindow(
                usedPercent: 100 - $0.percentLeft,
                windowMinutes: 24 * 60,
                resetsAt: $0.resetTime,
                resetDescription: "Daily Flash")
        }

        let entry = iOSWidgetSnapshot.ProviderEntry(
            providerID: "gemini",
            updatedAt: generatedAt,
            primary: primary,
            secondary: secondary,
            tertiary: nil,
            planType: usage.planName,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])

        return iOSWidgetSnapshot(entries: [entry], enabledProviderIDs: ["gemini"], generatedAt: generatedAt)
    }
}

// MARK: - Vertex AI (project + access token)

public struct iOSVertexAIUsageSnapshot: Sendable {
    public let requestsUsedPercent: Double
    public let updatedAt: Date
}

public enum iOSVertexAIUsageError: LocalizedError, Sendable {
    case invalidCredentials
    case noProjectID
    case noData
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "Vertex AI access token is invalid or expired."
        case .noProjectID:
            "Vertex AI requires a project ID. Use `project_id||access_token`."
        case .noData:
            "No Vertex AI quota data found for this project."
        case let .networkError(message):
            "Vertex AI network error: \(message)"
        }
    }
}

private struct iOSVertexAIMonitoringResponse: Decodable {
    let timeSeries: [Series]?

    struct Series: Decodable {
        let metric: Metric
        let resource: Resource
        let points: [Point]

        struct Metric: Decodable {
            let labels: [String: String]?
        }

        struct Resource: Decodable {
            let labels: [String: String]?
        }

        struct Point: Decodable {
            let value: Value

            struct Value: Decodable {
                let doubleValue: Double?
                let int64Value: String?
            }
        }
    }
}

public enum iOSVertexAIUsageFetcher {
    private static let monitoringBase = "https://monitoring.googleapis.com/v3/projects"

    public static func fetchUsage(projectID: String, accessToken: String) async throws -> iOSVertexAIUsageSnapshot {
        let projectID = projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        let accessToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !projectID.isEmpty else { throw iOSVertexAIUsageError.noProjectID }
        guard !accessToken.isEmpty else { throw iOSVertexAIUsageError.invalidCredentials }

        let usageSeries = try await self.fetchSeries(
            projectID: projectID,
            accessToken: accessToken,
            filter: "metric.type=\"serviceruntime.googleapis.com/quota/allocation/usage\" AND resource.type=\"consumer_quota\" AND resource.label.service=\"aiplatform.googleapis.com\"")

        let limitSeries = try await self.fetchSeries(
            projectID: projectID,
            accessToken: accessToken,
            filter: "metric.type=\"serviceruntime.googleapis.com/quota/limit\" AND resource.type=\"consumer_quota\" AND resource.label.service=\"aiplatform.googleapis.com\"")

        let usage = self.aggregate(series: usageSeries)
        let limits = self.aggregate(series: limitSeries)
        guard !usage.isEmpty, !limits.isEmpty else {
            throw iOSVertexAIUsageError.noData
        }

        var maxPercent: Double?
        for (key, limit) in limits {
            guard limit > 0, let used = usage[key] else { continue }
            let percent = (used / limit) * 100.0
            maxPercent = max(maxPercent ?? percent, percent)
        }

        guard let requestsUsedPercent = maxPercent else {
            throw iOSVertexAIUsageError.noData
        }

        return iOSVertexAIUsageSnapshot(requestsUsedPercent: max(0, min(100, requestsUsedPercent)), updatedAt: Date())
    }

    private struct QuotaKey: Hashable {
        let quotaMetric: String
        let limitName: String
        let location: String
    }

    private static func fetchSeries(
        projectID: String,
        accessToken: String,
        filter: String) async throws -> [iOSVertexAIMonitoringResponse.Series]
    {
        let now = Date()
        let start = now.addingTimeInterval(-(24 * 60 * 60))
        let formatter = ISO8601DateFormatter()

        guard var components = URLComponents(string: "\(self.monitoringBase)/\(projectID)/timeSeries") else {
            throw iOSVertexAIUsageError.networkError("Invalid Monitoring URL")
        }

        components.queryItems = [
            URLQueryItem(name: "filter", value: filter),
            URLQueryItem(name: "interval.startTime", value: formatter.string(from: start)),
            URLQueryItem(name: "interval.endTime", value: formatter.string(from: now)),
            URLQueryItem(name: "aggregation.alignmentPeriod", value: "3600s"),
            URLQueryItem(name: "aggregation.perSeriesAligner", value: "ALIGN_MAX"),
            URLQueryItem(name: "view", value: "FULL"),
        ]

        guard let url = components.url else {
            throw iOSVertexAIUsageError.networkError("Invalid Monitoring URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw iOSVertexAIUsageError.networkError("Invalid response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw iOSVertexAIUsageError.invalidCredentials
        }
        guard http.statusCode == 200 else {
            throw iOSVertexAIUsageError.networkError("HTTP \(http.statusCode)")
        }

        let decoded = try JSONDecoder().decode(iOSVertexAIMonitoringResponse.self, from: data)
        return decoded.timeSeries ?? []
    }

    private static func aggregate(series: [iOSVertexAIMonitoringResponse.Series]) -> [QuotaKey: Double] {
        var buckets: [QuotaKey: Double] = [:]

        for entry in series {
            let metricLabels = entry.metric.labels ?? [:]
            let resourceLabels = entry.resource.labels ?? [:]
            guard let quotaMetric = metricLabels["quota_metric"] ?? resourceLabels["quota_id"],
                  !quotaMetric.isEmpty
            else {
                continue
            }
            let key = QuotaKey(
                quotaMetric: quotaMetric,
                limitName: metricLabels["limit_name"] ?? "",
                location: resourceLabels["location"] ?? "global")

            let maxPoint = entry.points.compactMap { point -> Double? in
                if let double = point.value.doubleValue {
                    return double
                }
                if let int64 = point.value.int64Value {
                    return Double(int64)
                }
                return nil
            }.max()

            if let maxPoint {
                buckets[key] = max(buckets[key] ?? 0, maxPoint)
            }
        }

        return buckets
    }
}

public enum iOSVertexAIUsageMapper {
    public static func makeSnapshot(from usage: iOSVertexAIUsageSnapshot, generatedAt: Date = Date()) -> iOSWidgetSnapshot {
        let entry = iOSWidgetSnapshot.ProviderEntry(
            providerID: "vertexai",
            updatedAt: generatedAt,
            primary: .init(
                usedPercent: usage.requestsUsedPercent,
                windowMinutes: 24 * 60,
                resetsAt: nil,
                resetDescription: "Daily quota"),
            secondary: nil,
            tertiary: nil,
            planType: "Vertex AI",
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])

        return iOSWidgetSnapshot(entries: [entry], enabledProviderIDs: ["vertexai"], generatedAt: generatedAt)
    }
}

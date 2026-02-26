import AppIntents
import CodexBariOSShared
import SwiftUI
import UIKit
import WidgetKit

enum ProviderChoice: String, AppEnum {
    case all
    case codex
    case claude
    case gemini
    case antigravity
    case cursor
    case factory
    case copilot
    case minimax
    case vertexai
    case kiro
    case augment
    case jetbrains
    case kimi
    case kimik2
    case amp
    case synthetic
    case opencode
    case zai

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Provider")

    static let caseDisplayRepresentations: [ProviderChoice: DisplayRepresentation] = [
        .all: .init(title: "All Providers"),
        .codex: .init(title: "Codex"),
        .claude: .init(title: "Claude"),
        .gemini: .init(title: "Gemini"),
        .antigravity: .init(title: "Antigravity"),
        .cursor: .init(title: "Cursor"),
        .factory: .init(title: "Droid"),
        .copilot: .init(title: "Copilot"),
        .minimax: .init(title: "MiniMax"),
        .vertexai: .init(title: "Vertex AI"),
        .kiro: .init(title: "Kiro"),
        .augment: .init(title: "Augment"),
        .jetbrains: .init(title: "JetBrains"),
        .kimi: .init(title: "Kimi"),
        .kimik2: .init(title: "Kimi K2"),
        .amp: .init(title: "Amp"),
        .synthetic: .init(title: "Synthetic"),
        .opencode: .init(title: "OpenCode"),
        .zai: .init(title: "z.ai"),
    ]
}

struct ProviderSelectionIntent: AppIntent, WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Provider View"
    static let description = IntentDescription("Choose one provider, or show multiple providers in one widget.")

    @Parameter(title: "Provider")
    var provider: ProviderChoice

    init() {
        self.provider = .all
    }
}

struct CodexBariOSWidgetEntry: TimelineEntry {
    let date: Date
    let providerID: String
    let snapshot: iOSWidgetSnapshot
}

struct CodexBariOSWidgetTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> CodexBariOSWidgetEntry {
        CodexBariOSWidgetEntry(
            date: Date(),
            providerID: ProviderChoice.all.rawValue,
            snapshot: iOSWidgetPreviewData.snapshot())
    }

    func snapshot(for configuration: ProviderSelectionIntent, in _: Context) async -> CodexBariOSWidgetEntry {
        let snapshot = iOSWidgetSnapshotStore.load() ?? Self.emptySnapshot()
        return CodexBariOSWidgetEntry(
            date: Date(),
            providerID: self.providerID(for: configuration, snapshot: snapshot),
            snapshot: snapshot)
    }

    func timeline(
        for configuration: ProviderSelectionIntent,
        in _: Context) async -> Timeline<CodexBariOSWidgetEntry>
    {
        let snapshot = iOSWidgetSnapshotStore.load() ?? Self.emptySnapshot()
        let entry = CodexBariOSWidgetEntry(
            date: Date(),
            providerID: self.providerID(for: configuration, snapshot: snapshot),
            snapshot: snapshot)
        let refreshDate = Date().addingTimeInterval(30 * 60)
        return Timeline(entries: [entry], policy: .after(refreshDate))
    }

    private static func emptySnapshot() -> iOSWidgetSnapshot {
        iOSWidgetSnapshot(entries: [], enabledProviderIDs: [], generatedAt: Date())
    }

    private func providerID(
        for configuration: ProviderSelectionIntent,
        snapshot: iOSWidgetSnapshot) -> String
    {
        if configuration.provider == .all {
            return ProviderChoice.all.rawValue
        }
        return snapshot.selectedProviderID(preferred: configuration.provider.rawValue) ?? "codex"
    }
}

struct CodexBariOSUsageWidget: Widget {
    private let kind = "CodexBariOSUsageWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: self.kind,
            intent: ProviderSelectionIntent.self,
            provider: CodexBariOSWidgetTimelineProvider())
        { entry in
            CodexBariOSUsageWidgetView(entry: entry)
        }
        .configurationDisplayName("CodexBar Usage")
        .description("Session and weekly usage for your selected provider.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

private struct CodexBariOSUsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: CodexBariOSWidgetEntry

    private var summary: iOSWidgetSnapshot.ProviderSummary? {
        self.entry.snapshot.providerSummaries.first { $0.providerID == self.entry.providerID }
    }

    private var isAllProvidersMode: Bool {
        self.entry.providerID == ProviderChoice.all.rawValue
    }

    private var multiProviderSummaries: [iOSWidgetSnapshot.ProviderSummary] {
        let summaries = self.entry.snapshot.providerSummaries
            .filter { summary in
                summary.sessionRemainingPercent != nil
                    || summary.weeklyRemainingPercent != nil
                    || summary.todayCostUSD != nil
                    || summary.creditsRemaining != nil
            }
            .sorted { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }

        if summaries.isEmpty {
            return self.entry.snapshot.providerSummaries
                .sorted { lhs, rhs in lhs.updatedAt > rhs.updatedAt }
        }
        return summaries
    }

    private var palette: WidgetPalette {
        WidgetPalette(providerID: self.entry.providerID, colorScheme: self.colorScheme)
    }

    private var cornerRadius: CGFloat {
        self.family == .systemSmall ? 22 : 26
    }

    var body: some View {
        ZStack {
            self.palette.surfaceBackground(cornerRadius: self.cornerRadius)
            if self.isAllProvidersMode {
                self.multiProviderContent(palette: self.palette)
            } else if let summary {
                self.content(summary: summary, palette: self.palette)
            } else {
                self.emptyState(palette: self.palette)
            }
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
    }

    @ViewBuilder
    private func content(summary: iOSWidgetSnapshot.ProviderSummary, palette: WidgetPalette) -> some View {
        switch self.family {
        case .systemSmall:
            VStack(alignment: .leading, spacing: 6) {
                self.header(summary: summary, palette: palette)
                UsageBarRow(
                    title: "Session",
                    percentLeft: summary.sessionRemainingPercent,
                    tint: palette.primaryTint,
                    trackTint: palette.trackTint,
                    labelColor: palette.primaryText,
                    valueColor: palette.secondaryText)
                UsageBarRow(
                    title: "Weekly",
                    percentLeft: summary.weeklyRemainingPercent,
                    tint: palette.secondaryTint,
                    trackTint: palette.trackTint,
                    labelColor: palette.primaryText,
                    valueColor: palette.secondaryText)
                if let credits = summary.creditsRemaining {
                    ValueLine(
                        title: "Credits",
                        value: Self.decimal(credits),
                        labelColor: palette.secondaryText,
                        valueColor: palette.primaryText)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        default:
            VStack(alignment: .leading, spacing: 6) {
                self.header(summary: summary, palette: palette)
                UsageBarRow(
                    title: "Session",
                    percentLeft: summary.sessionRemainingPercent,
                    tint: palette.primaryTint,
                    trackTint: palette.trackTint,
                    labelColor: palette.primaryText,
                    valueColor: palette.secondaryText)
                UsageBarRow(
                    title: "Weekly",
                    percentLeft: summary.weeklyRemainingPercent,
                    tint: palette.secondaryTint,
                    trackTint: palette.trackTint,
                    labelColor: palette.primaryText,
                    valueColor: palette.secondaryText)
                ValueLine(
                    title: "Today",
                    value: summary.todayCostUSD.map(Self.usd) ?? "—",
                    labelColor: palette.secondaryText,
                    valueColor: palette.primaryText)
                ValueLine(
                    title: "30d",
                    value: summary.last30DaysCostUSD.map(Self.usd) ?? "—",
                    labelColor: palette.secondaryText,
                    valueColor: palette.primaryText)
                if let credits = summary.creditsRemaining {
                    ValueLine(
                        title: "Credits",
                        value: Self.decimal(credits),
                        labelColor: palette.secondaryText,
                        valueColor: palette.primaryText)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
    }

    private func header(summary: iOSWidgetSnapshot.ProviderSummary, palette: WidgetPalette) -> some View {
        HStack {
            HStack(spacing: 6) {
                WidgetProviderGlyph(
                    providerID: summary.providerID,
                    size: 10,
                    tint: palette.primaryTint,
                    backgroundTint: palette.iconBadgeTint)
                Text(summary.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(palette.primaryText)
            }
            Spacer()
            Text(Self.relative(summary.updatedAt))
                .font(.caption2)
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
        }
    }

    private func emptyState(palette: WidgetPalette) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Open CodexBar")
                .font(.body.weight(.semibold))
                .foregroundStyle(palette.primaryText)
            Text("Refresh a connected provider in the app, or import a widget snapshot.")
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
        }
        .padding(12)
    }

    @ViewBuilder
    private func multiProviderContent(palette: WidgetPalette) -> some View {
        let maxRows = self.family == .systemSmall ? 2 : 3
        let rows = Array(self.multiProviderSummaries.prefix(maxRows))

        VStack(alignment: .leading, spacing: self.family == .systemSmall ? 6 : 8) {
            HStack {
                Text("Providers")
                    .font(self.family == .systemSmall ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                Spacer()
                Text("\(self.multiProviderSummaries.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.secondaryText)
            }

            if rows.isEmpty {
                Text("No usage data yet")
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
            } else {
                ForEach(rows, id: \.providerID) { provider in
                    self.multiProviderRow(summary: provider, palette: palette)
                }
            }
        }
        .padding(.horizontal, self.family == .systemSmall ? 10 : 12)
        .padding(.vertical, self.family == .systemSmall ? 10 : 12)
    }

    private func multiProviderRow(
        summary: iOSWidgetSnapshot.ProviderSummary,
        palette: WidgetPalette) -> some View
    {
        let primaryPercent = summary.sessionRemainingPercent ?? summary.weeklyRemainingPercent
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                WidgetProviderGlyph(
                    providerID: summary.providerID,
                    size: 9,
                    tint: palette.primaryTint,
                    backgroundTint: palette.iconBadgeTint)
                Text(summary.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(palette.primaryText)
                Spacer()
                Text(primaryPercent.map { String(format: "%.0f%%", $0) } ?? "—")
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
            }
            GeometryReader { proxy in
                let ratio = max(0, min(100, primaryPercent ?? 0)) / 100
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.trackTint)
                    Capsule().fill(palette.primaryTint).frame(width: proxy.size.width * ratio)
                }
            }
            .frame(height: 4)
        }
    }

    private static func relative(_ value: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: value, relativeTo: Date())
    }

    private static func usd(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    private static func decimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}

private struct UsageBarRow: View {
    let title: String
    let percentLeft: Double?
    let tint: Color
    let trackTint: Color
    let labelColor: Color
    let valueColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(self.title)
                    .font(.caption2)
                    .foregroundStyle(self.labelColor)
                Spacer()
                Text(self.percentLeft.map { String(format: "%.0f%%", $0) } ?? "—")
                    .font(.caption2)
                    .foregroundStyle(self.valueColor)
            }
            GeometryReader { proxy in
                let ratio = max(0, min(100, self.percentLeft ?? 0)) / 100
                ZStack(alignment: .leading) {
                    Capsule().fill(self.trackTint)
                    Capsule().fill(self.tint).frame(width: proxy.size.width * ratio)
                }
            }
            .frame(height: 5)
        }
    }
}

private struct WidgetProviderGlyph: View {
    let providerID: String
    let size: CGFloat
    let tint: Color
    let backgroundTint: Color

    var body: some View {
        self.iconImage
            .resizable()
            .scaledToFit()
            .frame(width: self.size, height: self.size)
            .foregroundStyle(self.tint)
            .frame(width: self.size + 6, height: self.size + 6)
            .background(Circle().fill(self.backgroundTint))
    }

    private var iconImage: Image {
        if let brandedIcon = Self.brandedTemplateIcon(for: self.providerID) {
            return Image(uiImage: brandedIcon)
        }
        return Image(systemName: iOSProviderCatalog.iconSymbolName(for: self.providerID))
    }

    private static func brandedTemplateIcon(for providerID: String) -> UIImage? {
        guard let iconName = iOSProviderCatalog.brandIconResourceName(for: providerID),
              let image = UIImage(named: iconName)
        else {
            return nil
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
}

private struct ValueLine: View {
    let title: String
    let value: String
    let labelColor: Color
    let valueColor: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(self.title)
                .font(.caption2)
                .foregroundStyle(self.labelColor)
                .lineLimit(1)
            Text(self.value)
                .font(.caption2)
                .foregroundStyle(self.valueColor)
                .lineLimit(1)
        }
    }
}

private struct WidgetPalette {
    let providerID: String
    let colorScheme: ColorScheme

    var primaryTint: Color {
        let base = Self.accent(for: self.providerID, colorScheme: self.colorScheme)
        return self.colorScheme == .dark ? base.opacity(0.92) : base.opacity(0.86)
    }

    var secondaryTint: Color {
        self.primaryTint.opacity(self.colorScheme == .dark ? 0.66 : 0.6)
    }

    var primaryText: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.94) : Color.black.opacity(0.8)
    }

    var secondaryText: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.5)
    }

    var trackTint: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.24) : Color.black.opacity(0.16)
    }

    var iconBadgeTint: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.52)
    }

    func surfaceBackground(cornerRadius: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(self.chromaWash)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(self.specularHighlight)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(self.edgeVignette)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(self.glassStroke, lineWidth: 0.8)
        }
        .shadow(
            color: self.colorScheme == .dark ? Color.black.opacity(0.24) : Color.black.opacity(0.08),
            radius: 16,
            x: 0,
            y: 6)
    }

    private var chromaWash: LinearGradient {
        let accent = Self.accent(for: self.providerID, colorScheme: self.colorScheme)
        return LinearGradient(
            colors: self.colorScheme == .dark
                ? [accent.opacity(0.22), Color.white.opacity(0.06), Color.black.opacity(0.12)]
                : [accent.opacity(0.12), Color.white.opacity(0.1), Color.clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing)
    }

    private var specularHighlight: RadialGradient {
        RadialGradient(
            colors: self.colorScheme == .dark
                ? [Color.white.opacity(0.08), Color.clear]
                : [Color.white.opacity(0.18), Color.clear],
            center: .topLeading,
            startRadius: 0,
            endRadius: 240)
    }

    private var edgeVignette: LinearGradient {
        LinearGradient(
            colors: self.colorScheme == .dark
                ? [Color.clear, Color.black.opacity(0.18)]
                : [Color.clear, Color.black.opacity(0.06)],
            startPoint: .top,
            endPoint: .bottom)
    }

    private var glassStroke: LinearGradient {
        LinearGradient(
            colors: self.colorScheme == .dark
                ? [Color.white.opacity(0.24), Color.white.opacity(0.08)]
                : [Color.white.opacity(0.54), Color.white.opacity(0.16)],
            startPoint: .top,
            endPoint: .bottom)
    }

    private static func accent(for providerID: String, colorScheme: ColorScheme) -> Color {
        let light: Color
        let dark: Color
        switch iOSProviderCatalog.accentToken(for: providerID) {
        case .ocean:
            light = Color(red: 0.14, green: 0.48, blue: 0.95)
            dark = Color(red: 0.4, green: 0.67, blue: 1.0)
        case .violet:
            light = Color(red: 0.52, green: 0.37, blue: 0.94)
            dark = Color(red: 0.69, green: 0.57, blue: 1.0)
        case .amber:
            light = Color(red: 0.88, green: 0.56, blue: 0.2)
            dark = Color(red: 0.95, green: 0.72, blue: 0.42)
        case .indigo:
            light = Color(red: 0.34, green: 0.43, blue: 0.91)
            dark = Color(red: 0.56, green: 0.67, blue: 1.0)
        case .mint:
            light = Color(red: 0.15, green: 0.68, blue: 0.6)
            dark = Color(red: 0.38, green: 0.83, blue: 0.75)
        case .rose:
            light = Color(red: 0.84, green: 0.37, blue: 0.54)
            dark = Color(red: 0.93, green: 0.58, blue: 0.73)
        case .cyan:
            light = Color(red: 0.11, green: 0.59, blue: 0.8)
            dark = Color(red: 0.35, green: 0.79, blue: 0.93)
        case .neutral:
            light = Color(red: 0.36, green: 0.48, blue: 0.67)
            dark = Color(red: 0.62, green: 0.71, blue: 0.85)
        }
        return colorScheme == .dark ? dark : light
    }
}

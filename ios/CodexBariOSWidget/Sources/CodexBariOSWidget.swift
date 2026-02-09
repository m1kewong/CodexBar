import AppIntents
import CodexBariOSShared
import SwiftUI
import UIKit
import WidgetKit

enum ProviderChoice: String, AppEnum {
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
    static let title: LocalizedStringResource = "Provider"
    static let description = IntentDescription("Select which provider appears in the widget.")

    @Parameter(title: "Provider")
    var provider: ProviderChoice

    init() {
        self.provider = .codex
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
            providerID: "codex",
            snapshot: iOSWidgetPreviewData.snapshot())
    }

    func snapshot(for configuration: ProviderSelectionIntent, in _: Context) async -> CodexBariOSWidgetEntry {
        let snapshot = iOSWidgetSnapshotStore.load() ?? iOSWidgetPreviewData.snapshot()
        return CodexBariOSWidgetEntry(
            date: Date(),
            providerID: snapshot.selectedProviderID(preferred: configuration.provider.rawValue) ?? "codex",
            snapshot: snapshot)
    }

    func timeline(
        for configuration: ProviderSelectionIntent,
        in _: Context) async -> Timeline<CodexBariOSWidgetEntry>
    {
        let snapshot = iOSWidgetSnapshotStore.load() ?? iOSWidgetPreviewData.snapshot()
        let entry = CodexBariOSWidgetEntry(
            date: Date(),
            providerID: snapshot.selectedProviderID(preferred: configuration.provider.rawValue) ?? "codex",
            snapshot: snapshot)
        let refreshDate = Date().addingTimeInterval(30 * 60)
        return Timeline(entries: [entry], policy: .after(refreshDate))
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
    }
}

private struct CodexBariOSUsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: CodexBariOSWidgetEntry

    private var summary: iOSWidgetSnapshot.ProviderSummary? {
        self.entry.snapshot.providerSummaries.first { $0.providerID == self.entry.providerID }
    }

    private var palette: WidgetPalette {
        WidgetPalette(providerID: self.entry.providerID, colorScheme: self.colorScheme)
    }

    var body: some View {
        ZStack {
            self.palette.background
            if let summary {
                self.content(summary: summary, palette: self.palette)
            } else {
                self.emptyState(palette: self.palette)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(self.palette.border, lineWidth: 1)
        }
        .containerBackground(.clear, for: .widget)
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
                WidgetProviderGlyph(providerID: summary.providerID, size: 10, tint: palette.primaryTint)
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
            Text("Import a widget snapshot in the app first.")
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
        }
        .padding(12)
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

    var body: some View {
        self.iconImage
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: self.size, height: self.size)
            .foregroundStyle(self.tint)
            .frame(width: self.size + 6, height: self.size + 6)
            .background(Circle().fill(self.tint.opacity(0.2)))
    }

    private var iconImage: Image {
        if let iconName = iOSProviderCatalog.brandIconResourceName(for: self.providerID),
           UIImage(named: iconName) != nil
        {
            return Image(iconName)
        }
        return Image(systemName: iOSProviderCatalog.iconSymbolName(for: self.providerID))
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
        Self.accent(for: self.providerID, colorScheme: self.colorScheme)
    }

    var secondaryTint: Color {
        self.primaryTint.opacity(self.colorScheme == .dark ? 0.72 : 0.78)
    }

    var primaryText: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.88)
    }

    var secondaryText: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.54)
    }

    var trackTint: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1)
    }

    var border: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
    }

    var background: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(self.surfaceGradient)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(self.primaryTint.opacity(self.colorScheme == .dark ? 0.17 : 0.12))
        }
    }

    private var surfaceGradient: LinearGradient {
        LinearGradient(
            colors: self.colorScheme == .dark
                ? [Color(red: 0.1, green: 0.12, blue: 0.17), Color(red: 0.07, green: 0.09, blue: 0.13)]
                : [Color.white.opacity(0.94), Color.white.opacity(0.82)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing)
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

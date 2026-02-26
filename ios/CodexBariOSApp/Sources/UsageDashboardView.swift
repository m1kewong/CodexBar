import CodexBariOSShared
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct UsageDashboardView: View {
    @Bindable var viewModel: UsageDashboardViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPinnedSectionExpanded = true
    @State private var isMoreSectionExpanded = false
    @State private var isDesktopSectionExpanded = false
    @State private var expandedPinnedProviderID: String?
    @State private var expandedMoreProviderID: String?
    @State private var expandedDesktopProviderID: String?

    var body: some View {
        ZStack {
            DashboardBackground(colorScheme: self.colorScheme)
                .ignoresSafeArea()

            NavigationStack {
                Group {
                    if let snapshot = self.viewModel.snapshot,
                       let summary = self.viewModel.selectedSummary
                    {
                        self.snapshotContent(snapshot: snapshot, summary: summary)
                    } else {
                        self.emptyState
                    }
                }
                .navigationTitle("CodexBar")
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            self.viewModel.showingImportSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .accessibilityLabel("Import JSON")

                        Button {
                            self.viewModel.loadSnapshot()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Refresh")
                    }
                }
            }
        }
        .sheet(isPresented: self.$viewModel.showingImportSheet) {
            SnapshotImportSheet(viewModel: self.viewModel)
        }
        .task {
            self.viewModel.loadSnapshot()
        }
    }

    private func snapshotContent(
        snapshot: iOSWidgetSnapshot,
        summary: iOSWidgetSnapshot.ProviderSummary) -> some View
    {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if snapshot.availableProviderIDs.count > 1 {
                    self.providerSwitcherCard(snapshot: snapshot, selectedProviderID: summary.providerID)
                }

                self.providerOverviewCard(summary: summary)
                self.usageDetailsCard(summary: summary)
                self.homeConnectionsCard
                self.quickActionsCard(selectedProviderID: summary.providerID)
            }
            .padding(16)
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DashboardCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("No usage snapshot yet", systemImage: "chart.bar.doc.horizontal")
                            .font(.headline)
                        Text("Connect providers or import `widget-snapshot.json` from desktop CodexBar.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            Button("Load Sample Data") {
                                self.viewModel.loadSampleData()
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Import JSON") {
                                self.viewModel.showingImportSheet = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                self.homeConnectionsCard
            }
            .padding(16)
        }
    }

    private func providerSwitcherCard(
        snapshot: iOSWidgetSnapshot,
        selectedProviderID: String) -> some View
    {
        DashboardCard(accent: self.providerAccentColor(for: selectedProviderID)) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Provider")
                    .font(.headline)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(snapshot.availableProviderIDs, id: \.self) { providerID in
                            let selected = providerID == selectedProviderID
                            let accent = self.providerAccentColor(for: providerID)
                            Button {
                                self.viewModel.selectProvider(providerID)
                            } label: {
                                HStack(spacing: 6) {
                                    ProviderGlyph(
                                        providerID: providerID,
                                        size: 14,
                                        containerOpacity: selected ? 0.28 : 0.18,
                                        foreground: selected ? .white : accent)
                                    Text(iOSProviderCatalog.displayName(for: providerID))
                                        .font(.footnote.weight(.semibold))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .foregroundStyle(selected ? Color.white : Color.primary)
                                .background {
                                    Capsule(style: .continuous)
                                        .fill(selected ? accent : self.chipBackgroundColor)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func providerOverviewCard(summary: iOSWidgetSnapshot.ProviderSummary) -> some View {
        let accent = self.providerAccentColor(for: summary.providerID)
        return DashboardCard(accent: accent) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            ProviderGlyph(providerID: summary.providerID, size: 16, foreground: accent)
                            Text(summary.displayName)
                                .font(.title3.weight(.semibold))
                        }
                        Text("Updated \(Self.relativeDate(summary.updatedAt))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Self.planLabel(summary.planType))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(self.chipBackgroundColor, in: Capsule(style: .continuous))
                }

                UsageBarRow(
                    title: "Session",
                    percentLeft: summary.sessionRemainingPercent,
                    tint: accent,
                    trackTint: self.usageTrackColor)
                UsageBarRow(
                    title: "Weekly",
                    percentLeft: summary.weeklyRemainingPercent,
                    tint: accent.opacity(0.72),
                    trackTint: self.usageTrackColor)

                if let codeReview = summary.codeReviewRemainingPercent {
                    UsageBarRow(
                        title: "Code review",
                        percentLeft: codeReview,
                        tint: self.secondaryUsageTint,
                        trackTint: self.usageTrackColor)
                }
            }
        }
    }

    private func usageDetailsCard(summary: iOSWidgetSnapshot.ProviderSummary) -> some View {
        DashboardCard(accent: self.providerAccentColor(for: summary.providerID)) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Details")
                    .font(.headline)

                ValueRow(title: "Credits", value: summary.creditsRemaining.map(Self.decimal) ?? "—")
                ValueRow(title: "Today cost", value: summary.todayCostUSD.map(Self.usd) ?? "—")
                ValueRow(title: "30d cost", value: summary.last30DaysCostUSD.map(Self.usd) ?? "—")
                ValueRow(title: "Today tokens", value: summary.todayTokens.map(Self.integer) ?? "—")
                ValueRow(title: "30d tokens", value: summary.last30DaysTokens.map(Self.integer) ?? "—")
            }
        }
    }

    private var homeConnectionsCard: some View {
        NavigationLink {
            self.providerManagementScreen
        } label: {
            DashboardCard(accent: self.secondaryUsageTint) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Providers")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }

                    Text("\(self.connectedProviderCount) of \(self.connectableProviderCount) providers connected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("Manage sign-in and API credentials in one place.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func quickActionsCard(selectedProviderID: String) -> some View {
        let accent = self.providerAccentColor(for: selectedProviderID)
        return DashboardCard(accent: accent) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Quick actions")
                    .font(.headline)

                HStack(spacing: 10) {
                    ProviderActionButton(
                        title: "Refresh",
                        systemImage: "arrow.clockwise",
                        accent: accent,
                        kind: .primary,
                        expands: true,
                        disabled: self.viewModel.isRefreshing(providerID: selectedProviderID))
                    {
                        Task { await self.viewModel.refreshProvider(providerID: selectedProviderID) }
                    }
                    .accessibilityLabel("Refresh selected")

                    ProviderActionButton(
                        title: "Import",
                        systemImage: "square.and.arrow.down",
                        accent: accent,
                        kind: .secondary)
                    {
                        self.viewModel.showingImportSheet = true
                    }
                    .accessibilityLabel("Import JSON")
                }
            }
        }
    }

    private var connectableProviderCount: Int {
        self.connectableProviderIDs.count
    }

    private var connectedProviderCount: Int {
        self.connectableProviderIDs.count(where: { self.viewModel.hasCredentials(for: $0) })
    }

    private var connectableProviderIDs: [String] {
        ["codex", "copilot"] + Self.tokenProviderConfigs.map(\.id)
    }

    private var configuredProviderIDs: Set<String> {
        Set(self.connectableProviderIDs.filter { self.viewModel.hasCredentials(for: $0) })
    }

    private var pinnedProviderIDs: [String] {
        iOSProviderCatalog.pinnedProviderIDs(
            connectableProviderIDs: self.connectableProviderIDs,
            configuredProviderIDs: self.configuredProviderIDs,
            cap: Self.pinnedProviderCap)
    }

    private var pinnedProviderItems: [ProviderManagementItem] {
        self.pinnedProviderIDs.compactMap(self.providerItem(for:))
    }

    private var moreProviderItems: [ProviderManagementItem] {
        self.connectableProviderIDs
            .filter { !self.pinnedProviderIDs.contains($0) }
            .compactMap(self.providerItem(for:))
    }

    private var desktopOnlyItems: [ProviderManagementItem] {
        Self.unsupportedProviderConfigs.map { .unsupported($0) }
    }

    private func providerItem(for providerID: String) -> ProviderManagementItem? {
        switch providerID {
        case "codex":
            return ProviderManagementItem.codex
        case "copilot":
            return ProviderManagementItem.copilot
        default:
            guard let config = Self.tokenProviderConfigs.first(where: { $0.id == providerID }) else {
                return nil
            }
            return .token(config)
        }
    }

    private var providerManagementScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                self.providerSection(
                    title: "Pinned Providers",
                    subtitle: "\(self.pinnedProviderItems.count) shown",
                    isExpanded: self.$isPinnedSectionExpanded,
                    expandedProviderID: self.$expandedPinnedProviderID,
                    items: self.pinnedProviderItems)

                self.providerSection(
                    title: "More Providers",
                    subtitle: "\(self.moreProviderItems.count) available",
                    isExpanded: self.$isMoreSectionExpanded,
                    expandedProviderID: self.$expandedMoreProviderID,
                    items: self.moreProviderItems)

                self.providerSection(
                    title: "Desktop-only Providers",
                    subtitle: "Import from mac app",
                    isExpanded: self.$isDesktopSectionExpanded,
                    expandedProviderID: self.$expandedDesktopProviderID,
                    items: self.desktopOnlyItems)
            }
            .padding(16)
        }
        .navigationTitle("Providers")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func providerSection(
        title: String,
        subtitle: String,
        isExpanded: Binding<Bool>,
        expandedProviderID: Binding<String?>,
        items: [ProviderManagementItem]) -> some View
    {
        VStack(alignment: .leading, spacing: 8) {
            DashboardCard(accent: self.secondaryUsageTint) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isExpanded.wrappedValue.toggle()
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(subtitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }

            if isExpanded.wrappedValue {
                ForEach(items, id: \.id) { item in
                    self.providerAccordionItem(item, expandedProviderID: expandedProviderID)
                }
            }
        }
    }

    private func providerAccordionItem(_ item: ProviderManagementItem, expandedProviderID: Binding<String?>) -> some View {
        let isExpanded = expandedProviderID.wrappedValue == item.id
        let accent = self.providerAccentColor(for: item.id)
        return VStack(alignment: .leading, spacing: 8) {
            DashboardCard(accent: accent) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        expandedProviderID.wrappedValue = isExpanded ? nil : item.id
                    }
                } label: {
                    HStack(alignment: .center, spacing: 10) {
                        ProviderGlyph(providerID: item.id, size: 14, foreground: accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(self.providerRowStatus(item))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Text(self.providerConnectionStateText(item))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(self.chipBackgroundColor, in: Capsule(style: .continuous))
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                self.providerDetailCard(item)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private func providerDetailCard(_ item: ProviderManagementItem) -> some View {
        switch item {
        case .codex:
            self.codexAuthCard
        case .copilot:
            self.copilotAuthCard
        case let .token(config):
            self.tokenProviderCard(config)
        case let .unsupported(config):
            self.unsupportedProviderCard(config)
        }
    }

    private func providerRowStatus(_ item: ProviderManagementItem) -> String {
        switch item {
        case .codex:
            self.viewModel.hasCodexCredentials ? "Signed in with ChatGPT OAuth." : "Sign in to fetch live Codex usage."
        case .copilot:
            self.viewModel.hasCopilotToken ? "Signed in with GitHub device flow." : "Sign in to fetch live Copilot usage."
        case let .token(config):
            self.viewModel.hasProviderToken(config.id) ? "Credentials stored in Keychain." : config.subtitle
        case let .unsupported(config):
            config.subtitle
        }
    }

    private func providerConnectionStateText(_ item: ProviderManagementItem) -> String {
        switch item {
        case .unsupported:
            "Desktop"
        default:
            self.viewModel.hasCredentials(for: item.id) ? "Connected" : "Not connected"
        }
    }

    private var codexAuthCard: some View {
        DashboardCard(accent: self.providerAccentColor(for: "codex")) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ProviderGlyph(
                        providerID: "codex",
                        size: 15,
                        foreground: self.providerAccentColor(for: "codex"))
                    Text("Codex (ChatGPT OAuth)")
                        .font(.headline)
                }

                if self.viewModel.hasCodexCredentials {
                    Text("Signed in. Refresh to pull live Codex usage for your Plus/Pro account.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        ProviderManagementButton(
                            title: "Refresh",
                            systemImage: "arrow.clockwise",
                            kind: .primary,
                            expands: true,
                            disabled: self.viewModel.isRefreshingCodexUsage || self.viewModel.isAuthenticatingCodex)
                        {
                            Task { await self.viewModel.refreshCodexUsage() }
                        }
                        .accessibilityLabel("Refresh Codex Usage")

                        ProviderManagementButton(
                            title: "Sign Out",
                            systemImage: "rectangle.portrait.and.arrow.right",
                            kind: .destructive)
                        {
                            self.viewModel.clearCodexCredentials()
                        }
                    }
                } else {
                    Text("Sign in with ChatGPT Device Flow to fetch real Codex usage.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    ProviderManagementButton(
                        title: "Start Sign-In",
                        systemImage: "person.crop.circle.badge.checkmark",
                        kind: .primary,
                        disabled: self.viewModel.isAuthenticatingCodex)
                    {
                        Task { await self.viewModel.startCodexDeviceLogin() }
                    }
                }

                if let code = self.viewModel.codexDeviceCode {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Verification Code")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(code.userCode)
                            .font(.title3.weight(.bold))
                            .textSelection(.enabled)
                        Text(code.verificationURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        HStack(spacing: 10) {
                            ProviderManagementButton(
                                title: "Open ChatGPT",
                                systemImage: "safari",
                                kind: .secondary)
                            {
                                self.viewModel.openCodexVerificationURL()
                            }

                            ProviderManagementButton(
                                title: "Complete Sign-In",
                                systemImage: "checkmark.circle.fill",
                                kind: .primary,
                                disabled: self.viewModel.isAuthenticatingCodex)
                            {
                                Task { await self.viewModel.completeCodexDeviceLogin() }
                            }
                        }
                    }
                    .padding(10)
                    .background(self.chipBackgroundColor, in: RoundedRectangle(cornerRadius: 10))
                }

                if let status = self.viewModel.codexAuthStatusMessage {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let status = self.viewModel.codexRefreshStatusMessage {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let error = self.viewModel.codexAuthErrorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var copilotAuthCard: some View {
        DashboardCard(accent: self.providerAccentColor(for: "copilot")) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ProviderGlyph(
                        providerID: "copilot",
                        size: 15,
                        foreground: self.providerAccentColor(for: "copilot"))
                    Text("GitHub Copilot (Live)")
                        .font(.headline)
                }

                if self.viewModel.hasCopilotToken {
                    Text("Signed in. You can refresh live usage anytime.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        ProviderManagementButton(
                            title: "Refresh",
                            systemImage: "arrow.clockwise",
                            kind: .primary,
                            expands: true,
                            disabled: self.viewModel.isRefreshingCopilotUsage || self.viewModel.isAuthenticatingCopilot)
                        {
                            Task { await self.viewModel.refreshCopilotUsage() }
                        }
                        .accessibilityLabel("Refresh Live Usage")

                        ProviderManagementButton(
                            title: "Sign Out",
                            systemImage: "rectangle.portrait.and.arrow.right",
                            kind: .destructive)
                        {
                            self.viewModel.clearCopilotToken()
                        }
                    }
                } else {
                    Text("Sign in with GitHub Device Flow to fetch real Copilot usage.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    ProviderManagementButton(
                        title: "Start Sign-In",
                        systemImage: "person.crop.circle.badge.checkmark",
                        kind: .primary,
                        disabled: self.viewModel.isAuthenticatingCopilot)
                    {
                        Task { await self.viewModel.startCopilotDeviceLogin() }
                    }
                }

                if let code = self.viewModel.copilotDeviceCode {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Verification Code")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(code.userCode)
                            .font(.title3.weight(.bold))
                            .textSelection(.enabled)
                        Text(code.verificationURI)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        HStack(spacing: 10) {
                            ProviderManagementButton(
                                title: "Open URL",
                                systemImage: "safari",
                                kind: .secondary)
                            {
                                self.viewModel.openCopilotVerificationURL()
                            }

                            ProviderManagementButton(
                                title: "Complete Sign-In",
                                systemImage: "checkmark.circle.fill",
                                kind: .primary,
                                disabled: self.viewModel.isAuthenticatingCopilot)
                            {
                                Task { await self.viewModel.completeCopilotDeviceLogin() }
                            }
                        }
                    }
                    .padding(10)
                    .background(self.chipBackgroundColor, in: RoundedRectangle(cornerRadius: 10))
                }

                if let status = self.viewModel.authStatusMessage {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let status = self.viewModel.liveRefreshStatusMessage {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let error = self.viewModel.authErrorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func tokenProviderCard(_ config: TokenProviderCardConfig) -> some View {
        let accent = self.providerAccentColor(for: config.id)
        return DashboardCard(accent: accent) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ProviderGlyph(providerID: config.id, size: 15, foreground: accent)
                    Text(config.title)
                        .font(.headline)
                }

                Text(config.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                SecureField(config.placeholder, text: Binding(
                    get: { self.viewModel.tokenDraft(for: config.id) },
                    set: { self.viewModel.setTokenDraft($0, for: config.id) }))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
                    .padding(9)
                    .background(self.chipBackgroundColor, in: RoundedRectangle(cornerRadius: 10))

                if self.viewModel.hasProviderToken(config.id) {
                    Text("Credentials are stored in Keychain.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    ProviderManagementButton(
                        title: "Save",
                        systemImage: "checkmark.circle.fill",
                        kind: .primary)
                    {
                        self.viewModel.saveProviderToken(config.id)
                    }
                    .accessibilityLabel("Save Credentials")

                    ProviderManagementButton(
                        title: "Refresh",
                        systemImage: "arrow.clockwise",
                        kind: .secondary,
                        disabled: !self.viewModel.hasProviderToken(config.id) || self.viewModel
                            .isProviderRefreshing(config.id))
                    {
                        Task { await self.viewModel.refreshProviderUsage(config.id) }
                    }
                    .accessibilityLabel("Refresh Usage")

                    ProviderManagementButton(
                        title: "Clear",
                        systemImage: "trash",
                        kind: .destructive)
                    {
                        self.viewModel.clearProviderToken(config.id)
                    }
                }

                if let status = self.viewModel.providerStatus(for: config.id) {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let error = self.viewModel.providerError(for: config.id) {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func unsupportedProviderCard(_ config: UnsupportedProviderCardConfig) -> some View {
        DashboardCard(accent: self.providerAccentColor(for: config.id)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ProviderGlyph(
                        providerID: config.id,
                        size: 15,
                        foreground: self.providerAccentColor(for: config.id))
                    Text(config.title)
                        .font(.headline)
                }
                Text(config.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var chipBackgroundColor: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)
    }

    private var usageTrackColor: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.08)
    }

    private var secondaryUsageTint: Color {
        self.colorScheme == .dark ? Color(red: 0.53, green: 0.66, blue: 1.0) : Color(red: 0.23, green: 0.4, blue: 0.93)
    }

    private func providerAccentColor(for providerID: String) -> Color {
        DashboardPalette.accent(for: providerID, colorScheme: self.colorScheme)
    }

    private static func relativeDate(_ value: Date) -> String {
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

    private static func integer(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func planLabel(_ value: String?) -> String {
        guard let value else { return "—" }
        return value
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map(\.capitalized)
            .joined(separator: " ")
    }

    private static let pinnedProviderCap = 4

    private static let tokenProviderConfigs: [TokenProviderCardConfig] = [
        .init(
            id: "claude",
            title: "Claude (session key)",
            subtitle: "Paste `sessionKey=...` cookie header or raw `sk-ant-...` session key.",
            placeholder: "Claude sessionKey cookie"),
        .init(
            id: "cursor",
            title: "Cursor (cookie header)",
            subtitle: "Paste Cursor browser cookie header (`WorkosCursorSessionToken`/`next-auth`).",
            placeholder: "Cursor Cookie header"),
        .init(
            id: "opencode",
            title: "OpenCode (cookie header)",
            subtitle: "Paste cookie header. Optional workspace override: `cookie||wrk_...`.",
            placeholder: "OpenCode Cookie header"),
        .init(
            id: "augment",
            title: "Augment (cookie header)",
            subtitle: "Paste app.augmentcode.com cookie header to fetch credits/subscription.",
            placeholder: "Augment Cookie header"),
        .init(
            id: "factory",
            title: "Factory (cookie header)",
            subtitle: "Paste app.factory.ai cookie header (supports `access-token` cookie if present).",
            placeholder: "Factory Cookie header"),
        .init(
            id: "amp",
            title: "Amp (cookie header)",
            subtitle: "Paste ampcode.com cookie header to fetch free tier usage from settings page.",
            placeholder: "Amp Cookie header"),
        .init(
            id: "gemini",
            title: "Gemini (access token)",
            subtitle: "Paste Google OAuth access token used by Gemini CLI.",
            placeholder: "Gemini OAuth access token"),
        .init(
            id: "vertexai",
            title: "Vertex AI (project + token)",
            subtitle: "Format: `project_id||access_token`.",
            placeholder: "my-project||ya29...."),
        .init(
            id: "zai",
            title: "z.ai (API key)",
            subtitle: "Paste your z.ai API token to fetch quota usage directly.",
            placeholder: "z.ai API token"),
        .init(
            id: "minimax",
            title: "MiniMax (API key)",
            subtitle: "Use your MiniMax Open Platform API token for coding plan remains.",
            placeholder: "MiniMax API token"),
        .init(
            id: "synthetic",
            title: "Synthetic (API key)",
            subtitle: "Use your Synthetic API key to fetch quotas from api.synthetic.new.",
            placeholder: "Synthetic API key"),
        .init(
            id: "kimik2",
            title: "Kimi K2 (API key)",
            subtitle: "Use your Kimi K2 API key to fetch credit usage.",
            placeholder: "Kimi K2 API key"),
        .init(
            id: "kimi",
            title: "Kimi (auth token)",
            subtitle: "Paste your Kimi auth token (JWT) to fetch coding quota usage.",
            placeholder: "Kimi auth token"),
    ]

    private static let unsupportedProviderConfigs: [UnsupportedProviderCardConfig] = [
        .init(
            id: "antigravity",
            title: "Antigravity",
            subtitle: "Depends on local desktop language-server process; use JSON import from desktop CodexBar."),
        .init(
            id: "jetbrains",
            title: "JetBrains",
            subtitle: "Depends on local IDE XML quota files; use JSON import from desktop CodexBar."),
        .init(
            id: "kiro",
            title: "Kiro",
            subtitle: "Depends on local `kiro-cli` session; use JSON import from desktop CodexBar."),
    ]
}

private struct TokenProviderCardConfig: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let placeholder: String
}

private struct UnsupportedProviderCardConfig: Identifiable {
    let id: String
    let title: String
    let subtitle: String
}

private enum ProviderManagementItem {
    case codex
    case copilot
    case token(TokenProviderCardConfig)
    case unsupported(UnsupportedProviderCardConfig)

    var id: String {
        switch self {
        case .codex:
            "codex"
        case .copilot:
            "copilot"
        case let .token(config):
            config.id
        case let .unsupported(config):
            config.id
        }
    }

    var title: String {
        switch self {
        case .codex:
            "Codex (ChatGPT OAuth)"
        case .copilot:
            "GitHub Copilot (Live)"
        case let .token(config):
            config.title
        case let .unsupported(config):
            config.title
        }
    }
}

private struct ProviderGlyph: View {
    let providerID: String
    let size: CGFloat
    var containerOpacity: Double = 0.14
    var foreground: Color = .primary

    var body: some View {
        self.iconImage
            .resizable()
            .scaledToFit()
            .frame(width: self.size, height: self.size)
            .foregroundStyle(self.foreground)
            .frame(width: self.size + 12, height: self.size + 12)
            .background(
                Circle()
                    .fill(self.foreground.opacity(self.containerOpacity)))
    }

    private var iconImage: Image {
        if let brandedIcon = Self.brandedTemplateIcon(for: self.providerID)
        {
            return Image(uiImage: brandedIcon)
        }
        return Image(systemName: iOSProviderCatalog.iconSymbolName(for: self.providerID))
    }

    private static func brandedTemplateIcon(for providerID: String) -> UIImage? {
        #if canImport(UIKit)
        guard let iconName = iOSProviderCatalog.brandIconResourceName(for: providerID),
              let image = UIImage(named: iconName)
        else {
            return nil
        }
        return image.withRenderingMode(.alwaysTemplate)
        #else
        return nil
        #endif
    }
}

private struct DashboardCard<Content: View>: View {
    var accent: Color?
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            self.content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(self.baseGradient)
            if let accent {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(accent.opacity(self.colorScheme == .dark ? 0.18 : 0.09))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(self.borderColor, lineWidth: 1)
        }
        .shadow(color: self.shadowColor, radius: 14, x: 0, y: 10)
    }

    private var baseGradient: LinearGradient {
        LinearGradient(
            colors: self.colorScheme == .dark
                ? [Color(red: 0.11, green: 0.13, blue: 0.18), Color(red: 0.09, green: 0.11, blue: 0.16)]
                : [Color.white.opacity(0.88), Color.white.opacity(0.74)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing)
    }

    private var borderColor: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.13) : Color.black.opacity(0.08)
    }

    private var shadowColor: Color {
        self.colorScheme == .dark ? Color.black.opacity(0.36) : Color.black.opacity(0.08)
    }
}

private struct UsageBarRow: View {
    let title: String
    let percentLeft: Double?
    let tint: Color
    let trackTint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(self.title)
                    .font(.footnote.weight(.medium))
                Spacer()
                Text(self.percentLeft.map { String(format: "%.0f%%", $0) } ?? "—")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                let ratio = max(0, min(100, self.percentLeft ?? 0)) / 100
                ZStack(alignment: .leading) {
                    Capsule().fill(self.trackTint)
                    Capsule().fill(self.tint).frame(width: proxy.size.width * ratio)
                }
            }
            .frame(height: 7)
        }
    }
}

private struct ValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(self.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(self.value)
                .font(.subheadline.weight(.medium))
        }
    }
}

private struct DashboardBackground: View {
    let colorScheme: ColorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: self.colorScheme == .dark
                    ? [Color(red: 0.05, green: 0.07, blue: 0.11), Color(red: 0.08, green: 0.1, blue: 0.16)]
                    : [Color(red: 0.9, green: 0.95, blue: 1.0), Color(red: 0.84, green: 0.91, blue: 0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing)

            Circle()
                .fill(
                    LinearGradient(
                        colors: self.colorScheme == .dark
                            ? [Color(red: 0.23, green: 0.33, blue: 0.63).opacity(0.28), .clear]
                            : [Color(red: 0.43, green: 0.62, blue: 0.95).opacity(0.24), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing))
                .frame(width: 380, height: 380)
                .offset(x: 170, y: -220)

            Circle()
                .fill(
                    LinearGradient(
                        colors: self.colorScheme == .dark
                            ? [Color(red: 0.12, green: 0.44, blue: 0.53).opacity(0.28), .clear]
                            : [Color(red: 0.41, green: 0.85, blue: 0.84).opacity(0.24), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing))
                .frame(width: 420, height: 420)
                .offset(x: -180, y: 260)
        }
    }
}

private enum DashboardPalette {
    static func accent(for providerID: String, colorScheme: ColorScheme) -> Color {
        let light: Color
        let dark: Color
        switch iOSProviderCatalog.accentToken(for: providerID) {
        case .ocean:
            light = Color(red: 0.12, green: 0.46, blue: 0.93)
            dark = Color(red: 0.39, green: 0.66, blue: 1.0)
        case .violet:
            light = Color(red: 0.5, green: 0.35, blue: 0.93)
            dark = Color(red: 0.69, green: 0.56, blue: 1.0)
        case .amber:
            light = Color(red: 0.87, green: 0.54, blue: 0.15)
            dark = Color(red: 0.97, green: 0.7, blue: 0.36)
        case .indigo:
            light = Color(red: 0.31, green: 0.41, blue: 0.9)
            dark = Color(red: 0.53, green: 0.66, blue: 1.0)
        case .mint:
            light = Color(red: 0.13, green: 0.64, blue: 0.58)
            dark = Color(red: 0.37, green: 0.82, blue: 0.73)
        case .rose:
            light = Color(red: 0.84, green: 0.34, blue: 0.52)
            dark = Color(red: 0.93, green: 0.56, blue: 0.71)
        case .cyan:
            light = Color(red: 0.07, green: 0.58, blue: 0.78)
            dark = Color(red: 0.35, green: 0.79, blue: 0.93)
        case .neutral:
            light = Color(red: 0.36, green: 0.48, blue: 0.67)
            dark = Color(red: 0.63, green: 0.71, blue: 0.85)
        }
        return colorScheme == .dark ? dark : light
    }
}

private enum ProviderActionButtonKind {
    case primary
    case secondary
    case destructive
}

private struct ProviderManagementButton: View {
    let title: String
    let systemImage: String
    let kind: ProviderActionButtonKind
    var expands: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        switch self.kind {
        case .primary:
            self.baseButton.buttonStyle(.borderedProminent)
        case .secondary:
            self.baseButton.buttonStyle(.bordered)
        case .destructive:
            self.baseButton.buttonStyle(.bordered).tint(.red)
        }
    }

    private var baseButton: some View {
        Button(action: self.action) {
            Label(self.title, systemImage: self.systemImage)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: self.expands ? .infinity : nil)
        }
        .disabled(self.disabled)
    }
}

private enum ProviderActionButtonSize {
    case compact
    case regular
}

private struct ProviderActionButton: View {
    let title: String
    let systemImage: String
    let accent: Color
    let kind: ProviderActionButtonKind
    var size: ProviderActionButtonSize = .regular
    var expands: Bool = false
    var disabled: Bool = false
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: self.action) {
            Label {
                Text(self.title)
                    .font(self.size == .compact ? .footnote.weight(.semibold) : .subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            } icon: {
                Image(systemName: self.systemImage)
                    .font(.system(size: self.size == .compact ? 11 : 13, weight: .semibold))
            }
            .frame(maxWidth: self.expands ? .infinity : nil)
            .padding(.horizontal, self.horizontalPadding)
            .padding(.vertical, self.verticalPadding)
        }
        .buttonStyle(.plain)
        .foregroundStyle(self.foregroundColor)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(self.fillStyle))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(self.strokeColor, lineWidth: 1))
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(self.topHighlightColor, lineWidth: 0.7)
                .padding(.horizontal, 0.5)
        }
        .opacity(self.disabled ? 0.52 : 1)
        .disabled(self.disabled)
    }

    private var horizontalPadding: CGFloat {
        switch (self.size, self.expands) {
        case (.compact, true):
            11
        case (.compact, false):
            10
        case (.regular, true):
            12
        case (.regular, false):
            14
        }
    }

    private var verticalPadding: CGFloat {
        self.size == .compact ? 7 : 10
    }

    private var foregroundColor: Color {
        if self.disabled {
            return self.colorScheme == .dark ? Color.white.opacity(0.46) : Color.black.opacity(0.4)
        }
        switch self.kind {
        case .primary:
            return .white
        case .secondary:
            return self.colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.82)
        case .destructive:
            return self.colorScheme == .dark ? Color(red: 1.0, green: 0.67, blue: 0.67) : Color(
                red: 0.78,
                green: 0.15,
                blue: 0.22)
        }
    }

    private var fillStyle: AnyShapeStyle {
        switch self.kind {
        case .primary:
            AnyShapeStyle(
                LinearGradient(
                    colors: [self.accent.opacity(0.95), self.accent.opacity(self.colorScheme == .dark ? 0.72 : 0.78)],
                    startPoint: .top,
                    endPoint: .bottom))
        case .secondary:
            AnyShapeStyle(self.colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.7))
        case .destructive:
            AnyShapeStyle(self.colorScheme == .dark ? Color.red.opacity(0.2) : Color.red.opacity(0.1))
        }
    }

    private var strokeColor: Color {
        switch self.kind {
        case .primary:
            self.accent.opacity(self.colorScheme == .dark ? 0.48 : 0.42)
        case .secondary:
            self.colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.08)
        case .destructive:
            self.colorScheme == .dark ? Color.red.opacity(0.4) : Color.red.opacity(0.3)
        }
    }

    private var topHighlightColor: Color {
        if self.disabled {
            return Color.clear
        }
        switch self.kind {
        case .primary:
            return Color.white.opacity(self.colorScheme == .dark ? 0.24 : 0.34)
        case .secondary:
            return Color.white.opacity(self.colorScheme == .dark ? 0.14 : 0.28)
        case .destructive:
            return Color.white.opacity(self.colorScheme == .dark ? 0.12 : 0.22)
        }
    }
}

private struct SnapshotImportSheet: View {
    @Bindable var viewModel: UsageDashboardViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Paste snapshot JSON")
                    .font(.headline)
                Text("Expected format is `widget-snapshot.json` from CodexBar.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextEditor(text: self.$viewModel.importJSON)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 260)
                    .scrollContentBackground(.hidden)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(self.colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.quaternary, lineWidth: 1))
                if let error = self.viewModel.importErrorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Import")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        self.dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        self.viewModel.importSnapshotFromJSON()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .background {
            DashboardBackground(colorScheme: self.colorScheme)
                .ignoresSafeArea()
        }
    }
}

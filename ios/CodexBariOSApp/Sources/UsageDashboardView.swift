import CodexBariOSShared
import SwiftUI

struct UsageDashboardView: View {
    @Bindable var viewModel: UsageDashboardViewModel

    var body: some View {
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
                    Button("Import JSON") {
                        self.viewModel.showingImportSheet = true
                    }
                    Button("Refresh") {
                        self.viewModel.loadSnapshot()
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
            VStack(alignment: .leading, spacing: 16) {
                self.codexAuthCard
                self.copilotAuthCard
                self.additionalProviderCards

                let available = snapshot.availableProviderIDs
                if available.count > 1 {
                    Picker("Provider", selection: Binding(
                        get: { self.viewModel.selectedProviderID ?? available.first ?? summary.providerID },
                        set: { self.viewModel.selectProvider($0) }))
                    {
                        ForEach(available, id: \.self) { providerID in
                            Text(iOSProviderCatalog.displayName(for: providerID))
                                .tag(providerID)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(summary.displayName)
                        .font(.title2.weight(.semibold))
                    Text("Updated \(Self.relativeDate(summary.updatedAt))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    ValueRow(title: "Plan", value: Self.planLabel(summary.planType))

                    UsageBarRow(title: "Session", percentLeft: summary.sessionRemainingPercent, tint: .teal)
                    UsageBarRow(title: "Weekly", percentLeft: summary.weeklyRemainingPercent, tint: .orange)

                    if let codeReview = summary.codeReviewRemainingPercent {
                        UsageBarRow(title: "Code review", percentLeft: codeReview, tint: .blue)
                    }

                    Divider()

                    ValueRow(title: "Credits", value: summary.creditsRemaining.map(Self.decimal) ?? "—")
                    ValueRow(title: "Today cost", value: summary.todayCostUSD.map(Self.usd) ?? "—")
                    ValueRow(title: "30d cost", value: summary.last30DaysCostUSD.map(Self.usd) ?? "—")
                    ValueRow(
                        title: "Today tokens",
                        value: summary.todayTokens.map(Self.integer) ?? "—")
                    ValueRow(
                        title: "30d tokens",
                        value: summary.last30DaysTokens.map(Self.integer) ?? "—")
                }
                .padding(16)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            }
            .padding()
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 12) {
                self.codexAuthCard
                self.copilotAuthCard
                self.additionalProviderCards

                Text("No usage snapshot yet")
                    .font(.headline)
                Text("Use live sign-in, provider API keys, import `widget-snapshot.json`, or load sample data.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Load Sample Data") {
                    self.viewModel.loadSampleData()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
        }
    }

    private var codexAuthCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Codex (ChatGPT OAuth)")
                .font(.headline)

            if self.viewModel.hasCodexCredentials {
                Text("Signed in. Refresh to pull live Codex usage for your Plus/Pro account.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Refresh Codex Usage") {
                        Task { await self.viewModel.refreshCodexUsage() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(self.viewModel.isRefreshingCodexUsage || self.viewModel.isAuthenticatingCodex)

                    Button("Sign Out") {
                        self.viewModel.clearCodexCredentials()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Text("Sign in with ChatGPT Device Flow to fetch real Codex usage.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Start ChatGPT Sign-In") {
                    Task { await self.viewModel.startCodexDeviceLogin() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(self.viewModel.isAuthenticatingCodex)
            }

            if let code = self.viewModel.codexDeviceCode {
                VStack(alignment: .leading, spacing: 6) {
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
                    HStack {
                        Button("Open ChatGPT") {
                            self.viewModel.openCodexVerificationURL()
                        }
                        .buttonStyle(.bordered)

                        Button("Complete Sign-In") {
                            Task { await self.viewModel.completeCodexDeviceLogin() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(self.viewModel.isAuthenticatingCodex)
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
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
        .padding(16)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private var copilotAuthCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GitHub Copilot (Live)")
                .font(.headline)

            if self.viewModel.hasCopilotToken {
                Text("Signed in. You can refresh live usage anytime.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Refresh Live Usage") {
                        Task { await self.viewModel.refreshCopilotUsage() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(self.viewModel.isRefreshingCopilotUsage || self.viewModel.isAuthenticatingCopilot)

                    Button("Sign Out") {
                        self.viewModel.clearCopilotToken()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Text("Sign in with GitHub Device Flow to fetch real Copilot usage.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Start GitHub Sign-In") {
                    Task { await self.viewModel.startCopilotDeviceLogin() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(self.viewModel.isAuthenticatingCopilot)
            }

            if let code = self.viewModel.copilotDeviceCode {
                VStack(alignment: .leading, spacing: 6) {
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
                    HStack {
                        Button("Open Verification URL") {
                            self.viewModel.openCopilotVerificationURL()
                        }
                        .buttonStyle(.bordered)

                        Button("Complete Sign-In") {
                            Task { await self.viewModel.completeCopilotDeviceLogin() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(self.viewModel.isAuthenticatingCopilot)
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
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
        .padding(16)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private var additionalProviderCards: some View {
        Group {
            ForEach(Self.tokenProviderConfigs) { config in
                self.tokenProviderCard(config)
            }
            ForEach(Self.unsupportedProviderConfigs) { config in
                self.unsupportedProviderCard(config)
            }
        }
    }

    private func tokenProviderCard(_ config: TokenProviderCardConfig) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(config.title)
                .font(.headline)

            Text(config.subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)

            SecureField(config.placeholder, text: Binding(
                get: { self.viewModel.tokenDraft(for: config.id) },
                set: { self.viewModel.setTokenDraft($0, for: config.id) }))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.footnote.monospaced())
                .padding(10)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))

            if self.viewModel.hasProviderToken(config.id) {
                Text("Credentials are stored in Keychain.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Save Credentials") {
                    self.viewModel.saveProviderToken(config.id)
                }
                .buttonStyle(.bordered)

                Button("Refresh Usage") {
                    Task { await self.viewModel.refreshProviderUsage(config.id) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!self.viewModel.hasProviderToken(config.id) || self.viewModel.isProviderRefreshing(config.id))

                Button("Clear") {
                    self.viewModel.clearProviderToken(config.id)
                }
                .buttonStyle(.bordered)
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
        .padding(16)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private func unsupportedProviderCard(_ config: UnsupportedProviderCardConfig) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(config.title)
                .font(.headline)
            Text(config.subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
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
            .map { $0.capitalized }
            .joined(separator: " ")
    }

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

private struct UsageBarRow: View {
    let title: String
    let percentLeft: Double?
    let tint: Color

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
                    Capsule().fill(Color.primary.opacity(0.12))
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

private struct SnapshotImportSheet: View {
    @Bindable var viewModel: UsageDashboardViewModel
    @Environment(\.dismiss) private var dismiss

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
    }
}

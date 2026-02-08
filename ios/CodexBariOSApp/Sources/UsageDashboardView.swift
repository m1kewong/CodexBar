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
                self.copilotAuthCard

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
                self.copilotAuthCard

                Text("No usage snapshot yet")
                    .font(.headline)
                Text("Use GitHub sign-in + live refresh, import `widget-snapshot.json`, or load sample data.")
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

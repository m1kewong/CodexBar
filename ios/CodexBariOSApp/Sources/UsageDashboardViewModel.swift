import CodexBariOSShared
import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif
import WidgetKit

@MainActor
@Observable
final class UsageDashboardViewModel {
    var snapshot: iOSWidgetSnapshot?
    var selectedProviderID: String?
    var importJSON = ""
    var importErrorMessage: String?
    var showingImportSheet = false
    var authErrorMessage: String?
    var authStatusMessage: String?
    var liveRefreshStatusMessage: String?
    var codexAuthErrorMessage: String?
    var codexAuthStatusMessage: String?
    var codexRefreshStatusMessage: String?
    var isAuthenticatingCopilot = false
    var isRefreshingCopilotUsage = false
    var copilotDeviceCode: iOSCopilotDeviceFlow.DeviceCodeResponse?
    var hasCopilotToken = false
    var isAuthenticatingCodex = false
    var isRefreshingCodexUsage = false
    var codexDeviceCode: iOSCodexOAuthDeviceCode?
    var hasCodexCredentials = false

    var providerTokenDrafts: [String: String] = [:]
    var providerStatusMessages: [String: String] = [:]
    var providerErrorMessages: [String: String] = [:]
    var providerHasToken: [String: Bool] = [:]
    var providerRefreshingIDs: Set<String> = []

    private static let apiTokenProviderIDs = [
        "claude",
        "cursor",
        "opencode",
        "augment",
        "factory",
        "amp",
        "gemini",
        "vertexai",
        "zai",
        "minimax",
        "synthetic",
        "kimik2",
        "kimi",
    ]

    var selectedSummary: iOSWidgetSnapshot.ProviderSummary? {
        guard let snapshot else { return nil }
        let selected = snapshot.selectedProviderID(preferred: self.selectedProviderID)
        return snapshot.providerSummaries.first { $0.providerID == selected }
    }

    func loadSnapshot() {
        let snapshot = iOSWidgetSnapshotStore.load()
        let storedProvider = iOSWidgetSnapshotStore.loadSelectedProviderID()
        self.snapshot = snapshot
        self.selectedProviderID = snapshot?.selectedProviderID(preferred: storedProvider ?? self.selectedProviderID)
        self.importErrorMessage = nil
        self.hasCopilotToken = CopilotTokenStore.load() != nil
        self.hasCodexCredentials = CodexCredentialsStore.load() != nil
        self.refreshProviderTokenPresence()
    }

    func loadSampleData() {
        let sample = iOSWidgetPreviewData.snapshot()
        iOSWidgetSnapshotStore.save(sample)
        self.snapshot = sample
        self.selectedProviderID = sample.selectedProviderID(preferred: self.selectedProviderID)
        self.importErrorMessage = nil
    }

    func selectProvider(_ providerID: String) {
        self.selectedProviderID = providerID
        iOSWidgetSnapshotStore.saveSelectedProviderID(providerID)
    }

    func importSnapshotFromJSON() {
        guard let data = self.importJSON.data(using: .utf8) else {
            self.importErrorMessage = "Could not parse pasted text as UTF-8."
            return
        }
        do {
            let snapshot = try iOSWidgetSnapshot.decode(from: data)
            iOSWidgetSnapshotStore.save(snapshot)
            self.snapshot = snapshot
            self.selectedProviderID = snapshot.selectedProviderID(preferred: self.selectedProviderID)
            self.importErrorMessage = nil
            self.showingImportSheet = false
            self.importJSON = ""
        } catch {
            self.importErrorMessage = "Invalid snapshot JSON: \(error.localizedDescription)"
        }
    }

    func tokenDraft(for providerID: String) -> String {
        self.providerTokenDrafts[providerID] ?? ""
    }

    func setTokenDraft(_ value: String, for providerID: String) {
        self.providerTokenDrafts[providerID] = value
    }

    func hasProviderToken(_ providerID: String) -> Bool {
        self.providerHasToken[providerID] ?? false
    }

    func providerStatus(for providerID: String) -> String? {
        self.providerStatusMessages[providerID]
    }

    func providerError(for providerID: String) -> String? {
        self.providerErrorMessages[providerID]
    }

    func isProviderRefreshing(_ providerID: String) -> Bool {
        self.providerRefreshingIDs.contains(providerID)
    }

    func hasCredentials(for providerID: String) -> Bool {
        switch providerID {
        case "codex":
            self.hasCodexCredentials
        case "copilot":
            self.hasCopilotToken
        default:
            self.hasProviderToken(providerID)
        }
    }

    func isRefreshing(providerID: String) -> Bool {
        switch providerID {
        case "codex":
            self.isAuthenticatingCodex || self.isRefreshingCodexUsage
        case "copilot":
            self.isAuthenticatingCopilot || self.isRefreshingCopilotUsage
        default:
            self.isProviderRefreshing(providerID)
        }
    }

    func refreshProvider(providerID: String) async {
        switch providerID {
        case "codex":
            await self.refreshCodexUsage()
        case "copilot":
            await self.refreshCopilotUsage()
        default:
            await self.refreshProviderUsage(providerID)
        }
    }

    func saveProviderToken(_ providerID: String) {
        guard Self.apiTokenProviderIDs.contains(providerID) else { return }
        let token = self.providerTokenDrafts[providerID]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !token.isEmpty else {
            self.providerErrorMessages[providerID] = "Paste a token first."
            self.providerStatusMessages[providerID] = nil
            return
        }

        ProviderAPITokenStore.save(token, for: providerID)
        self.providerHasToken[providerID] = true
        self.providerErrorMessages[providerID] = nil
        self.providerStatusMessages[providerID] = "Credentials saved in Keychain."
    }

    func clearProviderToken(_ providerID: String) {
        guard Self.apiTokenProviderIDs.contains(providerID) else { return }
        ProviderAPITokenStore.clear(providerID)
        self.providerTokenDrafts[providerID] = ""
        self.providerHasToken[providerID] = false
        self.providerErrorMessages[providerID] = nil
        self.providerStatusMessages[providerID] = "Credentials removed."
    }

    func refreshProviderUsage(_ providerID: String) async {
        guard Self.apiTokenProviderIDs.contains(providerID) else { return }
        guard let token = ProviderAPITokenStore.load(providerID), !token.isEmpty else {
            self.providerHasToken[providerID] = false
            self.providerStatusMessages[providerID] = "Save credentials first."
            self.providerErrorMessages[providerID] = nil
            return
        }

        self.providerHasToken[providerID] = true
        self.providerErrorMessages[providerID] = nil
        self.providerStatusMessages[providerID] = "Refreshing \(iOSProviderCatalog.displayName(for: providerID)) usage…"
        self.providerRefreshingIDs.insert(providerID)
        defer { self.providerRefreshingIDs.remove(providerID) }

        do {
            let providerSnapshot = try await self.fetchProviderSnapshot(providerID, token: token)
            self.mergeAndPersist(providerSnapshot: providerSnapshot, providerID: providerID)
            self.selectedProviderID = providerID
            iOSWidgetSnapshotStore.saveSelectedProviderID(providerID)
            WidgetCenter.shared.reloadAllTimelines()
            self.providerStatusMessages[providerID] = "Usage updated."
        } catch {
            self.providerStatusMessages[providerID] = nil
            self.providerErrorMessages[providerID] = "Refresh failed: \(error.localizedDescription)"
        }
    }

    func startCopilotDeviceLogin() async {
        self.authErrorMessage = nil
        self.authStatusMessage = nil
        self.isAuthenticatingCopilot = true
        defer { self.isAuthenticatingCopilot = false }

        do {
            let flow = iOSCopilotDeviceFlow()
            let code = try await flow.requestDeviceCode()
            self.copilotDeviceCode = code
            self.authStatusMessage = "Code ready. Open GitHub and authorize this device."
        } catch {
            self.authErrorMessage = "Could not start GitHub device login: \(error.localizedDescription)"
        }
    }

    func openCopilotVerificationURL() {
        guard let rawURL = self.copilotDeviceCode?.verificationURI,
              let url = URL(string: rawURL)
        else {
            return
        }
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
    }

    func completeCopilotDeviceLogin() async {
        guard let code = self.copilotDeviceCode else {
            self.authErrorMessage = "Start device login first."
            return
        }

        self.authErrorMessage = nil
        self.authStatusMessage = "Waiting for GitHub authorization confirmation…"
        self.isAuthenticatingCopilot = true
        defer { self.isAuthenticatingCopilot = false }

        do {
            let flow = iOSCopilotDeviceFlow()
            let token = try await flow.pollForToken(deviceCode: code.deviceCode, interval: code.interval)
            CopilotTokenStore.save(token)
            self.hasCopilotToken = true
            self.copilotDeviceCode = nil
            self.authStatusMessage = "GitHub sign-in complete."
        } catch is CancellationError {
            self.authStatusMessage = "GitHub sign-in cancelled."
        } catch {
            self.authErrorMessage = "GitHub sign-in failed: \(error.localizedDescription)"
        }
    }

    func clearCopilotToken() {
        CopilotTokenStore.clear()
        self.hasCopilotToken = false
        self.authStatusMessage = "GitHub token removed."
        self.copilotDeviceCode = nil
    }

    func refreshCopilotUsage() async {
        guard let token = CopilotTokenStore.load(), !token.isEmpty else {
            self.liveRefreshStatusMessage = "Sign in with GitHub first."
            self.hasCopilotToken = false
            return
        }

        self.authErrorMessage = nil
        self.liveRefreshStatusMessage = "Refreshing live usage from GitHub…"
        self.isRefreshingCopilotUsage = true
        defer { self.isRefreshingCopilotUsage = false }

        do {
            let response = try await iOSCopilotUsageFetcher(token: token).fetch()
            let copilotSnapshot = iOSCopilotUsageMapper.makeSnapshot(from: response)
            self.mergeAndPersist(copilotSnapshot: copilotSnapshot)
            self.selectedProviderID = "copilot"
            iOSWidgetSnapshotStore.saveSelectedProviderID("copilot")
            WidgetCenter.shared.reloadAllTimelines()
            self.liveRefreshStatusMessage = "Live usage updated."
            self.hasCopilotToken = true
        } catch {
            self.liveRefreshStatusMessage = "Live refresh failed: \(error.localizedDescription)"
        }
    }

    func startCodexDeviceLogin() async {
        self.codexAuthErrorMessage = nil
        self.codexAuthStatusMessage = nil
        self.isAuthenticatingCodex = true
        defer { self.isAuthenticatingCodex = false }

        do {
            let flow = iOSCodexDeviceAuthFlow()
            let code = try await flow.requestDeviceCode()
            self.codexDeviceCode = code
            self.codexAuthStatusMessage = "Code ready. Open ChatGPT and authorize this device."
        } catch {
            self.codexAuthErrorMessage = "Could not start Codex device login: \(error.localizedDescription)"
        }
    }

    func openCodexVerificationURL() {
        guard let rawURL = self.codexDeviceCode?.verificationURL,
              let url = URL(string: rawURL)
        else {
            return
        }
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
    }

    func completeCodexDeviceLogin() async {
        guard let code = self.codexDeviceCode else {
            self.codexAuthErrorMessage = "Start device login first."
            return
        }

        self.codexAuthErrorMessage = nil
        self.codexAuthStatusMessage = "Waiting for ChatGPT authorization confirmation…"
        self.isAuthenticatingCodex = true
        defer { self.isAuthenticatingCodex = false }

        do {
            let flow = iOSCodexDeviceAuthFlow()
            let credentials = try await flow.completeDeviceCodeLogin(code)
            CodexCredentialsStore.save(credentials)
            self.hasCodexCredentials = true
            self.codexDeviceCode = nil
            self.codexAuthStatusMessage = "Codex sign-in complete."
        } catch is CancellationError {
            self.codexAuthStatusMessage = "Codex sign-in cancelled."
        } catch {
            self.codexAuthErrorMessage = "Codex sign-in failed: \(error.localizedDescription)"
        }
    }

    func clearCodexCredentials() {
        CodexCredentialsStore.clear()
        self.hasCodexCredentials = false
        self.codexAuthStatusMessage = "Codex credentials removed."
        self.codexDeviceCode = nil
    }

    func refreshCodexUsage() async {
        guard var credentials = CodexCredentialsStore.load() else {
            self.codexRefreshStatusMessage = "Sign in to Codex first."
            self.hasCodexCredentials = false
            return
        }

        self.codexAuthErrorMessage = nil
        self.codexRefreshStatusMessage = "Refreshing live Codex usage…"
        self.isRefreshingCodexUsage = true
        defer { self.isRefreshingCodexUsage = false }

        do {
            if credentials.needsRefresh {
                credentials = try await iOSCodexTokenRefresher.refresh(credentials)
                CodexCredentialsStore.save(credentials)
            }

            let response = try await iOSCodexUsageFetcher.fetchUsage(credentials: credentials)
            self.applyCodexUsageRefreshResult(response: response, credentials: credentials)
        } catch iOSCodexOAuthFetchError.unauthorized {
            do {
                credentials = try await iOSCodexTokenRefresher.refresh(credentials)
                CodexCredentialsStore.save(credentials)
                let response = try await iOSCodexUsageFetcher.fetchUsage(credentials: credentials)
                self.applyCodexUsageRefreshResult(response: response, credentials: credentials)
            } catch {
                self.handleCodexRefreshError(error)
            }
        } catch {
            self.handleCodexRefreshError(error)
        }
    }

    private func applyCodexUsageRefreshResult(
        response: iOSCodexUsageResponse,
        credentials: iOSCodexOAuthCredentials)
    {
        let codexSnapshot = iOSCodexUsageMapper.makeSnapshot(from: response, credentials: credentials)
        self.mergeAndPersist(providerSnapshot: codexSnapshot, providerID: "codex")
        self.selectedProviderID = "codex"
        iOSWidgetSnapshotStore.saveSelectedProviderID("codex")
        WidgetCenter.shared.reloadAllTimelines()
        self.codexRefreshStatusMessage = "Codex usage updated."
        self.hasCodexCredentials = true
    }

    private func handleCodexRefreshError(_ error: Error) {
        if let refreshError = error as? iOSCodexTokenRefresher.RefreshError {
            switch refreshError {
            case .expired, .revoked, .reused:
                CodexCredentialsStore.clear()
                self.hasCodexCredentials = false
                self.codexDeviceCode = nil
            case .networkError, .invalidResponse:
                break
            }
        } else if let fetchError = error as? iOSCodexOAuthFetchError {
            switch fetchError {
            case .unauthorized:
                CodexCredentialsStore.clear()
                self.hasCodexCredentials = false
                self.codexDeviceCode = nil
            case .invalidResponse, .serverError, .networkError:
                break
            }
        }

        self.codexRefreshStatusMessage = "Codex refresh failed: \(error.localizedDescription)"
    }

    private func fetchProviderSnapshot(_ providerID: String, token: String) async throws -> iOSWidgetSnapshot {
        switch providerID {
        case "claude":
            let usage = try await iOSClaudeWebUsageFetcher.fetchUsage(sessionCredential: token)
            return iOSClaudeWebUsageMapper.makeSnapshot(from: usage)
        case "cursor":
            let usage = try await iOSCursorUsageFetcher.fetchUsage(cookieHeader: token)
            return iOSCursorUsageMapper.makeSnapshot(from: usage)
        case "opencode":
            let usage = try await iOSOpenCodeUsageFetcher.fetchUsage(cookieCredential: token)
            return iOSOpenCodeUsageMapper.makeSnapshot(from: usage)
        case "augment":
            let usage = try await iOSAugmentUsageFetcher.fetchUsage(cookieHeader: token)
            return iOSAugmentUsageMapper.makeSnapshot(from: usage)
        case "factory":
            let usage = try await iOSFactoryUsageFetcher.fetchUsage(cookieHeader: token)
            return iOSFactoryUsageMapper.makeSnapshot(from: usage)
        case "amp":
            let usage = try await iOSAmpUsageFetcher.fetchUsage(cookieHeader: token)
            return iOSAmpUsageMapper.makeSnapshot(from: usage)
        case "gemini":
            let usage = try await iOSGeminiUsageFetcher.fetchUsage(accessToken: token)
            return iOSGeminiUsageMapper.makeSnapshot(from: usage)
        case "vertexai":
            let (projectID, accessToken) = try self.parseVertexAICredential(token)
            let usage = try await iOSVertexAIUsageFetcher.fetchUsage(projectID: projectID, accessToken: accessToken)
            return iOSVertexAIUsageMapper.makeSnapshot(from: usage)
        case "zai":
            let usage = try await iOSZaiUsageFetcher.fetchUsage(apiKey: token)
            return iOSZaiUsageMapper.makeSnapshot(from: usage)
        case "minimax":
            let usage = try await iOSMiniMaxUsageFetcher.fetchUsage(apiToken: token)
            return iOSMiniMaxUsageMapper.makeSnapshot(from: usage)
        case "synthetic":
            let usage = try await iOSSyntheticUsageFetcher.fetchUsage(apiKey: token)
            return iOSSyntheticUsageMapper.makeSnapshot(from: usage)
        case "kimik2":
            let usage = try await iOSKimiK2UsageFetcher.fetchUsage(apiKey: token)
            return iOSKimiK2UsageMapper.makeSnapshot(from: usage)
        case "kimi":
            let response = try await iOSKimiUsageFetcher(authToken: token).fetch()
            return try iOSKimiUsageMapper.makeSnapshot(from: response)
        default:
            throw UnsupportedProviderError(providerID: providerID)
        }
    }

    private func parseVertexAICredential(_ raw: String) throws -> (projectID: String, accessToken: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let separators = ["||", "|", "\n"]
        for separator in separators {
            if let range = trimmed.range(of: separator) {
                let projectID = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let accessToken = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !projectID.isEmpty, !accessToken.isEmpty {
                    return (projectID, accessToken)
                }
            }
        }
        throw InvalidCredentialFormatError(providerID: "vertexai", expectedFormat: "project_id||access_token")
    }

    private func refreshProviderTokenPresence() {
        for providerID in Self.apiTokenProviderIDs {
            self.providerHasToken[providerID] = ProviderAPITokenStore.load(providerID) != nil
        }
    }

    private func mergeAndPersist(providerSnapshot: iOSWidgetSnapshot, providerID: String) {
        guard let providerEntry = providerSnapshot.entries.first else { return }
        let base = self.snapshot

        var entries = base?.entries.filter { $0.providerID != providerID } ?? []
        entries.append(providerEntry)

        var enabled: Set<String> = Set(base?.enabledProviderIDs ?? [])
        enabled.insert(providerID)
        let merged = iOSWidgetSnapshot(
            entries: entries,
            enabledProviderIDs: Array(enabled).sorted(),
            generatedAt: Date())

        iOSWidgetSnapshotStore.save(merged)
        self.snapshot = merged
    }

    private func mergeAndPersist(copilotSnapshot: iOSWidgetSnapshot) {
        self.mergeAndPersist(providerSnapshot: copilotSnapshot, providerID: "copilot")
    }
}

private struct UnsupportedProviderError: LocalizedError {
    let providerID: String

    var errorDescription: String? {
        "Unsupported provider: \(self.providerID)"
    }
}

private struct InvalidCredentialFormatError: LocalizedError {
    let providerID: String
    let expectedFormat: String

    var errorDescription: String? {
        "Invalid \(self.providerID) credential format. Use \(self.expectedFormat)."
    }
}

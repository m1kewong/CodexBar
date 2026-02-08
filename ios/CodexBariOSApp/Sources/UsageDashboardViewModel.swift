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
    var isAuthenticatingCopilot = false
    var isRefreshingCopilotUsage = false
    var copilotDeviceCode: iOSCopilotDeviceFlow.DeviceCodeResponse?
    var hasCopilotToken = false

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

    private func mergeAndPersist(copilotSnapshot: iOSWidgetSnapshot) {
        guard let copilotEntry = copilotSnapshot.entries.first else { return }
        let base = self.snapshot

        var entries = base?.entries.filter { $0.providerID != "copilot" } ?? []
        entries.append(copilotEntry)

        var enabled: Set<String> = Set(base?.enabledProviderIDs ?? [])
        enabled.insert("copilot")
        let merged = iOSWidgetSnapshot(
            entries: entries,
            enabledProviderIDs: Array(enabled).sorted(),
            generatedAt: Date())

        iOSWidgetSnapshotStore.save(merged)
        self.snapshot = merged
    }
}

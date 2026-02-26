import BackgroundTasks
import Foundation
import SwiftUI

@main
struct CodexBariOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = UsageDashboardViewModel()

    var body: some Scene {
        WindowGroup {
            UsageDashboardView(viewModel: self.viewModel)
                .task {
                    UsageBackgroundRefreshScheduler.schedule()
                }
        }
        .backgroundTask(.appRefresh(UsageBackgroundRefreshScheduler.taskIdentifier)) {
            _ = await self.viewModel.performBackgroundRefresh()
            UsageBackgroundRefreshScheduler.schedule()
        }
        .onChange(of: self.scenePhase) { _, newPhase in
            if newPhase == .background {
                UsageBackgroundRefreshScheduler.schedule()
            }
        }
    }
}

private enum UsageBackgroundRefreshScheduler {
    static let taskIdentifier = "com.steipete.codexbar.ios.usage-refresh"
    private static let minimumInterval: TimeInterval = 2 * 60 * 60

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Self.minimumInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            #if DEBUG
            print("Failed to schedule background refresh: \(error)")
            #endif
        }
    }
}

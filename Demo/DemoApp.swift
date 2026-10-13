import SwiftUI
import AgentJobRelay

/// Launch arguments (handy for screenshots and UI tests):
///   -profile clean|flaky|hostile   chaos applied to the foreground stream (default: flaky)
///   -seed <n>                      reproducible run (default: 2026)
///   -paused                        do not auto-play on launch
@main
struct AgentJobRelayDemoApp: App {
    @State private var model = RelayDemoModel(configuration: .fromLaunchArguments(ProcessInfo.processInfo.arguments))

    var body: some Scene {
        WindowGroup {
            RelayDashboardView(model: model)
        }
    }
}

import AppKit
import SwiftUI

@MainActor
@main
struct MacupApp: App {
    @State private var store = ProfileStore()
    @State private var runner = StartupRunner()
    @State private var loginItemManager = LoginItemManager()
    @State private var hasTriggeredAutoStartup = false

    var body: some Scene {
        Window("macup", id: "main") {
            ContentView(store: store, runner: runner, loginItemManager: loginItemManager)
                .onAppear {
                    triggerAutoStartupIfNeeded()
                }
        }
        .defaultSize(width: 960, height: 640)

        MenuBarExtra("macup", systemImage: "rectangle.3.group") {
            MenuBarView(store: store, runner: runner, loginItemManager: loginItemManager)
        }
    }

    private func triggerAutoStartupIfNeeded() {
        guard !hasTriggeredAutoStartup else { return }
        hasTriggeredAutoStartup = true

        let forceStartupArg = CommandLine.arguments.contains("--run-default")
        guard forceStartupArg || store.settings.runDefaultOnAppLaunch,
              let defaultProfile = store.defaultProfile else {
            return
        }

        let delay = max(0, store.settings.startupDelaySeconds)
        Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            runner.run(profile: defaultProfile)
        }
    }
}

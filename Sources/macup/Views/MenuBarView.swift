import AppKit
import SwiftUI

@MainActor
public struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    let store: ProfileStore
    let runner: StartupRunner
    let loginItemManager: LoginItemManager

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if runner.isRunning, let name = runner.activeProfileName {
                Label("Running \"\(name)\"…", systemImage: "hourglass")
                    .font(.caption.bold())
                Button("Stop Execution") {
                    runner.cancel()
                }
                Divider()
            }

            Text("Run Profile")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(store.profiles) { profile in
                Button {
                    runner.run(profile: profile)
                } label: {
                    Label(
                        profile.isDefaultOnStartup ? "\(profile.name) ★" : profile.name,
                        systemImage: profile.icon
                    )
                }
                .disabled(runner.isRunning)
            }

            Divider()

            Button("Configure macup…") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",")

            if loginItemManager.isRunningAsAppBundle {
                Toggle("Launch at Login", isOn: Binding(
                    get: { loginItemManager.isEnabled },
                    set: { loginItemManager.setEnabled($0) }
                ))
            }

            Divider()

            Button("Quit macup") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

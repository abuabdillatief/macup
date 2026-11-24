import AppKit
import SwiftUI

@MainActor
public struct ProfileDetailView: View {
    @Binding var profile: WorkspaceProfile
    let isDefault: Bool
    let onSetDefault: () -> Void
    let runner: StartupRunner

    @State private var accessibilityGranted = WindowManager.isAccessibilityGranted
    @State private var activeDesktopForPicker: UUID?
    @State private var showLogs = false

    private let availableIcons = [
        "laptopcomputer", "terminal", "sparkles", "briefcase",
        "house", "hammer", "book", "music.note", "gamecontroller", "globe"
    ]

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection

                    if !accessibilityGranted {
                        accessibilityBanner
                    }

                    cliCommandsSection
                    desktopsSection
                }
                .padding(20)
            }

            Divider()
            logDrawer
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityGranted = WindowManager.isAccessibilityGranted
        }
        .sheet(isPresented: Binding(
            get: { activeDesktopForPicker != nil },
            set: { if !$0 { activeDesktopForPicker = nil } }
        )) {
            if let desktopId = activeDesktopForPicker,
               let idx = profile.desktops.firstIndex(where: { $0.id == desktopId }) {
                AppPickerSheet { newApp in
                    profile.desktops[idx].apps.append(newApp)
                }
            }
        }
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 14) {
            Menu {
                ForEach(availableIcons, id: \.self) { iconName in
                    Button {
                        profile.icon = iconName
                    } label: {
                        Label(iconName, systemImage: iconName)
                    }
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: profile.icon)
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .buttonStyle(.plain)
            .help("Change profile icon")

            VStack(alignment: .leading, spacing: 4) {
                TextField("Profile Name", text: $profile.name)
                    .font(.title2.bold())
                    .textFieldStyle(.plain)

                HStack(spacing: 10) {
                    if isDefault {
                        Label("Default on Startup", systemImage: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Button("Set as Startup Default") {
                            onSetDefault()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }

                    Text("•")
                        .foregroundStyle(.secondary)
                    Text("\(profile.commands.count) commands, \(profile.desktops.count) desktops")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if runner.isRunning {
                Button(role: .destructive) {
                    runner.cancel()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .controlSize(.large)
            } else {
                Button {
                    showLogs = true
                    runner.run(profile: profile)
                } label: {
                    Label("Run Profile", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private var accessibilityBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility Permission Required")
                    .font(.subheadline.bold())
                Text("Grant Accessibility access so macup can tile windows (left/right/corners) and switch Desktop spaces.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Grant Access") {
                WindowManager.requestAccessibilityPermission()
                WindowManager.openAccessibilitySettings()
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.1))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.35), lineWidth: 1))
        )
    }

    private var cliCommandsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("CLI Commands", systemImage: "terminal")
                    .font(.headline)
                Spacer()
                Button {
                    profile.commands.append(CLICommandItem(name: "New Command", command: "echo hello"))
                } label: {
                    Label("Add Command", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if profile.commands.isEmpty {
                emptyCard(text: "No CLI commands yet. Add shell scripts, dev servers, or startup commands.")
            } else {
                VStack(spacing: 8) {
                    ForEach($profile.commands) { $cmd in
                        cliCommandCard($cmd)
                    }
                }
            }
        }
    }

    private func cliCommandCard(_ cmd: Binding<CLICommandItem>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Toggle("", isOn: cmd.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.checkbox)

                TextField("Label", text: cmd.name)
                    .font(.subheadline.bold())
                    .textFieldStyle(.plain)

                Spacer()

                Toggle("Open in Terminal", isOn: cmd.runInTerminal)
                    .font(.caption)
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                Button {
                    showLogs = true
                    runner.testCommand(cmd.wrappedValue)
                } label: {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.plain)
                .help("Test command now")

                Button(role: .destructive) {
                    profile.commands.removeAll { $0.id == cmd.wrappedValue.id }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove command")
            }

            HStack(spacing: 8) {
                Text("$")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                TextField("Shell command (e.g. brew services start postgresql)", text: cmd.command)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("Dir:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("~", text: cmd.workingDirectory)
                        .font(.caption.monospaced())
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
                }

                HStack(spacing: 4) {
                    Text("Delay:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("0", value: cmd.delaySeconds, format: .number)
                        .font(.caption)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 48)
                    Text("sec")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.18), lineWidth: 1))
        )
    }

    private var desktopsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Desktops & Window Layouts", systemImage: "macwindow.on.rectangle")
                    .font(.headline)
                Spacer()
                Button {
                    let nextSpace = min(9, (profile.desktops.map(\.spaceIndex).max() ?? 0) + 1)
                    profile.desktops.append(DesktopLayout(name: "Desktop \(nextSpace)", spaceIndex: nextSpace, apps: []))
                } label: {
                    Label("Add Desktop", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Text("Tip: Switching to Desktop 1–9 uses macOS Mission Control shortcuts (Control + 1…9). Enable them in System Settings → Keyboard → Keyboard Shortcuts → Mission Control.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if profile.desktops.isEmpty {
                emptyCard(text: "No desktops configured. Add a desktop to launch and snap apps into halves, corners, or thirds.")
            } else {
                VStack(spacing: 14) {
                    ForEach($profile.desktops) { $desktop in
                        desktopCard($desktop)
                    }
                }
            }
        }
    }

    private func desktopCard(_ desktop: Binding<DesktopLayout>) -> some View {
        let screensCount = max(1, NSScreen.screens.count)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TextField("Desktop Name", text: desktop.name)
                    .font(.headline)
                    .textFieldStyle(.plain)

                Spacer()

                Picker("Space", selection: desktop.spaceIndex) {
                    Text("Current Desktop").tag(0)
                    ForEach(1...9, id: \.self) { num in
                        Text("Desktop \(num)").tag(num)
                    }
                }
                .frame(width: 150)
                .help("Switches to this Desktop, automatically creating it in Mission Control if it doesn't exist yet")

                Button(role: .destructive) {
                    profile.desktops.removeAll { $0.id == desktop.wrappedValue.id }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove desktop")
            }

            // Visual layout preview
            DesktopLayoutPreview(apps: desktop.wrappedValue.apps)

            // App list
            if desktop.wrappedValue.apps.isEmpty {
                Text("No apps in this desktop yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 6) {
                    ForEach(desktop.apps) { $app in
                        appRowCard(app: $app, screensCount: screensCount) {
                            desktop.wrappedValue.apps.removeAll { $0.id == app.id }
                        }
                    }
                }
            }

            HStack {
                Button {
                    activeDesktopForPicker = desktop.wrappedValue.id
                } label: {
                    Label("Add App to \(desktop.wrappedValue.name)", systemImage: "plus.app")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Spacer()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
        )
    }

    private func appRowCard(
        app: Binding<AppLaunchItem>,
        screensCount: Int,
        onRemove: @escaping () -> Void
    ) -> some View {
        let item = app.wrappedValue
        let showURLSection = item.isBrowser || !item.urls.isEmpty

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Toggle("", isOn: app.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.checkbox)

                Image(nsImage: NSWorkspace.shared.icon(forFile: item.appPath))
                    .resizable()
                    .frame(width: 22, height: 22)

                Text(item.appName)
                    .font(.subheadline.weight(.medium))
                    .frame(minWidth: 100, alignment: .leading)

                PlacementMiniIcon(placement: item.placement, width: 24, height: 16)

                Picker("", selection: app.placement) {
                    ForEach(WindowPlacement.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .labelsHidden()
                .frame(width: 165)

                if screensCount > 1 {
                    Picker("", selection: app.screenIndex) {
                        ForEach(0..<screensCount, id: \.self) { sIdx in
                            Text("Display \(sIdx + 1)").tag(sIdx)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 96)
                }

                Spacer()

                if !showURLSection {
                    Button {
                        app.wrappedValue.urls.append("")
                    } label: {
                        Image(systemName: "globe")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Add a URL or deep link to open with this app")
                }

                Button {
                    showLogs = true
                    runner.testApp(item)
                } label: {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.plain)
                .help("Test launching & placing this app")

                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove app")
            }

            if showURLSection {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(item.urls.indices, id: \.self) { urlIdx in
                        HStack(spacing: 6) {
                            Image(systemName: "globe")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField(
                                "https://example.com",
                                text: Binding(
                                    get: {
                                        guard urlIdx < app.wrappedValue.urls.count else { return "" }
                                        return app.wrappedValue.urls[urlIdx]
                                    },
                                    set: { newValue in
                                        guard urlIdx < app.wrappedValue.urls.count else { return }
                                        app.wrappedValue.urls[urlIdx] = newValue
                                    }
                                )
                            )
                            .font(.caption.monospaced())
                            .textFieldStyle(.roundedBorder)

                            Button {
                                guard urlIdx < app.wrappedValue.urls.count else { return }
                                app.wrappedValue.urls.remove(at: urlIdx)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove URL")
                        }
                    }

                    Button {
                        app.wrappedValue.urls.append("")
                    } label: {
                        Label(
                            item.urls.isEmpty ? "Add URL to open" : "Add another URL",
                            systemImage: "plus.circle"
                        )
                        .font(.caption)
                    }
                    .buttonStyle(.link)
                }
                .padding(.leading, 32)
                .padding(.bottom, 2)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .windowBackgroundColor).opacity(0.6)))
    }

    private func emptyCard(text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.secondary.opacity(0.35))
            )
    }

    private var logDrawer: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showLogs.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showLogs ? "chevron.down" : "chevron.right")
                            .font(.caption)
                        Text("Activity Log (\(runner.logs.count))")
                            .font(.caption.bold())
                    }
                }
                .buttonStyle(.plain)

                if let latest = runner.logs.last, !showLogs {
                    Text(latest.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer()

                if !runner.logs.isEmpty {
                    Button("Clear") {
                        runner.clearLogs()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            if showLogs {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(runner.logs) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                Text(entry.timestamp, style: .time)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                Circle()
                                    .fill(logColor(entry.level))
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 4)
                                Text(entry.message)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                Spacer()
                            }
                        }
                    }
                    .padding(10)
                }
                .frame(height: 130)
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
    }

    private func logColor(_ level: ExecutionLogEntry.Level) -> Color {
        switch level {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

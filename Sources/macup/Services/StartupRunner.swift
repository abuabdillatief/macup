import AppKit
import Foundation

@MainActor
@Observable
public final class StartupRunner {
    public private(set) var isRunning: Bool = false
    public private(set) var activeProfileName: String?
    public private(set) var logs: [ExecutionLogEntry] = []

    private var currentTask: Task<Void, Never>?

    public init() {}

    public func clearLogs() {
        logs.removeAll()
    }

    public func cancel() {
        currentTask?.cancel()
        currentTask = nil
        if isRunning {
            log(.warning, "Execution cancelled by user.")
            isRunning = false
            activeProfileName = nil
        }
    }

    public func run(profile: WorkspaceProfile) {
        guard !isRunning else {
            log(.warning, "A profile is already running.")
            return
        }

        isRunning = true
        activeProfileName = profile.name
        log(.info, "Starting profile \"\(profile.name)\"...")

        currentTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isRunning = false
                self.activeProfileName = nil
                self.currentTask = nil
            }

            // 1. CLI Commands
            let enabledCommands = profile.commands.filter { $0.isEnabled && !$0.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if !enabledCommands.isEmpty {
                self.log(.info, "Running \(enabledCommands.count) CLI command(s)...")
                for cmd in enabledCommands {
                    if Task.isCancelled { return }
                    await self.executeCommand(cmd)
                }
            }

            // 2. Desktops & Apps
            var currentSpaceIndex = 1
            for desktop in profile.desktops {
                if Task.isCancelled { return }
                let enabledApps = desktop.apps.filter { $0.isEnabled }
                if enabledApps.isEmpty {
                    continue
                }

                self.log(.info, "Setting up desktop \"\(desktop.name)\"...")

                if desktop.spaceIndex > 0 {
                    do {
                        let directEnabled = WindowManager.isDirectDesktopShortcutEnabled(for: desktop.spaceIndex)
                        if directEnabled {
                            var changed = try await self.performSpaceSwitch {
                                try WindowManager.switchToDesktopSpace(desktop.spaceIndex)
                            }
                            if !changed && desktop.spaceIndex > currentSpaceIndex {
                                self.log(.info, "Desktop \(desktop.spaceIndex) not found — creating it in Mission Control...")
                                let created = await WindowManager.createNewDesktopSpace()
                                if created {
                                    self.log(.success, "Created new Desktop space.")
                                    try? await Task.sleep(nanoseconds: 500_000_000)
                                    changed = try await self.performSpaceSwitch {
                                        try WindowManager.switchToDesktopSpace(desktop.spaceIndex)
                                    }
                                } else {
                                    self.log(.warning, "Could not auto-create Desktop \(desktop.spaceIndex) via Mission Control.")
                                }
                            }
                            if changed {
                                self.log(.success, "Switched to Desktop \(desktop.spaceIndex) (Control+\(desktop.spaceIndex)).")
                            } else {
                                self.log(.info, "Staying on Desktop \(desktop.spaceIndex).")
                            }
                        } else {
                            let delta = desktop.spaceIndex - currentSpaceIndex
                            if delta != 0 {
                                let dirLabel = delta > 0 ? "Right" : "Left"
                                var movedCount = 0
                                for step in 0..<abs(delta) {
                                    var changed = try await self.performSpaceSwitch {
                                        try WindowManager.stepDesktopSpace(direction: delta)
                                    }
                                    if !changed && delta > 0 {
                                        // Target space doesn't exist yet — create one automatically, then step into it
                                        self.log(.info, "Desktop \(currentSpaceIndex + step + 1) not found — creating it in Mission Control...")
                                        let created = await WindowManager.createNewDesktopSpace()
                                        if created {
                                            self.log(.success, "Created new Desktop space.")
                                            try? await Task.sleep(nanoseconds: 500_000_000)
                                            changed = try await self.performSpaceSwitch {
                                                try WindowManager.stepDesktopSpace(direction: delta)
                                            }
                                        } else {
                                            self.log(.warning, "Could not auto-create Desktop \(currentSpaceIndex + step + 1) via Mission Control.")
                                        }
                                    }
                                    if changed { movedCount += 1 }
                                }
                                if movedCount == abs(delta) {
                                    self.log(.success, "Switched to Desktop \(desktop.spaceIndex) via Control+\(dirLabel) (×\(movedCount)).")
                                } else {
                                    self.log(.warning, "Moved \(movedCount)/\(abs(delta)) space(s) via Control+\(dirLabel).")
                                }
                            } else {
                                self.log(.info, "Using Desktop \(desktop.spaceIndex).")
                            }
                        }
                        currentSpaceIndex = desktop.spaceIndex
                    } catch {
                        self.log(.warning, "Desktop switch skipped: \(error.localizedDescription)")
                    }
                }

                let preferNewWindow = desktop.spaceIndex > 0
                for app in enabledApps {
                    if Task.isCancelled { return }
                    await self.launchAndPosition(app, preferNewWindowOnCurrentSpace: preferNewWindow)
                }
            }

            self.log(.success, "Finished profile \"\(profile.name)\".")
        }
    }

    public func testCommand(_ cmd: CLICommandItem) {
        Task { [weak self] in
            await self?.executeCommand(cmd)
        }
    }

    public func testApp(_ app: AppLaunchItem) {
        Task { [weak self] in
            await self?.launchAndPosition(app)
        }
    }

    private func executeCommand(_ item: CLICommandItem) async {
        if item.delaySeconds > 0 {
            try? await Task.sleep(nanoseconds: UInt64(item.delaySeconds * 1_000_000_000))
        }
        if Task.isCancelled { return }

        let expandedDir = (item.workingDirectory.isEmpty ? "~" : item.workingDirectory as NSString).expandingTildeInPath

        if item.runInTerminal {
            let escapedDir = expandedDir.replacingOccurrences(of: "\"", with: "\\\"")
            let escapedCmd = item.command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let fullCmd = "cd \\\"\(escapedDir)\\\" && \(escapedCmd)"
            let scriptSource = """
            tell application "Terminal"
                activate
                do script "\(fullCmd)"
            end tell
            """
            let success: Bool = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    var err: NSDictionary?
                    let script = NSAppleScript(source: scriptSource)
                    let res = script?.executeAndReturnError(&err)
                    continuation.resume(returning: res != nil && err == nil)
                }
            }
            if success {
                log(.success, "Opened \"\(item.name)\" in Terminal.")
            } else {
                log(.error, "Failed to open \"\(item.name)\" in Terminal (check Automation permissions).")
            }
            return
        }

        // Run in background via /bin/zsh -lc
        log(.info, "Running command \"\(item.name)\"...")
        let commandString = item.command
        let result: (Int32, String, String) = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-lc", commandString]
                if FileManager.default.fileExists(atPath: expandedDir) {
                    process.currentDirectoryURL = URL(fileURLWithPath: expandedDir)
                }

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let outStr = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(returning: (process.terminationStatus, outStr, errStr))
                } catch {
                    continuation.resume(returning: (-1, "", error.localizedDescription))
                }
            }
        }

        let (code, stdout, stderr) = result
        if code == 0 {
            let detail = stdout.isEmpty ? "" : " → \(stdout.prefix(160))"
            log(.success, "Command \"\(item.name)\" succeeded\(detail)")
        } else {
            let detail = stderr.isEmpty ? "exit code \(code)" : String(stderr.prefix(160))
            log(.error, "Command \"\(item.name)\" failed: \(detail)")
        }
    }

    private func launchAndPosition(_ item: AppLaunchItem, preferNewWindowOnCurrentSpace: Bool = false) async {
        guard let appURL = resolveAppURL(for: item) else {
            log(.error, "App not found: \(item.appName) (\(item.appPath))")
            return
        }

        let urlsToOpen = item.resolvedURLs
        if urlsToOpen.isEmpty {
            log(.info, "Opening \(item.appName)...")
        } else {
            log(.info, "Opening \(item.appName) with \(urlsToOpen.count) URL(s)...")
        }

        let existingApp = item.bundleIdentifier.isEmpty
            ? nil
            : NSRunningApplication.runningApplications(withBundleIdentifier: item.bundleIdentifier).first

        let runningApp: NSRunningApplication
        var openedNewWindowWithoutActivate = false
        if preferNewWindowOnCurrentSpace, existingApp != nil, item.isBrowser {
            if item.bundleIdentifier.lowercased() == "com.apple.safari" {
                let firstURL = urlsToOpen.first?.absoluteString ?? ""
                let script = firstURL.isEmpty
                    ? "tell application \"Safari\" to make new document"
                    : "tell application \"Safari\" to make new document with properties {URL:\"\(firstURL.replacingOccurrences(of: "\"", with: "\\\""))\"}"
                _ = await runAppleScript(script)
                openedNewWindowWithoutActivate = true
                runningApp = existingApp!
            } else {
                // Chromium-based (Chrome, Dia, Arc, Brave, Edge, Vivaldi, Opera) and Firefox support --new-window
                var args = ["-na", appURL.path, "--args", "--new-window"]
                args.append(contentsOf: urlsToOpen.map(\.absoluteString))
                _ = await runOpenCommand(args: args)
                openedNewWindowWithoutActivate = true
                runningApp = existingApp!
            }
        } else {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            config.createsNewApplicationInstance = false

            do {
                if urlsToOpen.isEmpty {
                    runningApp = try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
                } else {
                    runningApp = try await NSWorkspace.shared.open(urlsToOpen, withApplicationAt: appURL, configuration: config)
                }
            } catch {
                log(.error, "Failed to open \(item.appName): \(error.localizedDescription)")
                return
            }
        }

        if item.delaySeconds > 0 {
            try? await Task.sleep(nanoseconds: UInt64(item.delaySeconds * 1_000_000_000))
        }
        if Task.isCancelled { return }

        guard item.placement != .none else {
            log(.success, "Opened \(item.appName).")
            return
        }

        // Retry positioning briefly while the app finishes creating its first window.
        // Avoid calling runningApp.activate() when we opened a new window on a specific Space,
        // otherwise macOS may jump back to another Space that has an older window of the same app.
        var lastError: Error?
        for attempt in 1...6 {
            if Task.isCancelled { return }
            if !openedNewWindowWithoutActivate {
                runningApp.activate(options: [])
            }
            do {
                try WindowManager.positionWindow(
                    pid: runningApp.processIdentifier,
                    appName: item.appName,
                    placement: item.placement,
                    screenIndex: item.screenIndex
                )
                log(.success, "Placed \(item.appName) → \(item.placement.displayName).")
                return
            } catch WindowManagerError.accessibilityNotGranted {
                log(.warning, "Opened \(item.appName), but Accessibility permission is needed to move/resize windows.")
                return
            } catch {
                lastError = error
                if attempt < 6 {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
            }
        }

        log(.warning, "Opened \(item.appName), but could not place window: \(lastError?.localizedDescription ?? "Unknown error")")
    }

    /// Runs a space-switching action and observes NSWorkspace.activeSpaceDidChangeNotification
    /// to verify whether macOS actually switched Spaces.
    private func performSpaceSwitch(_ action: () throws -> Void) async throws -> Bool {
        var didChange = false
        let token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            didChange = true
        }
        defer {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }

        try action()
        // Wait up to 0.9s for macOS Space switch animation
        for _ in 0..<9 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if didChange {
                // Give macOS a moment to settle on the new Space
                try? await Task.sleep(nanoseconds: 350_000_000)
                return true
            }
        }
        return didChange
    }

    private func runAppleScript(_ source: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var err: NSDictionary?
                let script = NSAppleScript(source: source)
                let res = script?.executeAndReturnError(&err)
                continuation.resume(returning: res != nil && err == nil)
            }
        }
    }

    private func runOpenCommand(args: [String]) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                p.arguments = args
                do {
                    try p.run()
                    p.waitUntilExit()
                    continuation.resume(returning: p.terminationStatus == 0)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    private func resolveAppURL(for item: AppLaunchItem) -> URL? {
        if !item.appPath.isEmpty && FileManager.default.fileExists(atPath: item.appPath) {
            return URL(fileURLWithPath: item.appPath)
        }
        if !item.bundleIdentifier.isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.bundleIdentifier) {
            return url
        }
        return nil
    }

    private func log(_ level: ExecutionLogEntry.Level, _ message: String) {
        logs.append(ExecutionLogEntry(level: level, message: message))
        if logs.count > 200 {
            logs.removeFirst(logs.count - 200)
        }
    }
}

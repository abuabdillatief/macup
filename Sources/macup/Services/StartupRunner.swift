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
                if enabledApps.isEmpty && !desktop.createNewSpace {
                    continue
                }

                self.log(.info, "Setting up desktop \"\(desktop.name)\"...")

                if desktop.createNewSpace {
                    self.log(.info, "Attempting to add a new macOS Desktop via Mission Control...")
                    let created = await WindowManager.createNewDesktopSpace()
                    if created {
                        self.log(.success, "Created new Desktop space.")
                        try? await Task.sleep(nanoseconds: 700_000_000)
                    } else {
                        self.log(.warning, "Could not auto-create a new Desktop via Mission Control (ensure Accessibility & Automation are granted).")
                    }
                }

                if desktop.spaceIndex > 0 {
                    do {
                        if WindowManager.isDirectDesktopShortcutEnabled(for: desktop.spaceIndex) {
                            try WindowManager.switchToDesktopSpace(desktop.spaceIndex)
                            self.log(.info, "Switched to Desktop \(desktop.spaceIndex) (Control+\(desktop.spaceIndex)).")
                            try? await Task.sleep(nanoseconds: 700_000_000)
                        } else {
                            let delta = desktop.spaceIndex - currentSpaceIndex
                            if delta != 0 {
                                let dirLabel = delta > 0 ? "Right" : "Left"
                                self.log(.info, "Stepping to Desktop \(desktop.spaceIndex) via Control+\(dirLabel) (×\(abs(delta))).")
                                for _ in 0..<abs(delta) {
                                    try WindowManager.stepDesktopSpace(direction: delta)
                                    try? await Task.sleep(nanoseconds: 700_000_000)
                                }
                            } else {
                                // Still send Control+N in case user is currently on a different space
                                try WindowManager.switchToDesktopSpace(desktop.spaceIndex)
                                self.log(.info, "Targeting Desktop \(desktop.spaceIndex). Tip: enable 'Switch to Desktop \(desktop.spaceIndex)' in System Settings → Keyboard Shortcuts → Mission Control for direct jumps.")
                                try? await Task.sleep(nanoseconds: 500_000_000)
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
        if preferNewWindowOnCurrentSpace, existingApp != nil, item.isChromiumBasedBrowser {
            // Open a fresh window on the current Desktop Space instead of jumping back to an existing Space
            var args = ["-na", appURL.path, "--args", "--new-window"]
            args.append(contentsOf: urlsToOpen.map(\.absoluteString))
            let launched = await runOpenCommand(args: args)
            if !launched {
                log(.warning, "Fallback opening \(item.appName) normally...")
            }
            if let existing = existingApp {
                runningApp = existing
            } else {
                return
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

        // Retry positioning briefly while the app finishes creating its first window
        var lastError: Error?
        for attempt in 1...6 {
            if Task.isCancelled { return }
            runningApp.activate(options: [])
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

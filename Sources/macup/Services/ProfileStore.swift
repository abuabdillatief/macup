import Foundation

private struct PersistedData: Codable {
    var profiles: [WorkspaceProfile]
    var settings: AppSettings
}

@MainActor
@Observable
public final class ProfileStore {
    public var profiles: [WorkspaceProfile] = [] {
        didSet { save() }
    }
    public var settings: AppSettings = AppSettings() {
        didSet { save() }
    }

    private let storageURL: URL
    private var isLoading = false

    public init(storageURL: URL? = nil) {
        if let custom = storageURL {
            self.storageURL = custom
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let folder = appSupport.appendingPathComponent("macup", isDirectory: true)
            self.storageURL = folder.appendingPathComponent("profiles.json")
        }
        load()
    }

    public var defaultProfile: WorkspaceProfile? {
        profiles.first(where: { $0.isDefaultOnStartup }) ?? profiles.first
    }

    public func setDefaultProfile(_ id: UUID) {
        for idx in profiles.indices {
            profiles[idx].isDefaultOnStartup = (profiles[idx].id == id)
        }
    }

    public func addProfile(name: String = "New Profile", icon: String = "sparkles") -> WorkspaceProfile {
        let profile = WorkspaceProfile(
            name: name,
            icon: icon,
            isDefaultOnStartup: profiles.isEmpty,
            commands: [],
            desktops: [DesktopLayout(name: "Desktop 1", spaceIndex: 1, apps: [])]
        )
        profiles.append(profile)
        return profile
    }

    public func duplicateProfile(_ profile: WorkspaceProfile) -> WorkspaceProfile {
        var copy = profile
        copy.id = UUID()
        copy.name = "\(profile.name) Copy"
        copy.isDefaultOnStartup = false
        copy.commands = copy.commands.map { cmd in
            var c = cmd
            c.id = UUID()
            return c
        }
        copy.desktops = copy.desktops.map { desktop in
            var d = desktop
            d.id = UUID()
            d.apps = d.apps.map { app in
                var a = app
                a.id = UUID()
                return a
            }
            return d
        }
        profiles.append(copy)
        return copy
    }

    public func deleteProfile(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        if !profiles.isEmpty && !profiles.contains(where: { $0.isDefaultOnStartup }) {
            profiles[0].isDefaultOnStartup = true
        }
    }

    public func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(PersistedData(profiles: profiles, settings: settings))
    }

    public func importJSON(_ data: Data) throws {
        let decoded = try JSONDecoder().decode(PersistedData.self, from: data)
        isLoading = true
        self.profiles = decoded.profiles
        self.settings = decoded.settings
        isLoading = false
        save()
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }

        if let data = try? Data(contentsOf: storageURL),
           let decoded = try? JSONDecoder().decode(PersistedData.self, from: data),
           !decoded.profiles.isEmpty {
            self.profiles = decoded.profiles
            self.settings = decoded.settings
            return
        }

        // Seed starter profiles on first launch
        self.profiles = Self.starterProfiles()
        self.settings = AppSettings(runDefaultOnAppLaunch: false, startupDelaySeconds: 3.0)
        isLoading = false
        save()
    }

    private func save() {
        guard !isLoading else { return }
        do {
            let folder = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try exportJSON()
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("macup: failed to save profiles: \(error)")
        }
    }

    private static func starterProfiles() -> [WorkspaceProfile] {
        let work = WorkspaceProfile(
            name: "Work",
            icon: "laptopcomputer",
            isDefaultOnStartup: true,
            commands: [
                CLICommandItem(
                    name: "Print greeting",
                    command: "echo \"macup ready at $(date)\"",
                    workingDirectory: "~",
                    runInTerminal: false,
                    delaySeconds: 0,
                    isEnabled: true
                )
            ],
            desktops: [
                DesktopLayout(
                    name: "Main Workspace",
                    spaceIndex: 1,
                    apps: [
                        AppLaunchItem(
                            appName: "Safari",
                            bundleIdentifier: "com.apple.Safari",
                            appPath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app",
                            placement: .leftHalf,
                            screenIndex: 0,
                            delaySeconds: 1.0
                        ),
                        AppLaunchItem(
                            appName: "Terminal",
                            bundleIdentifier: "com.apple.Terminal",
                            appPath: "/System/Applications/Utilities/Terminal.app",
                            placement: .rightHalf,
                            screenIndex: 0,
                            delaySeconds: 0.8
                        )
                    ]
                ),
                DesktopLayout(
                    name: "Notes & Reference",
                    spaceIndex: 2,
                    apps: [
                        AppLaunchItem(
                            appName: "Notes",
                            bundleIdentifier: "com.apple.Notes",
                            appPath: "/System/Applications/Notes.app",
                            placement: .fullScreen,
                            screenIndex: 0,
                            delaySeconds: 1.0
                        )
                    ]
                )
            ]
        )

        let focus = WorkspaceProfile(
            name: "Focus",
            icon: "sparkles",
            isDefaultOnStartup: false,
            commands: [],
            desktops: [
                DesktopLayout(
                    name: "Current Desktop",
                    spaceIndex: 0,
                    apps: [
                        AppLaunchItem(
                            appName: "Notes",
                            bundleIdentifier: "com.apple.Notes",
                            appPath: "/System/Applications/Notes.app",
                            placement: .topLeft,
                            screenIndex: 0,
                            delaySeconds: 0.8
                        ),
                        AppLaunchItem(
                            appName: "Terminal",
                            bundleIdentifier: "com.apple.Terminal",
                            appPath: "/System/Applications/Utilities/Terminal.app",
                            placement: .bottomLeft,
                            screenIndex: 0,
                            delaySeconds: 0.8
                        )
                    ]
                )
            ]
        )

        return [work, focus]
    }
}

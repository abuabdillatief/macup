import Foundation
import CoreGraphics

public enum WindowPlacement: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case fullScreen
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case leftThird
    case centerThird
    case rightThird
    case leftTwoThirds
    case rightTwoThirds
    case center

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: return "Default (Don't Move)"
        case .fullScreen: return "Maximize"
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topHalf: return "Top Half"
        case .bottomHalf: return "Bottom Half"
        case .topLeft: return "Top-Left Corner"
        case .topRight: return "Top-Right Corner"
        case .bottomLeft: return "Bottom-Left Corner"
        case .bottomRight: return "Bottom-Right Corner"
        case .leftThird: return "Left Third"
        case .centerThird: return "Center Third"
        case .rightThird: return "Right Third"
        case .leftTwoThirds: return "Left Two-Thirds"
        case .rightTwoThirds: return "Right Two-Thirds"
        case .center: return "Centered"
        }
    }

    /// Normalized rect in top-left coordinate space (x, y, width, height in 0...1).
    /// Returns nil for `.none`.
    public var normalizedRect: CGRect? {
        switch self {
        case .none:
            return nil
        case .fullScreen:
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        case .leftHalf:
            return CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf:
            return CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topHalf:
            return CGRect(x: 0, y: 0, width: 1, height: 0.5)
        case .bottomHalf:
            return CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        case .topLeft:
            return CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRight:
            return CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .bottomLeft:
            return CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .bottomRight:
            return CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .leftThird:
            return CGRect(x: 0, y: 0, width: 1.0 / 3.0, height: 1)
        case .centerThird:
            return CGRect(x: 1.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1)
        case .rightThird:
            return CGRect(x: 2.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1)
        case .leftTwoThirds:
            return CGRect(x: 0, y: 0, width: 2.0 / 3.0, height: 1)
        case .rightTwoThirds:
            return CGRect(x: 1.0 / 3.0, y: 0, width: 2.0 / 3.0, height: 1)
        case .center:
            return CGRect(x: 0.15, y: 0.12, width: 0.70, height: 0.76)
        }
    }

    /// Calculates the target frame in Accessibility (top-left origin) coordinates given
    /// the screen's visible frame in top-left coordinates.
    public func targetFrame(in visibleTopLeftFrame: CGRect) -> CGRect? {
        guard let norm = normalizedRect else { return nil }
        return CGRect(
            x: visibleTopLeftFrame.origin.x + visibleTopLeftFrame.width * norm.origin.x,
            y: visibleTopLeftFrame.origin.y + visibleTopLeftFrame.height * norm.origin.y,
            width: visibleTopLeftFrame.width * norm.width,
            height: visibleTopLeftFrame.height * norm.height
        ).integral
    }
}

public struct CLICommandItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var command: String
    public var workingDirectory: String
    public var runInTerminal: Bool
    public var delaySeconds: Double
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String = "New Command",
        command: String = "",
        workingDirectory: String = "~",
        runInTerminal: Bool = false,
        delaySeconds: Double = 0,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.workingDirectory = workingDirectory
        self.runInTerminal = runInTerminal
        self.delaySeconds = delaySeconds
        self.isEnabled = isEnabled
    }
}

public struct AppLaunchItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var appName: String
    public var bundleIdentifier: String
    public var appPath: String
    public var placement: WindowPlacement
    public var screenIndex: Int
    public var delaySeconds: Double
    public var isEnabled: Bool
    public var urls: [String]

    public init(
        id: UUID = UUID(),
        appName: String,
        bundleIdentifier: String = "",
        appPath: String,
        placement: WindowPlacement = .none,
        screenIndex: Int = 0,
        delaySeconds: Double = 1.0,
        isEnabled: Bool = true,
        urls: [String] = []
    ) {
        self.id = id
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.appPath = appPath
        self.placement = placement
        self.screenIndex = screenIndex
        self.delaySeconds = delaySeconds
        self.isEnabled = isEnabled
        self.urls = urls
    }

    private enum CodingKeys: String, CodingKey {
        case id, appName, bundleIdentifier, appPath, placement, screenIndex, delaySeconds, isEnabled, urls
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        appName = try c.decode(String.self, forKey: .appName)
        bundleIdentifier = try c.decodeIfPresent(String.self, forKey: .bundleIdentifier) ?? ""
        appPath = try c.decode(String.self, forKey: .appPath)
        placement = try c.decodeIfPresent(WindowPlacement.self, forKey: .placement) ?? .none
        screenIndex = try c.decodeIfPresent(Int.self, forKey: .screenIndex) ?? 0
        delaySeconds = try c.decodeIfPresent(Double.self, forKey: .delaySeconds) ?? 1.0
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        urls = try c.decodeIfPresent([String].self, forKey: .urls) ?? []
    }

    public var isBrowser: Bool {
        let lowerId = bundleIdentifier.lowercased()
        let lowerName = appName.lowercased()
        let browserBundleKeywords = [
            "safari", "chrome", "chromium", "firefox", "brave",
            "edgemac", "arc", "dia", "browser", "vivaldi", "opera",
            "orion", "duckduckgo", "zen", "sigmaos", "torbrowser"
        ]
        if browserBundleKeywords.contains(where: { lowerId.contains($0) }) {
            return true
        }
        let browserNames = [
            "safari", "google chrome", "chrome", "firefox", "arc", "dia",
            "brave browser", "microsoft edge", "vivaldi", "opera",
            "orion", "zen", "zen browser", "duckduckgo", "chromium"
        ]
        return browserNames.contains(lowerName)
    }

    public var isChromiumBasedBrowser: Bool {
        let lowerId = bundleIdentifier.lowercased()
        let lowerName = appName.lowercased()
        let keywords = ["chrome", "chromium", "brave", "edgemac", "vivaldi", "opera", "dia", "arc"]
        return keywords.contains(where: { lowerId.contains($0) || lowerName.contains($0) })
    }

    /// Parses configured URL strings, prepending https:// when no scheme is provided.
    public var resolvedURLs: [URL] {
        urls.compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if trimmed.contains("://") {
                return URL(string: trimmed)
            }
            return URL(string: "https://\(trimmed)")
        }
    }
}

public struct DesktopLayout: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// 0 = Current Desktop (do not switch), 1...9 = macOS Desktop Space 1...9
    public var spaceIndex: Int
    /// Best-effort attempt to add a new Desktop via Mission Control before switching
    public var createNewSpace: Bool
    public var apps: [AppLaunchItem]

    public init(
        id: UUID = UUID(),
        name: String = "Desktop 1",
        spaceIndex: Int = 1,
        createNewSpace: Bool = false,
        apps: [AppLaunchItem] = []
    ) {
        self.id = id
        self.name = name
        self.spaceIndex = spaceIndex
        self.createNewSpace = createNewSpace
        self.apps = apps
    }
}

public struct WorkspaceProfile: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var icon: String
    public var isDefaultOnStartup: Bool
    public var commands: [CLICommandItem]
    public var desktops: [DesktopLayout]

    public init(
        id: UUID = UUID(),
        name: String,
        icon: String = "laptopcomputer",
        isDefaultOnStartup: Bool = false,
        commands: [CLICommandItem] = [],
        desktops: [DesktopLayout] = []
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.isDefaultOnStartup = isDefaultOnStartup
        self.commands = commands
        self.desktops = desktops
    }
}

public struct AppSettings: Codable, Hashable, Sendable {
    public var runDefaultOnAppLaunch: Bool
    public var startupDelaySeconds: Double

    public init(runDefaultOnAppLaunch: Bool = false, startupDelaySeconds: Double = 3.0) {
        self.runDefaultOnAppLaunch = runDefaultOnAppLaunch
        self.startupDelaySeconds = startupDelaySeconds
    }
}

public struct ExecutionLogEntry: Identifiable, Sendable {
    public enum Level: String, Sendable {
        case info
        case success
        case warning
        case error
    }

    public let id = UUID()
    public let timestamp: Date
    public let level: Level
    public let message: String

    public init(level: Level, message: String, timestamp: Date = Date()) {
        self.level = level
        self.message = message
        self.timestamp = timestamp
    }
}

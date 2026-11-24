import AppKit
import Foundation

public struct InstalledApp: Identifiable, Hashable {
    public var id: String { path }
    public let name: String
    public let bundleIdentifier: String
    public let path: String

    public var icon: NSImage {
        NSWorkspace.shared.icon(forFile: path)
    }
}

public enum AppDiscovery {
    public static func listInstalledApps() -> [InstalledApp] {
        let searchDirs = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            (NSHomeDirectory() as NSString).appendingPathComponent("Applications")
        ]

        let fm = FileManager.default
        var seenPaths = Set<String>()
        var results: [InstalledApp] = []

        for dir in searchDirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items where item.hasSuffix(".app") {
                let fullPath = (dir as NSString).appendingPathComponent(item)
                guard !seenPaths.contains(fullPath) else { continue }
                seenPaths.insert(fullPath)

                let url = URL(fileURLWithPath: fullPath)
                let bundle = Bundle(url: url)
                let displayName = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let bundleId = bundle?.bundleIdentifier ?? ""

                results.append(InstalledApp(name: displayName, bundleIdentifier: bundleId, path: fullPath))
            }
        }

        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

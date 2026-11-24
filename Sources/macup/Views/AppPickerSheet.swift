import AppKit
import SwiftUI

public struct AppPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var installedApps: [InstalledApp] = []
    @State private var selectedPlacement: WindowPlacement = .leftHalf

    public let onSelect: (AppLaunchItem) -> Void

    public init(onSelect: @escaping (AppLaunchItem) -> Void) {
        self.onSelect = onSelect
    }

    private var filteredApps: [InstalledApp] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return installedApps
        }
        return installedApps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }
    }

    public var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Add Application")
                    .font(.headline)
                Spacer()
                Button("Browse…") {
                    browseForApp()
                }
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search installed apps…", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))

            HStack {
                Text("Initial placement:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("", selection: $selectedPlacement) {
                    ForEach(WindowPlacement.allCases) { placement in
                        Text(placement.displayName).tag(placement)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 200)
                PlacementMiniIcon(placement: selectedPlacement, width: 28, height: 18)
                Spacer()
            }

            List(filteredApps) { app in
                Button {
                    let item = AppLaunchItem(
                        appName: app.name,
                        bundleIdentifier: app.bundleIdentifier,
                        appPath: app.path,
                        placement: selectedPlacement
                    )
                    onSelect(item)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Image(nsImage: app.icon)
                            .resizable()
                            .frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text(app.path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
            .frame(minHeight: 280)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 460, height: 480)
        .onAppear {
            installedApps = AppDiscovery.listInstalledApps()
        }
    }

    private func browseForApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        if panel.runModal() == .OK, let url = panel.url {
            let bundle = Bundle(url: url)
            let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            let bundleId = bundle?.bundleIdentifier ?? ""
            let item = AppLaunchItem(
                appName: name,
                bundleIdentifier: bundleId,
                appPath: url.path,
                placement: selectedPlacement
            )
            onSelect(item)
            dismiss()
        }
    }
}

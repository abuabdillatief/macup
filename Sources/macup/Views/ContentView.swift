import SwiftUI

@MainActor
public struct ContentView: View {
    @Bindable var store: ProfileStore
    let runner: StartupRunner
    let loginItemManager: LoginItemManager

    @State private var selectedProfileId: UUID?

    public var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selectedProfileId) {
                    Section("Profiles") {
                        ForEach(store.profiles) { profile in
                            HStack(spacing: 8) {
                                Image(systemName: profile.icon)
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 18)
                                Text(profile.name)
                                    .lineLimit(1)
                                Spacer()
                                if profile.isDefaultOnStartup {
                                    Image(systemName: "star.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                        .help("Default Startup Profile")
                                }
                            }
                            .tag(profile.id)
                            .contextMenu {
                                Button("Run Now") {
                                    runner.run(profile: profile)
                                }
                                Button("Set as Startup Default") {
                                    store.setDefaultProfile(profile.id)
                                }
                                Button("Duplicate") {
                                    let copy = store.duplicateProfile(profile)
                                    selectedProfileId = copy.id
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    store.deleteProfile(profile.id)
                                    if selectedProfileId == profile.id {
                                        selectedProfileId = store.profiles.first?.id
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)

                Divider()

                // Startup settings footer in sidebar
                VStack(alignment: .leading, spacing: 8) {
                    Text("Startup")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    Toggle("Launch at Login", isOn: Binding(
                        get: { loginItemManager.isEnabled },
                        set: { loginItemManager.setEnabled($0) }
                    ))
                    .font(.caption)
                    .disabled(!loginItemManager.isRunningAsAppBundle)
                    .help(loginItemManager.statusDescription)

                    Toggle("Auto-run default on launch", isOn: $store.settings.runDefaultOnAppLaunch)
                        .font(.caption)

                    if store.settings.runDefaultOnAppLaunch {
                        HStack(spacing: 4) {
                            Text("Delay:")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            TextField("3", value: $store.settings.startupDelaySeconds, format: .number)
                                .font(.caption2)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 40)
                            Text("sec")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        let created = store.addProfile()
                        selectedProfileId = created.id
                    } label: {
                        Label("New Profile", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let id = selectedProfileId ?? store.profiles.first?.id,
               let idx = store.profiles.firstIndex(where: { $0.id == id }) {
                ProfileDetailView(
                    profile: $store.profiles[idx],
                    isDefault: store.profiles[idx].isDefaultOnStartup,
                    onSetDefault: { store.setDefaultProfile(id) },
                    runner: runner
                )
            } else {
                ContentUnavailableView(
                    "No Profile Selected",
                    systemImage: "rectangle.3.group",
                    description: Text("Create a profile to configure your startup CLI commands, desktops, and window layouts.")
                )
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .onAppear {
            if selectedProfileId == nil {
                selectedProfileId = store.defaultProfile?.id ?? store.profiles.first?.id
            }
            loginItemManager.refresh()
        }
    }
}

import SwiftUI
import AppKit

/// The main window: a profiles sidebar + detail, a real titlebar toolbar, and the
/// composer / settings sheets. Lives in a proper SwiftUI `Window` scene, so the
/// toolbar and sheets behave natively.
struct RootView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: ProfileStore
    @State private var selection: UUID?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) { Divider(); footer }.background(.bar)
        }
        .sheet(isPresented: $model.showComposer) {
            LayoutComposerView().environmentObject(store).environmentObject(model)
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsSheet().environmentObject(store).environmentObject(model)
        }
        .sheet(isPresented: $model.showSpaces) { SpacesView() }
        .onAppear { model.refreshTrust() }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.showComposer = true } label: {
                Label("Create Layout", systemImage: "square.grid.2x2")
            }
            .help("Pick apps and choose how they're arranged, then save as a profile")

            Button { model.saveCurrentLayout() } label: {
                Label("Save Current Layout", systemImage: "plus.rectangle.on.rectangle")
            }
            .help("Capture the current window layout as a new profile")

            Button { model.showSettings = true } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            if !model.isTrusted {
                Section {
                    Button {
                        AccessibilityManager.triggerSystemPrompt()
                        AccessibilityManager.openSystemSettings()
                    } label: {
                        Label("Enable Accessibility", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                }
            }
            Section("Profiles") {
                ForEach(store.profiles) { profile in
                    profileRow(profile).tag(profile.id)
                }
            }
        }
        .overlay {
            if store.profiles.isEmpty {
                EmptyStateView(title: "No Profiles",
                               message: "Use “Create Layout” or “Save Current Layout” in the toolbar.")
            }
        }
        .navigationTitle("Stagehand")
        .frame(minWidth: 230)
    }

    private func profileRow(_ profile: LayoutProfile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(profile.name).font(.headline)
            Text("\(profile.apps.count) apps · \(profile.windowCount) windows")
                .font(.caption).foregroundStyle(.secondary)
        }
        .contextMenu {
            Button("Restore") { model.restore(profile) }
            Button("Rename…") { rename(profile) }
            Divider()
            Button("Delete", role: .destructive) { store.deleteProfile(id: profile.id) }
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let id = selection, let profile = store.profile(id: id) {
            ProfileDetailView(profile: profile, onRename: { rename(profile) })
        } else {
            EmptyStateView(title: "Select a Profile",
                           message: "Pick a profile on the left to see its captured windows.")
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if model.isRestoring {
                ProgressView().controlSize(.small)
                Text("Restoring…").font(.caption)
            } else if !model.lastWarnings.isEmpty {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                Text(model.lastWarnings.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                    .help(model.lastWarnings.joined(separator: "\n"))
            } else {
                Image(systemName: "externaldrive").foregroundStyle(.secondary)
                Text(store.storageURL.path)
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([store.storageURL])
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    // MARK: Rename

    private func rename(_ profile: LayoutProfile) {
        guard let newName = TextPrompt.ask(
            title: "Rename Profile",
            message: "Enter a new name for “\(profile.name)”.",
            defaultValue: profile.name) else { return }
        if !store.renameProfile(id: profile.id, to: newName) {
            TextPrompt.info(title: "Couldn't rename",
                            message: "That name is empty or already used by another profile.")
        }
    }
}

// MARK: - Detail view

private struct ProfileDetailView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: ProfileStore
    let profile: LayoutProfile
    var onRename: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(profile.name).font(.largeTitle.bold()).lineLimit(1)
                Spacer()
                Button("Restore") { model.restore(profile) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isRestoring)
                Button(action: onRename) { Image(systemName: "pencil") }.help("Rename")
                Button(role: .destructive) { store.deleteProfile(id: profile.id) } label: {
                    Image(systemName: "trash")
                }.help("Delete profile")
            }
            Text("Updated \(profile.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Toggle("Open at startup", isOn: Binding(
                    get: { profile.openAtStartup },
                    set: { store.setOpenAtStartup(id: profile.id, $0) }
                ))
                .toggleStyle(.checkbox)
                .help("Auto-restore this layout when Stagehand launches at login")

                Button {
                    model.nameCurrentSpace(after: profile)
                } label: {
                    Label("Name this Desktop", systemImage: "rectangle.on.rectangle")
                }
                .help("Name the current Mission Control desktop after this profile (experimental)")

                Spacer()
            }

            Divider()
            List {
                ForEach(profile.apps, id: \.bundleID) { app in
                    Section(app.name) {
                        ForEach(Array(app.windows.enumerated()), id: \.offset) { _, window in
                            WindowRow(window: window)
                        }
                    }
                }
            }
        }
        .padding()
    }
}

private struct WindowRow: View {
    let window: SavedWindow
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(window.title.isEmpty ? "Untitled window" : window.title)
                Text(String(format: "%.0f×%.0f at (%.0f, %.0f)",
                            window.frame.width, window.frame.height,
                            window.frame.x, window.frame.y))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer()
            if let space = window.spaceID {
                Label("Space \(space)", systemImage: "rectangle.on.rectangle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if window.minimized {
                Image(systemName: "minus.circle").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Empty state (ContentUnavailableView is macOS 14+)

private struct EmptyStateView: View {
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.system(size: 34)).foregroundStyle(.tertiary)
            Text(title).font(.title3.bold())
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

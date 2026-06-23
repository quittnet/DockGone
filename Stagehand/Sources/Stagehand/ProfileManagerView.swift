import SwiftUI

/// SwiftUI detail/management UI for profiles. The menu bar handles the common
/// quick actions (save / restore); this window is where you rename, delete and
/// inspect what a profile actually captured.
struct ProfileManagerView: View {
    @ObservedObject var store: ProfileStore
    /// Restore is owned by the AppDelegate (it tracks progress + warnings), so
    /// the view asks for it through a closure rather than calling the engine.
    var onRestore: (LayoutProfile) -> Void

    @State private var selection: UUID?
    @State private var renaming: UUID?
    @State private var renameText: String = ""

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(minWidth: 620, minHeight: 420)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(store.profiles) { profile in
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name).font(.headline)
                    Text("\(profile.apps.count) apps · \(profile.windowCount) windows")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(profile.id)
                .contextMenu {
                    Button("Restore") { onRestore(profile) }
                    Button("Rename") { beginRename(profile) }
                    Divider()
                    Button("Delete", role: .destructive) { store.deleteProfile(id: profile.id) }
                }
            }
        }
        .overlay {
            if store.profiles.isEmpty {
                ContentUnavailableCompat(
                    title: "No Profiles",
                    message: "Use “Save current layout…” in the menu bar to create one."
                )
            }
        }
        .navigationTitle("Profiles")
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let id = selection, let profile = store.profile(id: id) {
            ProfileDetailView(
                profile: profile,
                isRenaming: renaming == id,
                renameText: $renameText,
                onRestore: { onRestore(profile) },
                onCommitRename: {
                    store.renameProfile(id: id, to: renameText)
                    renaming = nil
                },
                onBeginRename: { beginRename(profile) },
                onDelete: { store.deleteProfile(id: id) }
            )
            .padding()
        } else {
            ContentUnavailableCompat(
                title: "Select a Profile",
                message: "Pick a profile on the left to see its captured windows."
            )
        }
    }

    private func beginRename(_ profile: LayoutProfile) {
        selection = profile.id
        renameText = profile.name
        renaming = profile.id
    }
}

// MARK: - Detail pane

private struct ProfileDetailView: View {
    let profile: LayoutProfile
    let isRenaming: Bool
    @Binding var renameText: String
    var onRestore: () -> Void
    var onCommitRename: () -> Void
    var onBeginRename: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if isRenaming {
                    TextField("Profile name", text: $renameText, onCommit: onCommitRename)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                    Button("Save", action: onCommitRename)
                } else {
                    Text(profile.name).font(.largeTitle.bold())
                    Button(action: onBeginRename) { Image(systemName: "pencil") }
                        .buttonStyle(.borderless)
                        .help("Rename")
                }
                Spacer()
                Button("Restore", action: onRestore)
                    .keyboardShortcut(.defaultAction)
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .help("Delete profile")
            }

            Text("Updated \(profile.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)

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
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let space = window.spaceID {
                Label("Space \(space)", systemImage: "rectangle.on.rectangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if window.minimized {
                Image(systemName: "minus.circle").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Back-deployable empty state
//
// ContentUnavailableView is macOS 14+, but we target 13, so this is a tiny
// stand-in with the same intent.
private struct ContentUnavailableCompat: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text(title).font(.title3.bold())
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

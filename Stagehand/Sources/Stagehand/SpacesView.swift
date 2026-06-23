import SwiftUI

/// Experimental Mission Control desktop (Space) naming UI. Honest about the fact
/// that this rides on private APIs and may not reflect in Mission Control without
/// a Dock relaunch.
struct SpacesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var spaces: [SpaceManager.Space] = []
    @State private var drafts: [UInt64: String] = [:]
    @State private var status: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 540, height: 460)
        .onAppear(perform: reload)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Name Desktops (Spaces)").font(.title2.bold())
            Text("Experimental — uses private macOS APIs. Names are set at the system "
                + "level; if Mission Control still shows the old label, use “Relaunch "
                + "Dock”. Apple may change or remove this at any time.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        if !SpaceManager.canEnumerate {
            unavailable("Spaces can't be read on this macOS — the private API is missing.")
        } else if spaces.isEmpty {
            unavailable("No Spaces were reported. Open Mission Control once, then press Refresh.")
        } else {
            List {
                if !SpaceManager.canRename {
                    Text("Read-only: the rename API isn't available on this macOS.")
                        .font(.caption).foregroundStyle(.orange)
                }
                ForEach(spaces) { space in row(space) }
            }
        }
    }

    private func row(_ space: SpaceManager.Space) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Desktop \(space.index)").font(.headline)
                Text(space.isCurrent ? "Current · \(space.display)" : space.display)
                    .font(.caption)
                    .foregroundStyle(space.isCurrent ? Color.accentColor : .secondary)
            }
            .frame(width: 160, alignment: .leading)

            TextField("Name", text: binding(for: space))
                .textFieldStyle(.roundedBorder)
                .disabled(!SpaceManager.canRename)
                .onSubmit { apply(space) }

            Button("Set") { apply(space) }
                .disabled(!SpaceManager.canRename)
        }
        .padding(.vertical, 2)
    }

    private func binding(for space: SpaceManager.Space) -> Binding<String> {
        Binding(
            get: { drafts[space.id] ?? space.name ?? "" },
            set: { drafts[space.id] = $0 }
        )
    }

    private func unavailable(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle).foregroundStyle(.secondary)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            if let status {
                Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Button("Relaunch Dock") {
                SpaceManager.relaunchDock()
                status = "Relaunched Dock — give Mission Control a moment, then Refresh."
            }
            .disabled(!SpaceManager.canEnumerate)
            Button("Refresh") { reload() }
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    private func reload() {
        spaces = SpaceManager.spaces()
        drafts = [:]
    }

    private func apply(_ space: SpaceManager.Space) {
        let name = (drafts[space.id] ?? space.name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = SpaceManager.setName(name, for: space.id)
        status = ok
            ? "Set Desktop \(space.index) to “\(name)”. If Mission Control still shows the old label, Relaunch Dock."
            : "Couldn't set Desktop \(space.index) — macOS didn't accept the name."
        reload()
    }
}

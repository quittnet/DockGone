import SwiftUI
import AppKit

/// "Create Layout" composer: pick apps (even ones that aren't running), choose a
/// screen region for each, preview the arrangement, and save it as a profile.
///
/// Each region is baked into an absolute frame on the chosen display at save
/// time, so a composed layout restores through exactly the same path as a
/// captured one — launching each app and placing its window.
struct LayoutComposerView: View {
    @EnvironmentObject var store: ProfileStore
    @Environment(\.dismiss) private var dismiss

    struct Assignment: Identifiable {
        let app: CatalogApp
        var region: WindowArranger.Action
        var id: String { app.id }
    }

    @State private var catalog: [CatalogApp] = []
    @State private var search = ""
    @State private var assignments: [Assignment] = []
    @State private var name = ""
    @State private var screenIndex = 0

    private var screens: [NSScreen] { NSScreen.screens }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                appPicker
                Divider()
                arrangementPane
            }
            Divider()
            footer
        }
        .frame(width: 780, height: 540)
        .onAppear { if catalog.isEmpty { catalog = AppCatalog.installedApps() } }
    }

    // MARK: Header / footer

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Create Layout").font(.title2.bold())
            Text("Choose apps and where each one goes, then save it as a profile.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            TextField("Layout name (e.g. Work)", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            if screens.count > 1 {
                Picker("Display", selection: $screenIndex) {
                    ForEach(Array(screens.enumerated()), id: \.offset) { item in
                        Text(displayLabel(item.offset, item.element)).tag(item.offset)
                    }
                }
                .frame(width: 220)
            }
            Spacer()
            Button("Cancel") { dismiss() }
            Button("Create") { create() }
                .keyboardShortcut(.defaultAction)
                .disabled(assignments.isEmpty || trimmedName.isEmpty)
        }
        .padding(12)
    }

    // MARK: App picker (left)

    private var filteredCatalog: [CatalogApp] {
        guard !search.isEmpty else { return catalog }
        return catalog.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var appPicker: some View {
        VStack(spacing: 0) {
            TextField("Search apps", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(8)
            List(filteredCatalog) { app in
                Button { toggle(app) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isSelected(app) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(isSelected(app) ? Color.accentColor : .secondary)
                        Image(nsImage: app.icon).resizable().frame(width: 18, height: 18)
                        Text(app.name).lineLimit(1)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 300)
    }

    // MARK: Arrangement (right): preview + per-app region

    private var arrangementPane: some View {
        VStack(spacing: 10) {
            preview
            HStack {
                Text(assignments.isEmpty ? "No apps selected"
                                         : "\(assignments.count) app\(assignments.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Auto-Tile") { autoTile() }
                    .disabled(assignments.isEmpty)
                    .help("Distribute the selected apps into halves / thirds / quarters")
            }
            if assignments.isEmpty {
                Spacer()
                Text("Pick apps on the left to add them here.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List {
                    ForEach($assignments) { $assignment in
                        HStack(spacing: 8) {
                            Image(nsImage: assignment.app.icon).resizable().frame(width: 18, height: 18)
                            Text(assignment.app.name).lineLimit(1)
                            Spacer()
                            Picker("", selection: $assignment.region) {
                                ForEach(WindowArranger.composableRegions, id: \.self) { region in
                                    Text(region.title).tag(region)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 150)
                            Button { remove(assignment.app) } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(minWidth: 440)
    }

    /// A schematic of the chosen display with each app's region drawn in place.
    private var preview: some View {
        GeometryReader { geo in
            let aspect: CGFloat = 1.6
            let screenW = min(geo.size.width, geo.size.height * aspect)
            let screenH = screenW / aspect
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.12))
                ForEach(assignments) { assignment in
                    let unit = WindowArranger.unitRect(for: assignment.region)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.22))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor.opacity(0.7)))
                        .overlay(
                            VStack(spacing: 2) {
                                Image(nsImage: assignment.app.icon).resizable().frame(width: 16, height: 16)
                                Text(assignment.app.name).font(.system(size: 9)).lineLimit(1)
                            }
                            .padding(2)
                        )
                        .frame(width: max(0, unit.width * screenW - 2),
                               height: max(0, unit.height * screenH - 2))
                        .offset(x: unit.minX * screenW + 1, y: unit.minY * screenH + 1)
                }
            }
            .frame(width: screenW, height: screenH)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 190)
    }

    // MARK: Mutations

    private func isSelected(_ app: CatalogApp) -> Bool {
        assignments.contains { $0.app.id == app.id }
    }

    private func toggle(_ app: CatalogApp) {
        if let index = assignments.firstIndex(where: { $0.app.id == app.id }) {
            assignments.remove(at: index)
        } else {
            assignments.append(Assignment(app: app, region: .maximize))
        }
    }

    private func remove(_ app: CatalogApp) {
        assignments.removeAll { $0.app.id == app.id }
    }

    /// Distribute the selected apps into a sensible tiling by count.
    private func autoTile() {
        let regions = tiling(count: assignments.count)
        for index in assignments.indices { assignments[index].region = regions[index] }
    }

    private func tiling(count: Int) -> [WindowArranger.Action] {
        switch count {
        case 1:  return [.maximize]
        case 2:  return [.leftHalf, .rightHalf]
        case 3:  return [.leftThird, .centerThird, .rightThird]
        case 4:  return [.topLeft, .topRight, .bottomLeft, .bottomRight]
        default:
            var regions: [WindowArranger.Action] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
            regions.append(contentsOf: Array(repeating: .maximize, count: max(0, count - 4)))
            return regions
        }
    }

    private func displayLabel(_ index: Int, _ screen: NSScreen) -> String {
        "Display \(index + 1) (\(Int(screen.frame.width))×\(Int(screen.frame.height)))"
    }

    private func create() {
        let screen = screens.indices.contains(screenIndex)
            ? screens[screenIndex]
            : (NSScreen.main ?? screens.first)
        guard let screen else { return }

        let savedApps: [SavedApp] = assignments.map { assignment in
            let frame = WindowArranger.frame(for: assignment.region, on: screen)
            let window = SavedWindow(title: "", frame: WindowFrame(frame),
                                     minimized: false, displayID: nil, spaceID: nil)
            return SavedApp(bundleID: assignment.app.id, name: assignment.app.name,
                            bundlePath: assignment.app.url.path, windows: [window])
        }
        store.saveProfile(named: trimmedName, apps: savedApps)
        dismiss()
    }
}

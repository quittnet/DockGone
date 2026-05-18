import Cocoa
import SwiftUI
import Carbon

// MARK: - Window controller

final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let host = NSHostingController(rootView: SettingsView())
        host.preferredContentSize = NSSize(width: 500, height: 540)
        let win = NSWindow(contentViewController: host)
        win.title = "DockGone Preferences"
        win.styleMask = [.titled, .closable]
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .visible
        win.setContentSize(NSSize(width: 500, height: 540))
        win.isReleasedWhenClosed = false
        super.init(window: win)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        if window?.isVisible != true { window?.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Tint presets

// Eight neutral translucent tints ordered light → dark. The full list of
// glass tints the app offers; there is no custom picker beyond these.
struct TintPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let color: NSColor
}

let tintPresets: [TintPreset] = [
    .init(id: "clear",     name: "Clear",     color: NSColor.black.withAlphaComponent(0.03)),
    .init(id: "mist",      name: "Mist",      color: NSColor.white.withAlphaComponent(0.12)),
    .init(id: "frost",     name: "Frost",     color: NSColor.white.withAlphaComponent(0.22)),
    .init(id: "slate",     name: "Slate",     color: NSColor(white: 0.5,  alpha: 0.20)),
    .init(id: "stone",     name: "Stone",     color: NSColor.black.withAlphaComponent(0.12)),
    .init(id: "charcoal",  name: "Charcoal",  color: NSColor.black.withAlphaComponent(0.24)),
    .init(id: "graphite",  name: "Graphite",  color: NSColor.black.withAlphaComponent(0.36)),
    .init(id: "onyx",      name: "Onyx",      color: NSColor.black.withAlphaComponent(0.50)),
]

// Loose colorspace-tolerant comparison so the selected preset highlights
// correctly even when SwiftUI <-> AppKit bridging drifts components by a
// few thousandths.
private func nsColorsApproxMatch(_ a: NSColor, _ b: NSColor) -> Bool {
    guard
        let aa = a.usingColorSpace(.sRGB),
        let bb = b.usingColorSpace(.sRGB)
    else { return false }
    return abs(aa.redComponent   - bb.redComponent)   < 0.01 &&
           abs(aa.greenComponent - bb.greenComponent) < 0.01 &&
           abs(aa.blueComponent  - bb.blueComponent)  < 0.01 &&
           abs(aa.alphaComponent - bb.alphaComponent) < 0.02
}

// MARK: - SwiftUI view + view model

@MainActor
final class SettingsViewModel: ObservableObject {
    private let s = Prefs.shared

    var iconSize: Double {
        get { Double(s.iconSize) }
        set { s.iconSize = CGFloat(newValue); objectWillChange.send() }
    }

    var tintColor: Color {
        get { Color(nsColor: s.tintColor) }
        set { s.tintColor = NSColor(newValue); objectWillChange.send() }
    }

    var position: Prefs.Position {
        get { s.position }
        set { s.position = newValue; objectWillChange.send() }
    }

    var labelMode: Prefs.LabelMode {
        get { s.labelMode }
        set { s.labelMode = newValue; objectWillChange.send() }
    }

    var includeTrash: Bool {
        get { s.includeTrash }
        set { s.includeTrash = newValue; objectWillChange.send() }
    }

    var hotkeyKey: UInt32 {
        get { s.hotkeyKeyCode }
        set { s.hotkeyKeyCode = newValue; objectWillChange.send() }
    }

    var hotkeyMods: UInt32 {
        get { s.hotkeyModifiers }
        set { s.hotkeyModifiers = newValue; objectWillChange.send() }
    }

    var suppressBouncing: Bool {
        get { s.suppressBouncing }
        set { s.suppressBouncing = newValue; objectWillChange.send() }
    }

    func reset() {
        s.resetToDefaults()
        objectWillChange.send()
    }
}

struct SettingsView: View {
    @StateObject private var model = SettingsViewModel()

    var body: some View {
        Form {
            Section("Appearance") {
                LabeledContent {
                    HStack(spacing: 10) {
                        Slider(
                            value: Binding(get: { model.iconSize },
                                           set: { model.iconSize = $0 }),
                            in: 48...128, step: 4
                        )
                        .frame(width: 180)
                        Text("\(Int(model.iconSize))pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 42, alignment: .trailing)
                    }
                } label: {
                    SettingsRowLabel(symbol: "photo.on.rectangle",
                                     tint: .blue,
                                     title: "Icon size")
                }

                LabeledContent {
                    HStack(spacing: 6) {
                        ForEach(tintPresets) { preset in
                            ColorSwatch(
                                fill: Color(nsColor: preset.color),
                                isSelected: nsColorsApproxMatch(
                                    NSColor(model.tintColor), preset.color
                                ),
                                action: {
                                    model.tintColor = Color(nsColor: preset.color)
                                }
                            )
                            .help(preset.name)
                        }
                    }
                } label: {
                    SettingsRowLabel(symbol: "paintpalette.fill",
                                     tint: .pink,
                                     title: "Glass tint")
                }

                Picker(selection: Binding(get: { model.position },
                                          set: { model.position = $0 })) {
                    ForEach(Prefs.Position.allCases) { p in
                        Text(p.label).tag(p)
                    }
                } label: {
                    SettingsRowLabel(symbol: "rectangle.center.inset.filled",
                                     tint: .indigo,
                                     title: "Panel position")
                }

                Picker(selection: Binding(get: { model.labelMode },
                                          set: { model.labelMode = $0 })) {
                    ForEach(Prefs.LabelMode.allCases) { m in
                        Text(m.label).tag(m)
                    }
                } label: {
                    SettingsRowLabel(symbol: "textformat",
                                     tint: .purple,
                                     title: "App labels")
                }
            }

            Section("Behavior") {
                LabeledContent {
                    HotkeyRecorder(
                        modifiers: Binding(get: { model.hotkeyMods },
                                           set: { model.hotkeyMods = $0 }),
                        keyCode:   Binding(get: { model.hotkeyKey },
                                           set: { model.hotkeyKey = $0 })
                    )
                    .frame(width: 180, height: 26)
                } label: {
                    SettingsRowLabel(symbol: "keyboard",
                                     tint: .gray,
                                     title: "Hotkey")
                }

                Toggle(isOn: Binding(get: { model.includeTrash },
                                     set: { model.includeTrash = $0 })) {
                    SettingsRowLabel(symbol: "trash",
                                     tint: .orange,
                                     title: "Include Trash")
                }

                Toggle(isOn: Binding(get: { model.suppressBouncing },
                                     set: { model.suppressBouncing = $0 })) {
                    SettingsRowLabel(symbol: "arrow.up.and.down.circle",
                                     tint: .red,
                                     title: "Suppress Dock bouncing")
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Reset to Defaults", role: .destructive) {
                        model.reset()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 500, height: 540)
    }
}

// Apple System Settings places a small colored rounded-square chip with an
// SF Symbol to the left of each row label. This re-creates that look.
private struct SettingsRowLabel: View {
    let symbol: String
    let tint: Color
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(
                    LinearGradient(
                        colors: [tint.opacity(0.95), tint],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text(title)
        }
    }
}

// MARK: - Tint swatch

private struct ColorSwatch: View {
    let fill: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // Light-to-dark diagonal backplate so the swatch's actual
                // translucency reads at a glance — Clear is mostly the
                // gradient showing through, Onyx mostly obscures it.
                LinearGradient(
                    colors: [
                        Color(nsColor: .white),
                        Color(nsColor: .black)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(Circle())
                .frame(width: 22, height: 22)
                Circle()
                    .fill(fill)
                    .frame(width: 22, height: 22)
                Circle()
                    .stroke(Color.primary.opacity(0.25), lineWidth: 0.5)
                    .frame(width: 22, height: 22)
                if isSelected {
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 2)
                        .frame(width: 26, height: 26)
                }
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Hotkey recorder

struct HotkeyRecorder: NSViewRepresentable {
    @Binding var modifiers: UInt32
    @Binding var keyCode: UInt32

    func makeNSView(context: Context) -> HotkeyRecorderView {
        let v = HotkeyRecorderView()
        v.modifiers = modifiers
        v.keyCode = keyCode
        v.onChange = { mods, key in
            modifiers = mods
            keyCode = key
        }
        return v
    }

    func updateNSView(_ nsView: HotkeyRecorderView, context: Context) {
        nsView.modifiers = modifiers
        nsView.keyCode = keyCode
        nsView.needsDisplay = true
    }
}

final class HotkeyRecorderView: NSView {
    var modifiers: UInt32 = 0
    var keyCode: UInt32 = 0
    var onChange: ((UInt32, UInt32) -> Void)?

    private var recording = false {
        didSet { needsDisplay = true }
    }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func becomeFirstResponder() -> Bool {
        recording = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        return super.resignFirstResponder()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        let nsMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbonMods: UInt32 = 0
        if nsMods.contains(.control) { carbonMods |= UInt32(controlKey) }
        if nsMods.contains(.option)  { carbonMods |= UInt32(optionKey) }
        if nsMods.contains(.shift)   { carbonMods |= UInt32(shiftKey) }
        if nsMods.contains(.command) { carbonMods |= UInt32(cmdKey) }

        guard carbonMods != 0 else {
            NSSound.beep()
            return
        }

        modifiers = carbonMods
        keyCode = UInt32(event.keyCode)
        onChange?(modifiers, keyCode)
        window?.makeFirstResponder(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius: CGFloat = 7
        let path = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)

        if recording {
            NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
        } else {
            NSColor.quaternaryLabelColor.withAlphaComponent(0.55).setFill()
        }
        path.fill()

        if recording {
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }

        let text = recording
            ? "Press a shortcut…"
            : HotkeyDisplay.string(modifiers: modifiers, keyCode: keyCode)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: recording
                ? NSColor.controlAccentColor
                : NSColor.labelColor
        ]
        let attr = NSAttributedString(string: text, attributes: attrs)
        let size = attr.size()
        attr.draw(at: NSPoint(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2
        ))
    }
}

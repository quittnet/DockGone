import AppKit
import Carbon.HIToolbox

/// System-wide hotkeys via Carbon's `RegisterEventHotKey`. An `.accessory` app
/// never becomes the key application, so AppKit/SwiftUI key handling and
/// `NSEvent` local monitors don't fire — Carbon hotkeys are the supported way to
/// get global shortcuts in this kind of menu-bar utility.
///
/// Defaults mirror Rectangle's Control+Option layout so the shortcuts feel
/// familiar to anyone coming from the popular window managers.
final class HotKeyManager {

    static let shared = HotKeyManager()
    private init() {}

    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1
    private let signature: OSType = 0x53544748   // 'STGH'

    // MARK: Public API

    /// (Re)register the window-arrange shortcuts, routing each to `perform`.
    func registerArrangeShortcuts(perform: @escaping (WindowArranger.Action) -> Void) {
        installHandlerIfNeeded()
        unregisterAll()
        for action in WindowArranger.Action.allCases {
            guard let shortcut = Shortcut.binding(for: action) else { continue }
            register(keyCode: shortcut.keyCode, modifiers: shortcut.carbonModifiers) {
                perform(action)
            }
        }
    }

    func unregisterAll() {
        for (_, ref) in hotKeyRefs { UnregisterEventHotKey(ref) }
        hotKeyRefs.removeAll()
        handlers.removeAll()
    }

    // MARK: Registration

    private func register(keyCode: Int, modifiers: UInt32, action: @escaping () -> Void) {
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(UInt32(keyCode), modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            hotKeyRefs[id] = ref
            handlers[id] = action
        }
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let userData, let event else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            if let handler = manager.handlers[hotKeyID.id] {
                DispatchQueue.main.async(execute: handler)
            }
            return noErr
        }, 1, &spec, context, &eventHandler)
    }
}

/// The default shortcut for each arrange action: a Carbon key code, Carbon
/// modifier mask, and a human label for the menu.
enum Shortcut {
    struct Binding {
        let keyCode: Int
        let carbonModifiers: UInt32
        let label: String
    }

    private static let controlOption = UInt32(controlKey | optionKey)
    private static let controlOptionCommand = UInt32(controlKey | optionKey | cmdKey)

    static func binding(for action: WindowArranger.Action) -> Binding? {
        switch action {
        case .leftHalf:       return Binding(keyCode: kVK_LeftArrow,  carbonModifiers: controlOption, label: "⌃⌥←")
        case .rightHalf:      return Binding(keyCode: kVK_RightArrow, carbonModifiers: controlOption, label: "⌃⌥→")
        case .topHalf:        return Binding(keyCode: kVK_UpArrow,    carbonModifiers: controlOption, label: "⌃⌥↑")
        case .bottomHalf:     return Binding(keyCode: kVK_DownArrow,  carbonModifiers: controlOption, label: "⌃⌥↓")
        case .topLeft:        return Binding(keyCode: kVK_ANSI_U,     carbonModifiers: controlOption, label: "⌃⌥U")
        case .topRight:       return Binding(keyCode: kVK_ANSI_I,     carbonModifiers: controlOption, label: "⌃⌥I")
        case .bottomLeft:     return Binding(keyCode: kVK_ANSI_J,     carbonModifiers: controlOption, label: "⌃⌥J")
        case .bottomRight:    return Binding(keyCode: kVK_ANSI_K,     carbonModifiers: controlOption, label: "⌃⌥K")
        case .leftThird:      return Binding(keyCode: kVK_ANSI_D,     carbonModifiers: controlOption, label: "⌃⌥D")
        case .centerThird:    return Binding(keyCode: kVK_ANSI_F,     carbonModifiers: controlOption, label: "⌃⌥F")
        case .rightThird:     return Binding(keyCode: kVK_ANSI_G,     carbonModifiers: controlOption, label: "⌃⌥G")
        case .leftTwoThirds:  return Binding(keyCode: kVK_ANSI_E,     carbonModifiers: controlOption, label: "⌃⌥E")
        case .rightTwoThirds: return Binding(keyCode: kVK_ANSI_T,     carbonModifiers: controlOption, label: "⌃⌥T")
        case .maximize:       return Binding(keyCode: kVK_Return,     carbonModifiers: controlOption, label: "⌃⌥↩")
        case .center:         return Binding(keyCode: kVK_ANSI_C,     carbonModifiers: controlOption, label: "⌃⌥C")
        case .nextDisplay:    return Binding(keyCode: kVK_RightArrow, carbonModifiers: controlOptionCommand, label: "⌃⌥⌘→")
        }
    }
}

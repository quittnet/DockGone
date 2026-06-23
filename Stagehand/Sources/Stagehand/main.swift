import AppKit

// `.regular` makes Stagehand a full Dock app with a main window; it ALSO keeps
// its menu-bar item (see AppDelegate). Set this here too so `swift run` (no
// bundle / Info.plist) behaves the same as the installed .app.
NSApplication.shared.setActivationPolicy(.regular)

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()

import AppKit

// `.accessory` keeps Stagehand out of the Dock and the ⌘-Tab switcher — it
// lives only in the menu bar. The bundle also sets LSUIElement (see Info.plist
// produced by install.sh); setting the policy here covers the `swift run` case
// where there is no bundle yet.
NSApplication.shared.setActivationPolicy(.accessory)

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()

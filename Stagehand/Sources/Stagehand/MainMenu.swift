import AppKit

/// Builds the standard menu bar for a regular (Dock) app. Because Stagehand is
/// assembled in code (no storyboard/SwiftUI `App`), it would otherwise launch
/// with an empty menu bar — and, worse, its text fields would have no
/// Cut/Copy/Paste/Select-All. This installs the conventional App / Edit / Window
/// menus. The menu-bar *status item* (the bar item) is separate; see AppDelegate.
enum MainMenu {

    static func install(appName: String) {
        let mainMenu = NSMenu()
        mainMenu.addItem(appMenu(appName: appName))
        mainMenu.addItem(editMenu())
        let windowItem = windowMenu()
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowItem.submenu   // enables the standard window list
    }

    private static func appMenu(appName: String) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu()
        item.submenu = menu

        menu.addItem(withTitle: "About \(appName)",
                     action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                     keyEquivalent: "")
        menu.addItem(.separator())

        menu.addItem(withTitle: "Hide \(appName)",
                     action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = menu.addItem(withTitle: "Hide Others",
                     action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(withTitle: "Show All",
                     action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())

        menu.addItem(withTitle: "Quit \(appName)",
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return item
    }

    private static func editMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Edit")
        item.submenu = menu

        // Responder-chain actions (string selectors avoid type-resolution noise).
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: Selector(("cut:")), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: Selector(("copy:")), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: Selector(("paste:")), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All", action: Selector(("selectAll:")), keyEquivalent: "a")
        return item
    }

    private static func windowMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Window")
        item.submenu = menu

        menu.addItem(withTitle: "Minimize",
                     action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom",
                     action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Bring All to Front",
                     action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        return item
    }
}

# Stagehand

A macOS menu-bar app that **saves and restores window layout profiles**. Arrange
your windows once, save the arrangement as a named profile ("Work", "Study",
"Deep Focus"), and restore it later with one click — Stagehand reopens the apps
that aren't running and moves every window back to where it was.

Menu-bar only: no Dock icon, no ⌘-Tab entry. Launches at login via `SMAppService`.

> Lives in the same repo as **DockGone** but is a separate, self-contained app
> (its own `Package.swift` under `Stagehand/`). DockGone is untouched.

## Features

- **Menu-bar dropdown** listing every saved profile; click one to restore it.
- **Save current layout…** captures all regular apps' standard windows — screen
  position, size, minimized state, the display each window is on, and (best
  effort) which Space it's on.
- **Profiles persisted as JSON** in `~/Library/Application Support/Stagehand/profiles.json`.
- **Restore** relaunches any saved apps that aren't running, waits for their
  windows, and repositions them to the saved coordinates.
- **Multiple named profiles** with a SwiftUI manager window (rename, delete,
  inspect captured windows).
- **Launch at login** via `SMAppService.mainApp` (macOS 13+) — toggle in the menu.
- **Graceful failures**: an app that's no longer installed (or opens no windows)
  is skipped, and a `⚠︎` summary of what was skipped appears at the bottom of the
  menu after a restore.

## Requirements

- macOS 13 (Ventura) or later.
- **Accessibility permission.** Reading and moving other apps' windows requires
  it. On first launch Stagehand explains why, then sends you to
  System Settings ▸ Privacy & Security ▸ Accessibility.

## Build & install

```bash
cd Stagehand
./install.sh
```

This builds a release binary, wraps it in `~/Applications/Stagehand.app`
(`LSUIElement`, ad-hoc signed for a stable identity), and launches it. Then grant
Accessibility access when prompted.

To run straight from source during development:

```bash
cd Stagehand
swift run
```

(You can also open the `Stagehand/` folder directly in Xcode — it's a Swift
package — and run the `Stagehand` scheme.)

## How it works

### Capture

For every `.regular` running app (the ones with a Dock presence), Stagehand asks
the Accessibility API for its windows, keeps the standard ones, and records each
window's frame, title and minimized state. The display is derived from
`CGDisplayBounds`; the Space, when available, from the private
`CGSCopySpacesForWindows` (the CGWindowID behind each AX element comes from the
private `_AXUIElementGetWindow`). Both private calls degrade gracefully — losing
them only drops the optional Space annotation.

### Restore

For each saved app Stagehand finds it running or launches it
(`NSWorkspace.openApplication`, resolved by bundle id with the captured path as a
fallback), polls up to ~10s for its windows to appear, matches saved windows to
live ones (standard windows only — exact title first, then positionally for the
rest), and applies the saved frame via the Accessibility API.

### Coordinates & Spaces

Frames are stored in the Accessibility global coordinate space (top-left origin),
exactly as read and written, so a restore lands windows precisely when the
display arrangement is unchanged. Space ids are captured and shown for reference
only — macOS has no supported API to move a window between Spaces, so restore
doesn't attempt it (windows are positioned on the current Space).

## File layout

```
Stagehand/
├── Package.swift
├── Resources/Info.plist                  LSUIElement bundle metadata
├── install.sh                            build → .app → sign → launch
└── Sources/Stagehand/
    ├── main.swift                        accessory entry point
    ├── AppDelegate.swift                 menu bar, save/restore wiring, prompts
    ├── Models.swift                      Codable profile / app / window model
    ├── AXBridge.swift                    Accessibility + private CGS/AX helpers
    ├── AccessibilityManager.swift        permission checks & explainer prompts
    ├── LayoutEngine.swift                capture + restore logic
    ├── ProfileStore.swift                JSON persistence (Application Support)
    ├── LoginItem.swift                   SMAppService launch-at-login
    ├── ProfileManagerView.swift          SwiftUI manager UI
    └── ProfileManagerWindowController.swift  hosts the SwiftUI window
```

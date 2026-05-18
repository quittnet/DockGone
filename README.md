# DockGone

A keyboard-driven app launcher for macOS that shows only the apps in your Dock that **aren't currently open**. Press a hotkey (⌥⇥ by default), pick an unopened app, release the modifier, and it launches.

The idea: shrink your Dock down to "apps I might want to launch later" and use one shortcut to reach any of them without taking your hands off the keyboard.

> ⚠️ **DockGone only launches apps that aren't already running.** It is **not** a replacement for the macOS app switcher. To move between apps that are *already open*, keep using **⌘⇥** (Command-Tab). That's macOS's built-in switcher, and DockGone doesn't try to replace it. The two are designed to complement each other: ⌘⇥ for "switch to a running app," ⌥⇥ for "launch one that isn't."

---

## How it works

DockGone runs as a menu-bar utility (no Dock icon of its own). When you press the hotkey, it:

1. Reads your Dock's `persistent-apps` list directly from `~/Library/Preferences/com.apple.dock.plist`.
2. Filters out any app that's already running (matched by bundle identifier).
3. Pops up a translucent "Liquid Glass" switcher with one tile per unopened app.

You then pick an app and launch it, or dismiss without launching.

### Switcher controls

| Action | Result |
|---|---|
| Tap hotkey | Open the switcher |
| Tap hotkey again | Cycle to the next app |
| Hold hotkey ≥ 0.35s | Auto-cycle forward (~5/sec) |
| Shift + hotkey key (while open) | Cycle backward |
| Arrow keys | Move selection in the grid |
| Mouse hover | Move selection |
| Click an icon | Launch and dismiss |
| Release the modifier | Launch the selected app |
| `Esc`, click outside, or pick the trailing **✕** tile | Dismiss without launching |

A quick tap-and-release pre-selects the first real app (not the ✕), so single-tap-to-launch always hits something useful.

### Panel layout

- **Single row** when it fits within ~92% of the screen width.
- **Wraps to a grid** otherwise. The last row is centered if it has a remainder.
- Each tile shows the icon + name; the selected tile gets a tinted ring.
- Panel can sit at the top, center, or bottom of the screen (preference).

---

## Attention tracker

The system Dock bounces an app's icon when it calls `requestUserAttention(_:)`. That's useful, except when the Dock is hidden and the bounce happens in empty space. DockGone replaces this with two surfaces and disables the bouncing animation system-wide.

### What you see

- **Red dot on the menu-bar icon** when one or more apps are requesting attention. Pulses briefly on appearance, then stays steady.
- **Attention rows** at the top of the menu bar menu, one per app, with its icon and "needs attention" label. Click to bring it forward.
- **Red glow ring** in the switcher around the icon of any app that's requesting attention. Attention-pending apps are sorted to the front of the list, so a quick ⌥⇥ lands on them first. Selecting one **activates the existing process** (revealing the save dialog or prompt) instead of launching a fresh instance.

### Disabling system Dock bouncing

When DockGone launches, it writes `com.apple.dock no-bouncing = true` and restarts the Dock so nothing bounces, including the visible Dock if you keep it shown. Toggle **Suppress Dock bouncing** off in Preferences to restore native bouncing.

### How attention is detected

DockGone uses the macOS Accessibility API to watch for **new windows appearing in inactive apps**, the heuristic that catches save dialogs, "are you sure?" prompts, IDE breakpoints, and similar attention-grabbers. There is no public API for `requestUserAttention` directly. The indicator clears when the app becomes active (any path), when the app terminates, or after a 5-minute backstop.

### Required permission

DockGone needs **Accessibility** permission to observe other apps' windows:

> **System Settings → Privacy & Security → Accessibility →** add `~/Applications/DockGone.app`

It also needs **Input Monitoring** (for the global hotkey). See Installation below.

---

## Menu bar features

The menu-bar icon (a dock rectangle) opens this menu:

- **Hide Dock**: toggles `autohide` with a 9999-second delay, so the Dock won't slide back in on hover. Toggle off to restore normal behaviour.
- **Add to Dock**: a grid picker listing every app in `/Applications` and `~/Applications` that isn't already in your Dock. Multi-select and click **Add to Dock** to append them.
- **Edit Dock** opens a grid view of your current Dock apps:
  - Drag tiles to reorder.
  - Click a tile to select; press `Delete` (or `⌫`) to remove the selection.
  - Click the per-tile **✕** badge for a single-app removal with a confirmation prompt.
  - Tiles jiggle gently while you're in edit mode.
- **Preferences…**: opens the settings window. You can also reopen Preferences by double-clicking the .app icon while DockGone is already running.
- **Launch at Login**: installs/uninstalls a per-user LaunchAgent at `~/Library/LaunchAgents/com.user.dockgone.plist` with `RunAtLoad` + `KeepAlive`.
- **Quit DockGone**

---

## Preferences

| Setting | Options | Default |
|---|---|---|
| **Icon size** | 48–128 pt slider | 64 pt |
| **Glass tint** | 8 neutral presets: Clear, Mist, Frost, Slate, Stone, Charcoal, Graphite, Onyx | ~10% black |
| **Panel position** | Top / Center / Bottom | Center |
| **App labels** | Selected only / Always / Never | Selected only |
| **Hotkey** | Any modifier(s) + key (recorded by clicking the field and pressing the combo) | ⌥⇥ |
| **Include Trash** | Adds a Trash tile (full/empty icon) at the end of the switcher | On |
| **Reset to Defaults** | Clears every preference | |

Settings persist in `UserDefaults`. Changing the hotkey re-registers it immediately, with no restart needed. The Add-to-Dock and Edit Dock panels share the switcher's glass tint, so the look stays consistent across windows.

---

## Installation

**Requires macOS 26+** (uses `NSGlassEffectView`).

```bash
git clone https://github.com/quittnet/DockGone.git
cd DockGone
./install.sh
```

The script:
1. Builds release (`swift build -c release`).
2. Creates `~/Applications/DockGone.app` (`LSUIElement=true`, so it's menu-bar only).
3. Writes the LaunchAgent and loads it via `launchctl`.

Because the build isn't codesigned, **macOS Gatekeeper will block the first launch.** Either right-click `DockGone.app` → **Open**, or go to **System Settings → Privacy & Security** and click **Open Anyway** after the first blocked attempt.

Then grant two permissions so the hotkey and attention tracker work:

> **System Settings → Privacy & Security → Input Monitoring →** add `~/Applications/DockGone.app`
>
> **System Settings → Privacy & Security → Accessibility →** add `~/Applications/DockGone.app`

DockGone also prompts for Accessibility automatically on first launch. Clicking through that prompt opens the right pane.

### Uninstall

```bash
launchctl unload ~/Library/LaunchAgents/com.user.dockgone.plist
rm ~/Library/LaunchAgents/com.user.dockgone.plist
pkill -x DockGone
rm -rf ~/Applications/DockGone.app
defaults delete com.user.dockgone                                   # saved preferences (optional)
defaults delete com.apple.dock no-bouncing 2>/dev/null && killall Dock   # restore icon bouncing
```

This leaves your Dock in whatever state it was in last. DockGone doesn't keep a backup, so any reorders/deletes you made through it stay. If you used **Hide Dock**, toggle it off before uninstalling (or run `defaults delete com.apple.dock autohide-delay && killall Dock`).

You may also want to remove DockGone from **Accessibility** and **Input Monitoring** in System Settings → Privacy & Security.

---

## How it talks to the Dock

DockGone reads and writes `~/Library/Preferences/com.apple.dock.plist` directly, then `killall Dock` to make the system pick up the new state.

- **Reorders** and **adds** preserve each entry's original plist payload (badges, display modes, etc.).
- **Deletes** are subtractive; the app itself stays installed.
- The "unopened" filter compares each Dock entry's bundle identifier against `NSWorkspace.shared.runningApplications`, so an app running from a different path than the Dock entry still counts as opened.

---

## Architecture notes

- **Hotkeys** are registered through Carbon (`RegisterEventHotKey`) so they fire system-wide regardless of which app is frontmost. `NSEvent` local monitors don't, since DockGone runs as `.accessory` and never becomes the key app on its own.
- **Hold-Tab cycling** is a 10 Hz poll timer that also watches for modifier release (which commits the launch). After a 0.35 s warm-up, it repeats every 0.22 s.
- **Liquid Glass** rendering uses `NSGlassEffectView` (macOS 26+), tinted from the user's preset. The same path is reused by Add-to-Dock and Edit Dock so all three windows match.
- **Launch at Login** uses a per-user LaunchAgent rather than `SMAppService`, since the latter requires a signed app bundle.

---

## File layout

```
Sources/DockGone/
├── main.swift              entrypoint, accessory app
├── AppDelegate.swift       menu bar, hotkeys, login item, Hide-Dock toggle
├── SwitcherPanel.swift     switcher panel + per-slot view
├── DockReader.swift        com.apple.dock.plist read / filter / write
├── Settings.swift          Prefs (UserDefaults) + hotkey display helpers
├── SettingsWindow.swift    SwiftUI preferences pane
├── DockManagePanel.swift   Edit-Dock grid (drag, reorder, delete)
└── AddAppPanel.swift       Add-to-Dock picker
install.sh                  build + bundle + launchctl
AppIcon.icns                app icon
Package.swift               SwiftPM target
```

import AppKit
import ApplicationServices

/// Moom/Magnet/Rectangle-style on-the-fly window snapping: move and resize the
/// frontmost window into a region of its screen (halves, quarters, thirds,
/// maximize, center) or fling it to the next display.
///
/// All math is done in the Accessibility global coordinate space (top-left
/// origin, +y down) so it composes with the rest of Stagehand. Screen rects from
/// AppKit are bottom-left origin, so they're flipped on the way in.
enum WindowArranger {

    enum Action: String, CaseIterable {
        case leftHalf, rightHalf, topHalf, bottomHalf
        case topLeft, topRight, bottomLeft, bottomRight
        case leftThird, centerThird, rightThird
        case leftTwoThirds, rightTwoThirds
        case maximize, center, nextDisplay

        var title: String {
            switch self {
            case .leftHalf:       return "Left Half"
            case .rightHalf:      return "Right Half"
            case .topHalf:        return "Top Half"
            case .bottomHalf:     return "Bottom Half"
            case .topLeft:        return "Top Left"
            case .topRight:       return "Top Right"
            case .bottomLeft:     return "Bottom Left"
            case .bottomRight:    return "Bottom Right"
            case .leftThird:      return "Left Third"
            case .centerThird:    return "Center Third"
            case .rightThird:     return "Right Third"
            case .leftTwoThirds:  return "Left Two Thirds"
            case .rightTwoThirds: return "Right Two Thirds"
            case .maximize:       return "Maximize"
            case .center:         return "Center"
            case .nextDisplay:    return "Move to Next Display"
            }
        }
    }

    /// Apply an arrange action to the frontmost app's focused window.
    static func apply(_ action: Action) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let window = AX.focusedWindow(of: appElement)
                ?? AX.windows(of: appElement).first(where: { AX.isStandardWindow($0) }),
              let current = AX.frame(of: window)
        else { return }

        let center = CGPoint(x: current.midX, y: current.midY)
        guard let screen = screen(containing: center) else { return }

        if action == .nextDisplay {
            applyNextDisplay(window: window, current: current, from: screen)
            return
        }

        let area = axRect(fromCocoa: screen.visibleFrame)
        AX.setFrame(window, target(for: action, in: area, current: current))
    }

    // MARK: Compose support

    /// Regions that fully define a frame from a screen alone — excludes `center`
    /// and `nextDisplay`, which need an existing window. Used by the composer.
    static let composableRegions: [Action] = [
        .leftHalf, .rightHalf, .topHalf, .bottomHalf,
        .topLeft, .topRight, .bottomLeft, .bottomRight,
        .leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds,
        .maximize,
    ]

    /// The AX frame a region maps to on a given screen. The composer uses this to
    /// bake a composed layout into absolute coordinates at creation time, so it
    /// then restores through the same path as a captured layout.
    static func frame(for action: Action, on screen: NSScreen) -> CGRect {
        let area = axRect(fromCocoa: screen.visibleFrame)
        return target(for: action, in: area, current: area)
    }

    /// A region as a unit rectangle in top-left [0,1] space, for drawing the
    /// composer's preview without referencing a real screen.
    static func unitRect(for action: Action) -> CGRect {
        switch action {
        case .leftHalf:       return CGRect(x: 0,     y: 0,   width: 0.5,     height: 1)
        case .rightHalf:      return CGRect(x: 0.5,   y: 0,   width: 0.5,     height: 1)
        case .topHalf:        return CGRect(x: 0,     y: 0,   width: 1,       height: 0.5)
        case .bottomHalf:     return CGRect(x: 0,     y: 0.5, width: 1,       height: 0.5)
        case .topLeft:        return CGRect(x: 0,     y: 0,   width: 0.5,     height: 0.5)
        case .topRight:       return CGRect(x: 0.5,   y: 0,   width: 0.5,     height: 0.5)
        case .bottomLeft:     return CGRect(x: 0,     y: 0.5, width: 0.5,     height: 0.5)
        case .bottomRight:    return CGRect(x: 0.5,   y: 0.5, width: 0.5,     height: 0.5)
        case .leftThird:      return CGRect(x: 0,     y: 0,   width: 1.0 / 3, height: 1)
        case .centerThird:    return CGRect(x: 1.0/3, y: 0,   width: 1.0 / 3, height: 1)
        case .rightThird:     return CGRect(x: 2.0/3, y: 0,   width: 1.0 / 3, height: 1)
        case .leftTwoThirds:  return CGRect(x: 0,     y: 0,   width: 2.0 / 3, height: 1)
        case .rightTwoThirds: return CGRect(x: 1.0/3, y: 0,   width: 2.0 / 3, height: 1)
        case .maximize:       return CGRect(x: 0,     y: 0,   width: 1,       height: 1)
        case .center:         return CGRect(x: 0.2,   y: 0.2, width: 0.6,     height: 0.6)
        case .nextDisplay:    return CGRect(x: 0,     y: 0,   width: 1,       height: 1)
        }
    }

    // MARK: Geometry

    /// Sub-rectangle of `area` (the screen's visible frame, in AX coordinates)
    /// for a given action. `current` is used only for `center`, which preserves
    /// the window's size.
    private static func target(for action: Action, in area: CGRect, current: CGRect) -> CGRect {
        let x = area.minX, y = area.minY, w = area.width, h = area.height
        switch action {
        case .leftHalf:       return CGRect(x: x,          y: y,          width: w / 2, height: h)
        case .rightHalf:      return CGRect(x: x + w / 2,  y: y,          width: w / 2, height: h)
        case .topHalf:        return CGRect(x: x,          y: y,          width: w,     height: h / 2)
        case .bottomHalf:     return CGRect(x: x,          y: y + h / 2,  width: w,     height: h / 2)
        case .topLeft:        return CGRect(x: x,          y: y,          width: w / 2, height: h / 2)
        case .topRight:       return CGRect(x: x + w / 2,  y: y,          width: w / 2, height: h / 2)
        case .bottomLeft:     return CGRect(x: x,          y: y + h / 2,  width: w / 2, height: h / 2)
        case .bottomRight:    return CGRect(x: x + w / 2,  y: y + h / 2,  width: w / 2, height: h / 2)
        case .leftThird:      return CGRect(x: x,              y: y, width: w / 3,     height: h)
        case .centerThird:    return CGRect(x: x + w / 3,      y: y, width: w / 3,     height: h)
        case .rightThird:     return CGRect(x: x + 2 * w / 3,  y: y, width: w / 3,     height: h)
        case .leftTwoThirds:  return CGRect(x: x,              y: y, width: 2 * w / 3, height: h)
        case .rightTwoThirds: return CGRect(x: x + w / 3,      y: y, width: 2 * w / 3, height: h)
        case .maximize:       return area
        case .center:
            let cw = min(current.width, w)
            let ch = min(current.height, h)
            return CGRect(x: x + (w - cw) / 2, y: y + (h - ch) / 2, width: cw, height: ch)
        case .nextDisplay:    return area   // handled separately in apply(_:)
        }
    }

    /// Move the window to the next screen (in `NSScreen.screens` order), keeping
    /// its position and size proportional to the new screen's visible frame so it
    /// lands in the same relative spot. No-op with a single display.
    private static func applyNextDisplay(window: AXUIElement, current: CGRect, from screen: NSScreen) {
        let screens = NSScreen.screens
        guard screens.count > 1,
              let index = screens.firstIndex(of: screen) else { return }
        let nextScreen = screens[(index + 1) % screens.count]

        let source = axRect(fromCocoa: screen.visibleFrame)
        let dest = axRect(fromCocoa: nextScreen.visibleFrame)

        // Map current's offset/size within the source visible frame onto the
        // destination, so a half-screen window stays a half-screen window.
        let fx = source.width  == 0 ? 0 : (current.minX - source.minX) / source.width
        let fy = source.height == 0 ? 0 : (current.minY - source.minY) / source.height
        let fw = source.width  == 0 ? 1 : current.width  / source.width
        let fh = source.height == 0 ? 1 : current.height / source.height

        AX.setFrame(window, CGRect(
            x: dest.minX + fx * dest.width,
            y: dest.minY + fy * dest.height,
            width:  min(fw, 1) * dest.width,
            height: min(fh, 1) * dest.height
        ))
    }

    // MARK: Coordinate conversion

    /// Height of the primary display (origin at (0,0) in AppKit's global space),
    /// used to flip between AppKit's bottom-left origin and AX's top-left origin.
    private static var primaryHeight: CGFloat {
        let primary = NSScreen.screens.first { $0.frame.origin == .zero }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        return primary?.frame.height ?? 0
    }

    /// Convert an AppKit rect (bottom-left origin) to an AX rect (top-left origin).
    private static func axRect(fromCocoa rect: CGRect) -> CGRect {
        CGRect(x: rect.minX,
               y: primaryHeight - rect.minY - rect.height,
               width: rect.width,
               height: rect.height)
    }

    /// The screen whose (AX-converted) full frame contains `axPoint`.
    private static func screen(containing axPoint: CGPoint) -> NSScreen? {
        NSScreen.screens.first { axRect(fromCocoa: $0.frame).contains(axPoint) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}

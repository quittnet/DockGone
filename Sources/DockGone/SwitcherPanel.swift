import Cocoa

// Screen containing the current mouse cursor — used to position panels on
// the display the user is actively looking at, instead of always falling
// back to NSScreen.main (which is the menu-bar/primary display).
extension NSScreen {
    static var screenWithMouse: NSScreen {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(loc) }
            ?? NSScreen.main
            ?? NSScreen.screens.first!
    }
}

// Static layout knobs. iconSize comes from Prefs (instance property);
// everything else is derived or kept constant.
private let kSlotPad:  CGFloat = 10
private let kLabelH:   CGFloat = 20
private let kLabelGap: CGFloat = 3
private let kRowGap:   CGFloat = 8
private let kSidePad:  CGFloat = 22
private let kVPad:     CGFloat = 8
private let kCorner:   CGFloat = 22

class SwitcherPanel: NSPanel {
    private let apps: [DockApp]
    // Start on the first non-close tile so a quick tap-and-release of the
    // hotkey lands on a useful app instead of the leading X. Falls back to
    // 0 if the apps list is somehow all-close (shouldn't happen in practice).
    private lazy var selectedIndex: Int =
        apps.firstIndex { $0.kind != .close } ?? 0
    private var slots: [SlotView] = []
    private var numCols = 1
    private var numRows = 1

    private let iconSize: CGFloat
    private let slotW: CGFloat
    private let slotH: CGFloat
    private let tintColor: NSColor
    private let position: Prefs.Position
    private let labelMode: Prefs.LabelMode

    var onDismiss: (() -> Void)?

    init(apps: [DockApp]) {
        self.apps = apps
        let p = Prefs.shared
        self.iconSize  = p.iconSize
        self.slotW     = p.iconSize + kSlotPad * 2
        self.slotH     = p.iconSize + kLabelGap + kLabelH
        self.tintColor = p.tintColor
        self.position  = p.position
        self.labelMode = p.labelMode

        let screen = NSScreen.screenWithMouse.frame

        // Single row if it fits within 92% of the screen width; otherwise wrap.
        let maxW = screen.width * 0.92
        let singleRowW = kSidePad * 2 + CGFloat(apps.count) * slotW

        let cols: Int
        let rows: Int
        if singleRowW <= maxW || apps.count == 1 {
            rows = 1
            cols = apps.count
        } else {
            let maxCols = max(1, Int((maxW - kSidePad * 2) / slotW))
            cols = maxCols
            rows = Int(ceil(Double(apps.count) / Double(maxCols)))
        }

        let w = kSidePad * 2 + CGFloat(cols) * slotW
        let h = kVPad * 2 + CGFloat(rows) * slotH + CGFloat(rows - 1) * kRowGap

        let originY: CGFloat
        switch position {
        case .top:
            originY = screen.maxY - h - screen.height * 0.10
        case .center:
            originY = screen.midY - h / 2 + screen.height * 0.05
        case .bottom:
            originY = screen.minY + screen.height * 0.12
        }
        let origin = NSPoint(x: screen.midX - w / 2, y: originY)

        super.init(
            contentRect: .init(origin: origin, size: .init(width: w, height: h)),
            styleMask:   [.borderless],
            backing:     .buffered,
            defer:       false
        )

        self.numCols = cols
        self.numRows = rows

        level                   = .floating
        isOpaque                = false
        backgroundColor         = .clear
        hasShadow               = false
        animationBehavior       = .utilityWindow
        collectionBehavior      = [.canJoinAllSpaces, .fullScreenAuxiliary]
        acceptsMouseMovedEvents = true

        buildUI()
    }

    private func buildUI() {
        let sz = contentRect(forFrameRect: frame).size
        let root = NSView(frame: .init(origin: .zero, size: sz))
        root.wantsLayer = true
        root.layer?.cornerRadius = kCorner
        root.layer?.masksToBounds = true

        let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: sz))
        glass.cornerRadius = kCorner
        glass.tintColor = tintColor

        let glassContent = NSView(frame: NSRect(origin: .zero, size: sz))
        glassContent.wantsLayer = true
        glassContent.layer?.cornerRadius = kCorner
        glassContent.layer?.masksToBounds = true
        glass.contentView = glassContent
        root.addSubview(glass)

        for (i, app) in apps.enumerated() {
            let col = i % numCols
            let row = i / numCols
            let remainder = apps.count % numCols
            let appsInRow = (row == numRows - 1 && remainder != 0) ? remainder : numCols
            let centerOffset = CGFloat(numCols - appsInRow) * slotW / 2
            let x = kSidePad + centerOffset + CGFloat(col) * slotW
            let rowFromBottom = numRows - 1 - row
            let y = kVPad + CGFloat(rowFromBottom) * (slotH + kRowGap)

            let slot = SlotView(
                frame:      .init(x: x, y: y, width: slotW, height: slotH),
                icon:       app.icon,
                name:       app.name,
                iconSize:   iconSize,
                slotPad:    kSlotPad,
                labelH:     kLabelH,
                labelGap:   kLabelGap,
                labelMode:  labelMode,
                ringColor:  ringColor(),
                needsAttention: app.attentionPID != nil
            )
            slot.onHover = { [weak self] in
                self?.selectedIndex = i
                self?.updateSelection()
            }
            slot.onLaunch = { [weak self] in
                self?.selectedIndex = i
                self?.launch()
            }
            glassContent.addSubview(slot)
            slots.append(slot)
        }

        contentView = root
        invalidateShadow()
        updateSelection()
    }

    // Derive a visible ring stroke from the user's tint when it's saturated;
    // fall back to a neutral white for low-saturation / nearly-black tints
    // so the ring still pops against the glass.
    private func ringColor() -> NSColor {
        let c = tintColor.usingColorSpace(.sRGB) ?? tintColor
        let saturation = c.saturationComponent
        if saturation > 0.15 {
            return c.withAlphaComponent(0.9)
        }
        return NSColor.white.withAlphaComponent(0.88)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            let loc = event.locationInWindow
            guard slots.contains(where: { $0.frame.contains(loc) }) else {
                dismiss(); return
            }
        }
        super.sendEvent(event)
    }

    // MARK: - Navigation

    func cycleNext() {
        selectedIndex = (selectedIndex + 1) % apps.count
        updateSelection()
    }

    func cyclePrev() {
        selectedIndex = (selectedIndex - 1 + apps.count) % apps.count
        updateSelection()
    }

    func moveLeft() {
        guard selectedIndex % numCols > 0 else { return }
        selectedIndex -= 1
        updateSelection()
    }

    func moveRight() {
        let col   = selectedIndex % numCols
        let row   = selectedIndex / numCols
        let inRow = min(numCols, apps.count - row * numCols)
        guard col < inRow - 1 else { return }
        selectedIndex += 1
        updateSelection()
    }

    func moveUp() {
        guard numRows > 1, selectedIndex / numCols > 0 else { return }
        selectedIndex -= numCols
        updateSelection()
    }

    func moveDown() {
        guard numRows > 1, selectedIndex / numCols < numRows - 1 else { return }
        selectedIndex = min(selectedIndex + numCols, apps.count - 1)
        updateSelection()
    }

    private func updateSelection() {
        slots.enumerated().forEach { i, s in s.isSelected = (i == selectedIndex) }
    }

    // MARK: - Launch

    func launchHovered() {
        let loc    = NSEvent.mouseLocation
        let origin = self.frame.origin
        let inWin  = NSPoint(x: loc.x - origin.x, y: loc.y - origin.y)
        var idx    = selectedIndex
        for (i, slot) in slots.enumerated() where slot.frame.contains(inWin) { idx = i; break }
        openTile(apps[idx])
        dismiss()
    }

    func launch() {
        openTile(apps[selectedIndex])
        dismiss()
    }

    private func openTile(_ app: DockApp) {
        switch app.kind {
        case .close:
            break  // intentional no-op; dismiss() runs in the caller
        case .folder:
            NSWorkspace.shared.open(app.url)
        case .app:
            // If this app is requesting attention, bring the existing process
            // forward (revealing the save dialog/prompt) rather than launching
            // a fresh instance.
            if let pid = app.attentionPID,
               let running = NSRunningApplication(processIdentifier: pid) {
                running.activate()
            } else {
                NSWorkspace.shared.openApplication(at: app.url, configuration: .init())
            }
        }
    }

    func dismiss() {
        orderOut(nil)
        onDismiss?()
    }

    func show() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Intentionally NOT calling updateHoverFromCurrentPosition here:
        // if the user's cursor happens to be sitting over a tile when the
        // panel appears, we'd silently override the keyboard-default first
        // app selection. Mouse hover still works via SlotView mouseEntered
        // once the user actually moves the cursor.
    }

    private func updateHoverFromCurrentPosition() {
        let loc    = NSEvent.mouseLocation
        let origin = self.frame.origin
        let inWin  = NSPoint(x: loc.x - origin.x, y: loc.y - origin.y)
        for (i, slot) in slots.enumerated() where slot.frame.contains(inWin) {
            selectedIndex = i
            updateSelection()
            return
        }
    }

    override var canBecomeKey: Bool { true }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - SlotView

class SlotView: NSView {
    var isSelected = false {
        didSet {
            // Always relayout the label width first so the fade-in lands on
            // the correct (full-name) frame.
            if isSelected { layoutFullNameLabel() }
            applyAppearance(animated: true)
            if isSelected {
                // Bring the slot to the front so any horizontally overflowing
                // label renders above its neighbours.
                superview?.addSubview(self, positioned: .above, relativeTo: nil)
            }
        }
    }
    var onHover:   (() -> Void)?
    var onLaunch:  (() -> Void)?

    private let nameLabel: NSTextField
    private let ringView   = NSView()
    private let attentionRing = NSView()
    private let iconSize:  CGFloat
    private let slotPad:   CGFloat
    private let labelH:    CGFloat
    private let labelGap:  CGFloat
    private let labelMode: Prefs.LabelMode
    private let ringColor: NSColor
    private let needsAttention: Bool

    init(frame: NSRect,
         icon: NSImage,
         name: String,
         iconSize: CGFloat,
         slotPad: CGFloat,
         labelH: CGFloat,
         labelGap: CGFloat,
         labelMode: Prefs.LabelMode,
         ringColor: NSColor,
         needsAttention: Bool) {
        self.iconSize  = iconSize
        self.slotPad   = slotPad
        self.labelH    = labelH
        self.labelGap  = labelGap
        self.labelMode = labelMode
        self.ringColor = ringColor
        self.needsAttention = needsAttention

        let iconY = labelH + labelGap
        let iconRect = NSRect(x: slotPad, y: iconY, width: iconSize, height: iconSize)

        nameLabel = NSTextField(labelWithString: name)
        super.init(frame: frame)
        wantsLayer = true

        // Attention ring — sits BEHIND the selection ring, slightly larger,
        // red, with an alpha that pulses 0.4 ↔ 1.0. Only added if this slot
        // belongs to an app currently requesting user attention.
        if needsAttention {
            let attnOutset: CGFloat = 6
            attentionRing.frame = NSRect(
                x: slotPad - attnOutset, y: iconY - attnOutset,
                width: iconSize + attnOutset * 2, height: iconSize + attnOutset * 2
            )
            attentionRing.wantsLayer = true
            attentionRing.layer?.cornerRadius = 17
            attentionRing.layer?.backgroundColor = NSColor.systemRed
                .withAlphaComponent(0.18).cgColor
            attentionRing.layer?.borderColor = NSColor.systemRed.cgColor
            attentionRing.layer?.borderWidth = 2.5
            attentionRing.alphaValue = 1.0
            addSubview(attentionRing)
            startAttentionPulse()
        }

        // Selection ring rendered as a layer-backed view so its alpha can
        // animate smoothly between cycles instead of snapping in/out via
        // draw(). Sits behind the icon and label.
        let outset: CGFloat = 3
        ringView.frame = NSRect(
            x: slotPad - outset, y: iconY - outset,
            width: iconSize + outset * 2, height: iconSize + outset * 2
        )
        ringView.wantsLayer = true
        ringView.layer?.cornerRadius = 14
        ringView.layer?.backgroundColor = ringColor.withAlphaComponent(0.16).cgColor
        ringView.layer?.borderColor = ringColor.cgColor
        ringView.layer?.borderWidth = 2.0
        ringView.alphaValue = 0
        addSubview(ringView)

        let imgView = NSImageView(frame: iconRect)
        imgView.image        = icon
        imgView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(imgView)

        nameLabel.alignment         = .center
        nameLabel.font              = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.textColor         = .labelColor
        nameLabel.isBezeled         = false
        nameLabel.drawsBackground   = false
        nameLabel.lineBreakMode     = .byClipping
        nameLabel.maximumNumberOfLines = 1
        nameLabel.cell?.usesSingleLineMode = true
        nameLabel.cell?.wraps       = false
        nameLabel.cell?.isScrollable = true
        nameLabel.alphaValue        = 0
        addSubview(nameLabel)

        if labelMode == .always { layoutFullNameLabel() }
        applyAppearance(animated: false)

        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        ))
    }

    // Smoothly cross-fades the selection ring and label between selected and
    // unselected states. With cycling running every ~0.22s, an 0.18s fade
    // gives each transition time to read without lagging the next cycle.
    private func applyAppearance(animated: Bool) {
        let ringAlpha: CGFloat = isSelected ? 1.0 : 0.0
        let labelAlpha: CGFloat
        switch labelMode {
        case .selectedOnly: labelAlpha = isSelected ? 1.0 : 0.0
        case .always:       labelAlpha = 1.0
        case .never:        labelAlpha = 0.0
        }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                ringView.animator().alphaValue  = ringAlpha
                nameLabel.animator().alphaValue = labelAlpha
            }
        } else {
            ringView.alphaValue  = ringAlpha
            nameLabel.alphaValue = labelAlpha
        }
    }

    private func layoutFullNameLabel() {
        nameLabel.sizeToFit()
        let w = ceil(nameLabel.frame.width)
        nameLabel.frame = NSRect(x: (bounds.width - w) / 2,
                                 y: 0,
                                 width: w,
                                 height: labelH)
    }

    private func startAttentionPulse() {
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 1.0
        anim.toValue   = 0.45
        anim.duration  = 0.6
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        attentionRing.layer?.add(anim, forKey: "attentionPulse")
    }

    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func mouseDown(with event: NSEvent)    { onLaunch?() }

    required init?(coder: NSCoder) { fatalError() }
}

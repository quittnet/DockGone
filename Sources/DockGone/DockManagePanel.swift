import Cocoa

// Same visual language as SwitcherPanel — kept independent so the constants
// can drift if the two panels' needs ever diverge.
private let kMIconSize: CGFloat = 96
private let kMSlotPad:  CGFloat = 14
private let kMLabelH:   CGFloat = 20
private let kMLabelGap: CGFloat = 4
private let kMSlotW:    CGFloat = kMIconSize + kMSlotPad * 2
private let kMSlotH:    CGFloat = kMIconSize + kMLabelGap + kMLabelH
private let kMRowGap:   CGFloat = 10
private let kMSidePad:  CGFloat = 24
private let kMTopPad:   CGFloat = 20    // space inside glass above icons — fits the delete badge with margin
private let kMBotPad:   CGFloat = 6
private let kMCorner:   CGFloat = 16
private let kMBadgeSize: CGFloat = 22

private let kDragThreshold: CGFloat = 4

class DockManagePanel: NSPanel {
    private var apps: [DockApp]
    private var selectedIndices: Set<Int> = []
    private var slots: [DockManageSlotView] = []
    private var numCols = 1
    private var numRows = 1
    private var statusLabel: NSTextField?

    // Drag state
    private var dragStartIndex: Int?
    private var dragStartLocation: NSPoint?
    private var dragGhost: NSImageView?
    private var dragActive = false
    private var dragTargetIndex: Int?

    var onDismiss: (() -> Void)?

    init(apps: [DockApp]) {
        self.apps = apps

        let screen = NSScreen.screenWithMouse.frame
        let (cols, rows) = Self.gridFor(count: apps.count, screen: screen)
        let (w, h) = Self.sizeFor(cols: cols, rows: rows)

        let origin = NSPoint(x: screen.midX - w / 2,
                             y: screen.midY - h / 2 + screen.height * 0.05)

        super.init(
            contentRect: .init(origin: origin, size: .init(width: w, height: h)),
            styleMask:   [.borderless],
            backing:     .buffered,
            defer:       false
        )

        numCols = cols
        numRows = rows

        level                   = .floating
        isOpaque                = false
        backgroundColor         = .clear
        hasShadow               = true
        animationBehavior       = .utilityWindow
        collectionBehavior      = [.canJoinAllSpaces, .fullScreenAuxiliary]
        acceptsMouseMovedEvents = true
        // We manage lifetime via a strong ref from AppDelegate; close() should
        // tear down the window without releasing the object.
        isReleasedWhenClosed    = false

        buildUI()
    }

    private static func gridFor(count: Int, screen: NSRect) -> (Int, Int) {
        let maxW       = screen.width * 0.92
        let singleRowW = kMSidePad * 2 + CGFloat(count) * kMSlotW
        if singleRowW <= maxW || count <= 1 {
            return (max(1, count), 1)
        }
        let maxCols = max(1, Int((maxW - kMSidePad * 2) / kMSlotW))
        let rows    = Int(ceil(Double(count) / Double(maxCols)))
        return (maxCols, rows)
    }

    private static func sizeFor(cols: Int, rows: Int) -> (CGFloat, CGFloat) {
        let w = kMSidePad * 2 + CGFloat(cols) * kMSlotW
        let h = kMTopPad + kMBotPad + CGFloat(rows) * kMSlotH
            + CGFloat(rows - 1) * kMRowGap + kMBotPad
        return (w, h)
    }

    // MARK: - UI

    private func buildUI() {
        let sz = contentRect(forFrameRect: frame).size
        let root = NSView(frame: .init(origin: .zero, size: sz))
        root.wantsLayer = true
        root.layer?.cornerRadius = kMCorner
        root.layer?.masksToBounds = true

        // Liquid Glass background, tinted by the user's Prefs selection so
        // this window matches whatever they chose in Preferences (same path
        // the switcher uses).
        let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: sz))
        glass.cornerRadius = kMCorner
        glass.tintColor = Prefs.shared.tintColor
        root.addSubview(glass)

        layoutSlots(in: root)
        addCloseButton(to: root)

        contentView = root
    }

    private func addCloseButton(to root: NSView) {
        let size: CGFloat  = 18
        let inset: CGFloat = 8
        let btn = NSButton(frame: NSRect(
            x: root.bounds.width - size - inset,
            y: root.bounds.height - size - inset,
            width: size, height: size
        ))
        btn.isBordered = false
        btn.bezelStyle = .regularSquare
        btn.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .regular))
        btn.contentTintColor = NSColor.labelColor.withAlphaComponent(0.45)
        btn.target = self
        btn.action = #selector(closeButtonTapped)
        // Brighten on hover so it's discoverable without being heavy.
        let area = NSTrackingArea(rect: btn.bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self,
                                  userInfo: ["closeBtn": btn])
        btn.addTrackingArea(area)
        root.addSubview(btn)
    }

    override func mouseEntered(with event: NSEvent) {
        if let btn = event.trackingArea?.userInfo?["closeBtn"] as? NSButton {
            btn.contentTintColor = .labelColor
        }
    }
    override func mouseExited(with event: NSEvent) {
        if let btn = event.trackingArea?.userInfo?["closeBtn"] as? NSButton {
            btn.contentTintColor = NSColor.labelColor.withAlphaComponent(0.45)
        }
    }

    private func layoutSlots(in root: NSView) {
        for s in slots { s.removeFromSuperview() }
        slots.removeAll()

        for (i, app) in apps.enumerated() {
            let frame = frameForSlot(index: i, panelWidth: root.bounds.width)
            let slot = DockManageSlotView(frame: frame, icon: app.icon, name: app.name)
            slot.onMouseDown    = { [weak self] loc in self?.slotMouseDown(at: i, location: loc) }
            slot.onMouseDragged = { [weak self] loc in self?.slotMouseDragged(at: i, location: loc) }
            slot.onMouseUp      = { [weak self] loc in self?.slotMouseUp(at: i, location: loc) }
            slot.onHover        = { [weak self] hovered in
                self?.refreshStatus(hoveredIndex: hovered ? i : nil)
            }
            slot.onDelete = { [weak self, weak slot] in
                guard let self, let slot,
                      let idx = self.slots.firstIndex(where: { $0 === slot }) else { return }
                self.confirmSingleDelete(at: idx)
            }
            slot.isSelected = selectedIndices.contains(i)
            root.addSubview(slot)
            slots.append(slot)
        }

        refreshStatus(hoveredIndex: nil)
    }

    private func frameForSlot(index i: Int, panelWidth: CGFloat) -> NSRect {
        let col = i % numCols
        let row = i / numCols
        let remainder = apps.count % numCols
        let appsInRow = (row == numRows - 1 && remainder != 0) ? remainder : numCols
        let centerOffset = CGFloat(numCols - appsInRow) * kMSlotW / 2
        let x = kMSidePad + centerOffset + CGFloat(col) * kMSlotW
        let rowFromBottom = numRows - 1 - row
        let y = kMBotPad + CGFloat(rowFromBottom) * (kMSlotH + kMRowGap)
        return NSRect(x: x, y: y, width: kMSlotW, height: kMSlotH)
    }

    private func refreshStatus(hoveredIndex: Int?) {
        let n = selectedIndices.count
        if n > 0 {
            setLabel("\(n) selected — Delete to remove",
                     color: NSColor.systemRed.withAlphaComponent(0.95))
        } else if let h = hoveredIndex, apps.indices.contains(h) {
            setLabel(apps[h].name, color: .labelColor)
        } else {
            setLabel("Drag to reorder • Click to select • Delete to remove",
                     color: .secondaryLabelColor)
        }
        for (i, s) in slots.enumerated() {
            s.isSelected = selectedIndices.contains(i)
        }
    }

    private func setLabel(_ text: String, color: NSColor) {
        // The label lives outside the icon strip — in the bottom band of the
        // glass (below the icons). Created lazily so we don't show a stale
        // placeholder if there are zero apps.
        if statusLabel == nil, let root = contentView {
            let lbl = NSTextField(labelWithString: "")
            lbl.frame = NSRect(x: 12, y: 4,
                               width: root.bounds.width - 24, height: kMLabelH)
            lbl.alignment = .center
            lbl.font = .systemFont(ofSize: 12, weight: .medium)
            lbl.isBezeled = false
            lbl.drawsBackground = false
            lbl.lineBreakMode = .byTruncatingTail
            lbl.maximumNumberOfLines = 1
            root.addSubview(lbl)
            statusLabel = lbl
        }
        statusLabel?.stringValue = text
        statusLabel?.textColor   = color
    }

    // MARK: - Mouse handling (forwarded from slots)

    private func slotMouseDown(at index: Int, location: NSPoint) {
        dragStartIndex = index
        dragStartLocation = location
        dragActive = false
    }

    private func slotMouseDragged(at index: Int, location: NSPoint) {
        guard let startIdx = dragStartIndex, let startLoc = dragStartLocation else { return }
        if !dragActive {
            let dx = location.x - startLoc.x
            let dy = location.y - startLoc.y
            if dx*dx + dy*dy < kDragThreshold * kDragThreshold { return }
            beginDrag(from: startIdx, atWindowLoc: location)
            dragActive = true
        }
        dragGhost?.setFrameOrigin(NSPoint(
            x: location.x - kMSlotW / 2 + kMSlotPad,
            y: location.y - kMIconSize / 2
        ))
        let newTarget = computeTargetIndex(for: location)
        if newTarget != dragTargetIndex {
            dragTargetIndex = newTarget
            animateSlotsForDrag(target: newTarget)
        }
    }

    private func slotMouseUp(at index: Int, location: NSPoint) {
        let wasDragging = dragActive
        let from = dragStartIndex
        let to   = dragTargetIndex
        let ghost = dragGhost
        dragStartIndex = nil
        dragStartLocation = nil
        dragActive = false
        dragTargetIndex = nil
        dragGhost = nil

        if wasDragging, let from = from {
            commitDragMove(from: from, to: to ?? from, ghost: ghost)
        } else {
            // No drag — treat as a select toggle.
            if selectedIndices.contains(index) {
                selectedIndices.remove(index)
            } else {
                selectedIndices.insert(index)
            }
            refreshStatus(hoveredIndex: index)
        }
    }

    private func commitDragMove(from: Int, to: Int, ghost: NSImageView?) {
        guard let root = contentView, apps.indices.contains(from) else {
            ghost?.removeFromSuperview()
            if from < slots.count { slots[from].alphaValue = 1 }
            return
        }
        let insertAt = min(to, apps.count - 1)

        if insertAt != from {
            let moved     = apps.remove(at: from)
            apps.insert(moved, at: insertAt)
            let movedSlot = slots.remove(at: from)
            slots.insert(movedSlot, at: insertAt)
            selectedIndices = remapSelectionAfterMove(from: from, to: insertAt, in: selectedIndices)
        }

        // Snap dragged slot from ghost position, then animate everything home.
        let droppedSlot = slots[insertAt]
        if let ghost {
            droppedSlot.frame = NSRect(
                x: ghost.frame.minX - kMSlotPad,
                y: ghost.frame.minY - (kMLabelH + kMLabelGap),
                width: kMSlotW, height: kMSlotH
            )
        }
        droppedSlot.alphaValue = 1
        ghost?.removeFromSuperview()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.20
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            for (i, slot) in slots.enumerated() {
                slot.animator().frame = frameForSlot(index: i, panelWidth: root.bounds.width)
            }
        }

        refreshStatus(hoveredIndex: insertAt)

        if insertAt != from { persistOrder() }
    }

    private func beginDrag(from index: Int, atWindowLoc loc: NSPoint) {
        guard apps.indices.contains(index) else { return }
        let ghost = NSImageView(frame: NSRect(
            x: loc.x - kMIconSize / 2,
            y: loc.y - kMIconSize / 2,
            width: kMIconSize, height: kMIconSize
        ))
        ghost.image = apps[index].icon
        ghost.imageScaling = .scaleProportionallyUpOrDown
        ghost.alphaValue = 0.92
        contentView?.addSubview(ghost)
        dragGhost = ghost
        // Hide the source slot entirely — the ghost stands in for it visually.
        slots[index].alphaValue = 0
        dragTargetIndex = index
    }

    // Pick the would-be slot position whose center is nearest the cursor.
    // This is the drop-target index in the resulting [0, apps.count) layout.
    private func computeTargetIndex(for windowLoc: NSPoint) -> Int {
        guard let root = contentView, !apps.isEmpty else { return 0 }
        var bestIdx = 0
        var bestDist = CGFloat.greatestFiniteMagnitude
        for target in 0..<apps.count {
            let f = frameForSlot(index: target, panelWidth: root.bounds.width)
            let dx = f.midX - windowLoc.x
            let dy = f.midY - windowLoc.y
            let d2 = dx*dx + dy*dy
            if d2 < bestDist { bestDist = d2; bestIdx = target }
        }
        return bestIdx
    }

    // Animate non-dragged slots into the positions they would occupy if the
    // dragged item were inserted at `target`. The dragged slot itself is
    // hidden — the ghost following the cursor stands in for it.
    private func animateSlotsForDrag(target: Int) {
        guard let dragFrom = dragStartIndex,
              let root = contentView else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            for (i, slot) in slots.enumerated() {
                if i == dragFrom { continue }
                let midIdx     = (i < dragFrom) ? i : (i - 1)
                let virtualIdx = (midIdx >= target) ? midIdx + 1 : midIdx
                slot.animator().frame = frameForSlot(index: virtualIdx, panelWidth: root.bounds.width)
            }
        }
    }

    private func remapSelectionAfterMove(from: Int, to: Int, in selection: Set<Int>) -> Set<Int> {
        var out = Set<Int>()
        for idx in selection {
            if idx == from {
                out.insert(to)
            } else if from < to {
                // Items in (from, to] shift left by 1.
                if idx > from && idx <= to { out.insert(idx - 1) }
                else { out.insert(idx) }
            } else {
                // from > to: items in [to, from) shift right by 1.
                if idx >= to && idx < from { out.insert(idx + 1) }
                else { out.insert(idx) }
            }
        }
        return out
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51, 117:   // Delete (backspace), Forward delete
            commitDelete()
        case 53:        // Escape
            dismiss()
        default:
            super.keyDown(with: event)
        }
    }

    override var canBecomeKey: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // MARK: - Persistence

    private func commitDelete() {
        guard !selectedIndices.isEmpty else { return }
        let kept = apps.enumerated()
            .filter { !selectedIndices.contains($0.offset) }
            .map { $0.element }
        apps = kept
        selectedIndices.removeAll()
        resizeAndRebuildAfterCountChange()
    }

    private func confirmSingleDelete(at index: Int) {
        guard apps.indices.contains(index) else { return }
        let app = apps[index]
        let alert = NSAlert()
        alert.messageText = "Remove “\(app.name)” from the Dock?"
        alert.informativeText = "The app stays installed — it just leaves the Dock."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        // runModal instead of beginSheetModal — borderless panels don't
        // render sheets reliably, so the sheet path was silently failing.
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn,
              apps.indices.contains(index) else { return }
        apps.remove(at: index)
        selectedIndices = Set(selectedIndices.compactMap { sel in
            sel == index ? nil : (sel > index ? sel - 1 : sel)
        })
        resizeAndRebuildAfterCountChange()
    }

    private func resizeAndRebuildAfterCountChange() {
        // Resize uses the panel's current screen (not the mouse's) so deleting
        // an app doesn't make the panel hop to a different display.
        let currentScreen = self.screen?.frame ?? NSScreen.screenWithMouse.frame
        let (cols, rows) = Self.gridFor(count: apps.count, screen: currentScreen)
        numCols = cols
        numRows = rows
        let (w, h) = Self.sizeFor(cols: cols, rows: rows)
        var f = frame
        f.origin.x += (f.size.width - w) / 2
        f.origin.y += (f.size.height - h) / 2
        f.size = .init(width: w, height: h)
        setFrame(f, display: true, animate: true)
        buildUI()
        persistOrder()
        if apps.isEmpty { dismiss() }
    }

    private func relayoutAndPersist() {
        if let root = contentView { layoutSlots(in: root) }
        persistOrder()
    }

    private func persistOrder() {
        DockReader.saveDockApps(apps)
    }

    // MARK: - Dismiss

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            let loc = event.locationInWindow

            // 1) The X badge overhangs the slot frame, so hitTest can't reach
            //    its upper half. Check badge regions in panel coords first.
            for (i, slot) in slots.enumerated() {
                let badgeInPanel = NSRect(
                    x: slot.frame.minX + kMSlotPad - kMBadgeSize / 2 + 6,
                    y: slot.frame.minY + (kMLabelH + kMLabelGap) + kMIconSize - kMBadgeSize / 2,
                    width: kMBadgeSize, height: kMBadgeSize
                )
                if badgeInPanel.contains(loc) {
                    confirmSingleDelete(at: i)
                    return
                }
            }

            // 2) Normal hit test for slot bodies and other controls.
            var v: NSView? = contentView?.hitTest(loc)
            while let view = v {
                if view is DockManageSlotView {
                    super.sendEvent(event)
                    return
                }
                v = view.superview
            }

            // 3) Anywhere else dismisses.
            dismiss()
            return
        }
        super.sendEvent(event)
    }

    private var didDismiss = false

    func dismiss() {
        guard !didDismiss else { return }
        didDismiss = true
        // Stop layer animations so the jiggle isn't lingering anywhere.
        for s in slots { s.layer?.removeAllAnimations() }
        // Hide instantly, then close. orderOut takes it off-screen in this
        // runloop tick; close() tears down the window-server resources.
        alphaValue = 0
        orderOut(nil)
        close()
        onDismiss?()
    }

    @objc private func closeButtonTapped() { dismiss() }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Slot

class DockManageSlotView: NSView {
    var isSelected = false {
        didSet {
            nameLabel.isHidden = !isSelected
            needsDisplay = true
        }
    }
    var onHover:        ((Bool) -> Void)?
    var onMouseDown:    ((NSPoint) -> Void)?
    var onMouseDragged: ((NSPoint) -> Void)?
    var onMouseUp:      ((NSPoint) -> Void)?
    var onDelete:       (() -> Void)?

    private let nameLabel:    NSTextField
    private let deleteButton: NSButton

    init(frame: NSRect, icon: NSImage, name: String) {
        let iconY = kMLabelH + kMLabelGap
        let iconRect  = NSRect(x: kMSlotPad, y: iconY, width: kMIconSize, height: kMIconSize)
        let labelRect = NSRect(x: 4, y: 0, width: frame.width - 8, height: kMLabelH)
        // Badge sits centered on the icon's top-left corner; it overflows the
        // slot bounds upward, hence kMTopPad in the panel and masksToBounds=false here.
        let badgeRect = NSRect(
            x: kMSlotPad - kMBadgeSize / 2 + 6,
            y: iconY + kMIconSize - kMBadgeSize / 2,
            width: kMBadgeSize, height: kMBadgeSize
        )

        nameLabel    = NSTextField(labelWithString: name)
        deleteButton = NSButton(frame: badgeRect)
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false

        let imgView = NSImageView(frame: iconRect)
        imgView.image        = icon
        imgView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(imgView)

        nameLabel.frame                    = labelRect
        nameLabel.alignment                = .center
        nameLabel.font                     = .systemFont(ofSize: 12, weight: .medium)
        nameLabel.textColor                = .labelColor
        nameLabel.isBezeled                = false
        nameLabel.drawsBackground          = false
        nameLabel.lineBreakMode            = .byTruncatingTail
        nameLabel.maximumNumberOfLines     = 1
        nameLabel.cell?.usesSingleLineMode = true
        nameLabel.isHidden                 = true
        addSubview(nameLabel)

        deleteButton.bezelStyle = .circular
        deleteButton.isBordered = false
        deleteButton.wantsLayer = true
        deleteButton.layer?.backgroundColor = NSColor.white.cgColor
        deleteButton.layer?.cornerRadius    = kMBadgeSize / 2
        deleteButton.layer?.borderWidth     = 0
        deleteButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Remove from Dock")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .bold))
        deleteButton.contentTintColor = NSColor.black.withAlphaComponent(0.78)
        deleteButton.target = self
        deleteButton.action = #selector(deleteTapped)
        addSubview(deleteButton)

        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        ))

        startJiggle()
    }

    @objc private func deleteTapped() { onDelete?() }

    private func startJiggle() {
        let rot = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        let amp = 0.009  // ~0.5° — subtle
        rot.values   = [-amp, amp, -amp]
        rot.keyTimes = [0, 0.5, 1]
        rot.duration = 0.26 + Double.random(in: -0.02...0.02)  // slightly slower too
        rot.repeatCount = .infinity
        rot.timeOffset = Double.random(in: 0...rot.duration)  // per-slot phase offset
        layer?.add(rot, forKey: "jiggle")
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent)  { onHover?(false) }
    override func mouseDown(with event: NSEvent)    { onMouseDown?(event.locationInWindow) }
    override func mouseDragged(with event: NSEvent) { onMouseDragged?(event.locationInWindow) }
    override func mouseUp(with event: NSEvent)      { onMouseUp?(event.locationInWindow) }

    override func draw(_ dirtyRect: NSRect) {
        guard isSelected else { return }
        let iconY = kMLabelH + kMLabelGap
        let outset: CGFloat = 3
        let r = NSRect(x: kMSlotPad - outset, y: iconY - outset,
                       width: kMIconSize + outset * 2, height: kMIconSize + outset * 2)
        // Red tint + ring for delete-selection mode.
        NSColor.systemRed.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: r, xRadius: 14, yRadius: 14).fill()
        NSColor.systemRed.withAlphaComponent(0.95).setStroke()
        let ring = NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 13, yRadius: 13)
        ring.lineWidth = 2.0
        ring.stroke()
    }

    required init?(coder: NSCoder) { fatalError() }
}

import Cocoa

// Shared with SwitcherPanel visual language
private let kAddCorner:   CGFloat = 20
private let kAddIconSize: CGFloat = 68
private let kAddSlotPad:  CGFloat = 14
private let kAddSlotW:    CGFloat = kAddIconSize + kAddSlotPad * 2   // 96
private let kAddNameH:    CGFloat = 18
private let kAddSlotH:    CGFloat = kAddIconSize + kAddSlotPad + kAddNameH + 8  // 108
private let kAddSidePad:  CGFloat = 20
private let kAddHeaderH:  CGFloat = 44
private let kAddFooterH:  CGFloat = 52

class AddAppPanel: NSPanel {
    private let allApps: [DockApp]
    private var selectedIndices = Set<Int>()
    private var slots: [AddSlotView] = []
    private var countLabel: NSTextField!
    private var addButton: NSButton!

    var onConfirm: (([DockApp]) -> Void)?

    init(apps: [DockApp]) {
        allApps = apps
        let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let w: CGFloat = 720
        let h: CGFloat = 560
        super.init(
            contentRect: CGRect(x: screen.midX - w / 2, y: screen.midY - h / 2, width: w, height: h),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        buildUI()
    }

    private func buildUI() {
        let sz = frame.size
        let root = NSView(frame: CGRect(origin: .zero, size: sz))
        root.wantsLayer = true
        root.layer?.cornerRadius = kAddCorner
        root.layer?.masksToBounds = true

        // Liquid Glass background — same NSGlassEffectView path the switcher
        // uses, tinted by the user's Prefs selection so this window matches
        // whatever they picked in Preferences.
        let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: sz))
        glass.cornerRadius = kAddCorner
        glass.tintColor = Prefs.shared.tintColor
        root.addSubview(glass)

        // Header
        root.addSubview(buildHeader(width: sz.width, height: sz.height))

        // Footer
        root.addSubview(buildFooter(width: sz.width))

        // Scroll body
        let bodyY  = kAddFooterH
        let bodyH  = sz.height - kAddFooterH - kAddHeaderH
        let scroll = NSScrollView(frame: CGRect(x: 0, y: bodyY, width: sz.width, height: bodyH))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground     = false
        scroll.borderType          = .noBorder

        let docView = buildGrid(width: sz.width, bodyH: bodyH)
        scroll.documentView = docView
        // Start scrolled to top (AppKit origin is bottom-left)
        if docView.frame.height > bodyH {
            docView.scroll(CGPoint(x: 0, y: docView.frame.height - bodyH))
        }
        root.addSubview(scroll)

        // Top divider (below header)
        let topDiv = NSBox(frame: CGRect(x: 0, y: sz.height - kAddHeaderH, width: sz.width, height: 0.5))
        topDiv.boxType   = .separator
        topDiv.fillColor = .separatorColor
        root.addSubview(topDiv)

        contentView = root
    }

    private func buildHeader(width: CGFloat, height: CGFloat) -> NSView {
        let view = NSView(frame: CGRect(x: 0, y: height - kAddHeaderH, width: width, height: kAddHeaderH))

        let title = NSTextField(labelWithString: "Add to Dock")
        title.frame       = CGRect(x: 40, y: (kAddHeaderH - 20) / 2, width: width - 80, height: 20)
        title.alignment   = .center
        title.font        = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor   = .labelColor
        view.addSubview(title)

        // Close button
        let closeBtn = NSButton(frame: CGRect(x: 12, y: (kAddHeaderH - 22) / 2, width: 22, height: 22))
        closeBtn.bezelStyle  = .circular
        closeBtn.isBordered  = false
        closeBtn.wantsLayer  = true
        closeBtn.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
        closeBtn.layer?.cornerRadius    = 11
        closeBtn.image = NSImage(systemSymbolName: "xmark",
                                  accessibilityDescription: "Close")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
        closeBtn.contentTintColor = .labelColor
        closeBtn.target = self
        closeBtn.action = #selector(closePanel)
        view.addSubview(closeBtn)

        return view
    }

    private func buildFooter(width: CGFloat) -> NSView {
        let view = NSView(frame: CGRect(x: 0, y: 0, width: width, height: kAddFooterH))

        let div = NSBox(frame: CGRect(x: 0, y: kAddFooterH - 0.5, width: width, height: 0.5))
        div.boxType   = .separator
        div.fillColor = .separatorColor
        view.addSubview(div)

        countLabel = NSTextField(labelWithString: "Select apps to add")
        countLabel.frame     = CGRect(x: 20, y: (kAddFooterH - 16) / 2, width: 240, height: 16)
        countLabel.textColor = .secondaryLabelColor
        countLabel.font      = .systemFont(ofSize: 12)
        view.addSubview(countLabel)

        addButton = NSButton(title: "Add to Dock", target: self, action: #selector(confirmSelected))
        addButton.bezelStyle = .rounded
        addButton.controlSize = .regular
        addButton.isEnabled  = false
        let bw: CGFloat = 120
        addButton.frame = CGRect(x: width - bw - 16, y: (kAddFooterH - 28) / 2, width: bw, height: 28)
        view.addSubview(addButton)

        return view
    }

    private func buildGrid(width: CGFloat, bodyH: CGFloat) -> NSView {
        if allApps.isEmpty {
            let dv = NSView(frame: CGRect(x: 0, y: 0, width: width, height: bodyH))
            let lbl = NSTextField(labelWithString: "All your apps are already in the Dock")
            lbl.frame       = CGRect(x: 0, y: bodyH / 2 - 10, width: width, height: 20)
            lbl.alignment   = .center
            lbl.textColor   = .secondaryLabelColor
            lbl.font        = .systemFont(ofSize: 13)
            dv.addSubview(lbl)
            return dv
        }

        let avail   = width - kAddSidePad * 2
        let numCols = max(1, Int(avail / kAddSlotW))
        let numRows = Int(ceil(Double(allApps.count) / Double(numCols)))
        let topPad: CGFloat = 12
        let contentH = max(bodyH, CGFloat(numRows) * kAddSlotH + topPad * 2)
        let dv = NSView(frame: CGRect(x: 0, y: 0, width: width, height: contentH))

        // Center the grid
        let gridW   = CGFloat(numCols) * kAddSlotW
        let leftPad = (width - gridW) / 2

        for (i, app) in allApps.enumerated() {
            let col = i % numCols
            let row = i / numCols
            let x   = leftPad + CGFloat(col) * kAddSlotW
            let rowFromBottom = numRows - 1 - row
            let y   = topPad + CGFloat(rowFromBottom) * kAddSlotH

            let slot = AddSlotView(
                frame: CGRect(x: x, y: y, width: kAddSlotW, height: kAddSlotH),
                app: app
            )
            slot.onToggle = { [weak self] isOn in
                guard let self else { return }
                if isOn { self.selectedIndices.insert(i) } else { self.selectedIndices.remove(i) }
                self.updateFooter()
            }
            dv.addSubview(slot)
            slots.append(slot)
        }

        return dv
    }

    private func updateFooter() {
        let n = selectedIndices.count
        switch n {
        case 0:
            countLabel.stringValue = "Select apps to add"
            countLabel.textColor   = .secondaryLabelColor
            addButton.isEnabled    = false
        case 1:
            countLabel.stringValue = "1 app selected"
            countLabel.textColor   = .labelColor
            addButton.isEnabled    = true
        default:
            countLabel.stringValue = "\(n) apps selected"
            countLabel.textColor   = .labelColor
            addButton.isEnabled    = true
        }
    }

    @objc private func confirmSelected() {
        let apps = selectedIndices.sorted().map { allApps[$0] }
        onConfirm?(apps)
        close()
    }

    @objc private func closePanel() {
        close()
    }

    override var canBecomeKey: Bool { true }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - AddSlotView

class AddSlotView: NSView {
    var onToggle: ((Bool) -> Void)?
    private(set) var isSelected = false
    private var isHovered = false

    private let app: DockApp

    init(frame: NSRect, app: DockApp) {
        self.app = app
        super.init(frame: frame)
        wantsLayer = true

        // Icon — centered horizontally, sitting in the top portion of the slot
        let iconX = (frame.width - kAddIconSize) / 2
        let iconY = kAddNameH + 8
        let imgView = NSImageView(frame: CGRect(x: iconX, y: iconY, width: kAddIconSize, height: kAddIconSize))
        imgView.image        = app.icon
        imgView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(imgView)

        // Name label below the icon
        let lbl = NSTextField(labelWithString: app.name)
        lbl.frame         = CGRect(x: 2, y: 4, width: frame.width - 4, height: kAddNameH)
        lbl.alignment     = .center
        lbl.font          = .systemFont(ofSize: 10, weight: .medium)
        lbl.textColor     = .labelColor
        lbl.lineBreakMode = .byTruncatingTail
        addSubview(lbl)

        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true;  needsDisplay = true }
    override func mouseExited(with event: NSEvent)  { isHovered = false; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        isSelected.toggle()
        onToggle?(isSelected)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // Ring ring reference area — tight around the icon
        let iconY: CGFloat = kAddNameH + 8
        let inset: CGFloat = 6
        let r = CGRect(
            x: (bounds.width - kAddIconSize) / 2 - inset,
            y: iconY - inset,
            width: kAddIconSize + inset * 2,
            height: kAddIconSize + inset * 2
        )
        let radius: CGFloat = 14

        if isSelected {
            // Adaptive ring — labelColor reads against both light and dark
            // glass tints, matching the switcher's selection treatment.
            NSColor.labelColor.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
            NSColor.controlAccentColor.setStroke()
            let ring = NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: radius - 1, yRadius: radius - 1)
            ring.lineWidth = 2.5
            ring.stroke()
        } else if isHovered {
            NSColor.labelColor.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
        }
    }

    required init?(coder: NSCoder) { fatalError() }
}

#!/usr/bin/env swift
import AppKit
import CoreGraphics

func drawIcon(size: Int) -> Data? {
    let s = CGFloat(size)
    guard let ctx = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    let cs = CGColorSpaceCreateDeviceRGB()

    // ── Background gradient (Sonoma/Sequoia style) ─────────────────────────
    let bgColors = [
        CGColor(red: 0.04, green: 0.07, blue: 0.22, alpha: 1),   // deep navy
        CGColor(red: 0.18, green: 0.06, blue: 0.38, alpha: 1),   // violet
        CGColor(red: 0.52, green: 0.07, blue: 0.36, alpha: 1),   // magenta-rose
    ] as CFArray
    if let grad = CGGradient(colorsSpace: cs, colors: bgColors, locations: [0, 0.45, 1.0]) {
        ctx.drawLinearGradient(grad,
            start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    // ── Abstract light streak (upper-left glow) ────────────────────────────
    if size >= 64 {
        let shineColors = [
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.10),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.00),
        ] as CFArray
        if let sg = CGGradient(colorsSpace: cs, colors: shineColors, locations: [0, 1]) {
            ctx.drawLinearGradient(sg,
                start: CGPoint(x: 0, y: s),
                end: CGPoint(x: s * 0.65, y: s * 0.28),
                options: [])
        }
    }

    // ── Floating glass panel (the dock-switcher representation) ───────────
    let panelW  = s * 0.76
    let panelH  = s * 0.26
    let panelX  = (s - panelW) / 2
    let panelY  = s * 0.37
    let panelR  = panelH * 0.28

    let panelRect = CGRect(x: panelX, y: panelY, width: panelW, height: panelH)
    let panelPath = CGPath(roundedRect: panelRect,
                           cornerWidth: panelR, cornerHeight: panelR, transform: nil)

    // Glass fill — gradient for depth
    ctx.saveGState()
    ctx.addPath(panelPath)
    ctx.clip()
    let glassColors = [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.30),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.12),
    ] as CFArray
    if let gg = CGGradient(colorsSpace: cs, colors: glassColors, locations: [0, 1]) {
        ctx.drawLinearGradient(gg,
            start: CGPoint(x: panelX, y: panelY + panelH),
            end:   CGPoint(x: panelX, y: panelY), options: [])
    }
    // Inner shine at top of panel
    let shineH = panelH * 0.35
    let innerShineColors = [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.22),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.00),
    ] as CFArray
    if let isg = CGGradient(colorsSpace: cs, colors: innerShineColors, locations: [0, 1]) {
        ctx.drawLinearGradient(isg,
            start: CGPoint(x: panelX, y: panelY + panelH),
            end:   CGPoint(x: panelX, y: panelY + panelH - shineH), options: [])
    }
    ctx.restoreGState()

    // Glass border
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.40))
    ctx.setLineWidth(max(1, s * 0.007))
    ctx.addPath(panelPath)
    ctx.strokePath()

    // ── App icons inside the panel ─────────────────────────────────────────
    if size >= 32 {
        let iconColors: [(CGFloat, CGFloat, CGFloat)] = [
            (0.22, 0.60, 1.00),   // blue
            (0.18, 0.78, 0.36),   // green
            (1.00, 0.28, 0.28),   // red
            (1.00, 0.70, 0.08),   // yellow
        ]
        let n        = iconColors.count
        let iconSize = panelH * 0.50
        let spacing  = (panelW - CGFloat(n) * iconSize) / CGFloat(n + 1)
        let iconY    = panelY + (panelH - iconSize) / 2
        let iconR    = iconSize * 0.22

        for (i, (r, g, b)) in iconColors.enumerated() {
            let ix       = panelX + spacing + CGFloat(i) * (iconSize + spacing)
            let iconRect = CGRect(x: ix, y: iconY, width: iconSize, height: iconSize)
            let iconPath = CGPath(roundedRect: iconRect,
                                  cornerWidth: iconR, cornerHeight: iconR, transform: nil)

            // Icon fill
            ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
            ctx.addPath(iconPath)
            ctx.fillPath()

            // Icon shine
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: iconRect,
                               cornerWidth: iconR, cornerHeight: iconR, transform: nil))
            ctx.clip()
            let shineCols = [
                CGColor(red: 1, green: 1, blue: 1, alpha: 0.28),
                CGColor(red: 1, green: 1, blue: 1, alpha: 0.00),
            ] as CFArray
            if let sg = CGGradient(colorsSpace: cs, colors: shineCols, locations: [0, 1]) {
                ctx.drawLinearGradient(sg,
                    start: CGPoint(x: ix, y: iconY + iconSize),
                    end:   CGPoint(x: ix, y: iconY + iconSize * 0.45), options: [])
            }
            ctx.restoreGState()

            // Selection ring around the green icon (index 1)
            if i == 1 && size >= 64 {
                let pad      = max(1.5, s * 0.009)
                let ringRect = CGRect(x: ix - pad, y: iconY - pad,
                                     width: iconSize + pad * 2, height: iconSize + pad * 2)
                let ringR    = iconR + pad
                let ringPath = CGPath(roundedRect: ringRect,
                                      cornerWidth: ringR, cornerHeight: ringR, transform: nil)
                ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.90))
                ctx.setLineWidth(max(1.5, s * 0.015))
                ctx.addPath(ringPath)
                ctx.strokePath()
            }
        }
    }

    guard let cgImg = ctx.makeImage() else { return nil }
    let bmp = NSBitmapImageRep(cgImage: cgImg)
    return bmp.representation(using: .png, properties: [:])
}

// ── Build iconset ──────────────────────────────────────────────────────────
let iconsetPath = "/tmp/DockGone.iconset"
try? FileManager.default.createDirectory(atPath: iconsetPath,
                                          withIntermediateDirectories: true)

let specs: [(Int, String)] = [
    (16,   "icon_16x16"),
    (32,   "icon_16x16@2x"),
    (32,   "icon_32x32"),
    (64,   "icon_32x32@2x"),
    (128,  "icon_128x128"),
    (256,  "icon_128x128@2x"),
    (256,  "icon_256x256"),
    (512,  "icon_256x256@2x"),
    (512,  "icon_512x512"),
    (1024, "icon_512x512@2x"),
]

for (px, name) in specs {
    if let data = drawIcon(size: px) {
        let path = "\(iconsetPath)/\(name).png"
        try? data.write(to: URL(fileURLWithPath: path))
        print("✓ \(name).png (\(px)px)")
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetPath, "-o", "/tmp/DockGone.icns"]
try? iconutil.run()
iconutil.waitUntilExit()

if iconutil.terminationStatus == 0 {
    print("✓ /tmp/DockGone.icns")
} else {
    print("✗ iconutil failed")
}

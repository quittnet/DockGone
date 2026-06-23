#!/usr/bin/env swift
import AppKit
import CoreGraphics

// Generates Stagehand's app icon: a couple of arranged app windows on a cool
// gradient, evoking "windows placed where you want them". Run on macOS:
//
//     swift make_icon.swift
//
// It writes AppIcon.icns next to this script (install.sh copies it into the
// bundle). Requires /usr/bin/iconutil (ships with macOS).

func drawIcon(size: Int) -> Data? {
    let s = CGFloat(size)
    guard let ctx = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    let cs = CGColorSpaceCreateDeviceRGB()

    // ── Background gradient (teal → blue → indigo) ─────────────────────────
    let bgColors = [
        CGColor(red: 0.04, green: 0.16, blue: 0.30, alpha: 1),
        CGColor(red: 0.06, green: 0.30, blue: 0.52, alpha: 1),
        CGColor(red: 0.14, green: 0.20, blue: 0.52, alpha: 1),
    ] as CFArray
    if let grad = CGGradient(colorsSpace: cs, colors: bgColors, locations: [0, 0.5, 1]) {
        ctx.drawLinearGradient(grad,
            start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    // ── Soft upper-left glow ───────────────────────────────────────────────
    if size >= 64 {
        let glow = [
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.12),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.00),
        ] as CFArray
        if let g = CGGradient(colorsSpace: cs, colors: glow, locations: [0, 1]) {
            ctx.drawRadialGradient(g,
                startCenter: CGPoint(x: s * 0.28, y: s * 0.78), startRadius: 0,
                endCenter:   CGPoint(x: s * 0.28, y: s * 0.78), endRadius: s * 0.62,
                options: [])
        }
    }

    // ── One arranged app window ────────────────────────────────────────────
    func drawWindow(_ rect: CGRect, accent: CGColor, active: Bool) {
        let radius = rect.height * 0.14
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        // Body (with drop shadow for depth)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03,
                      color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
        ctx.setFillColor(CGColor(red: 0.97, green: 0.98, blue: 1.0, alpha: 1))
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()

        // Title bar (accent strip, clipped to the rounded body)
        let barH = rect.height * 0.26
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.setFillColor(accent)
        ctx.fill(CGRect(x: rect.minX, y: rect.maxY - barH, width: rect.width, height: barH))
        ctx.restoreGState()

        // Traffic-light dots
        if size >= 64 {
            let d = barH * 0.30
            let cy = rect.maxY - barH / 2 - d / 2
            let lights = [
                CGColor(red: 1.00, green: 0.37, blue: 0.34, alpha: 1),
                CGColor(red: 1.00, green: 0.74, blue: 0.18, alpha: 1),
                CGColor(red: 0.30, green: 0.82, blue: 0.34, alpha: 1),
            ]
            for (i, c) in lights.enumerated() {
                let cx = rect.minX + barH * 0.45 + CGFloat(i) * d * 1.7
                ctx.setFillColor(c)
                ctx.fillEllipse(in: CGRect(x: cx, y: cy, width: d, height: d))
            }
        }

        // Content lines
        if size >= 128 {
            ctx.setFillColor(CGColor(red: 0.62, green: 0.68, blue: 0.80, alpha: 0.55))
            let lineH = rect.height * 0.045
            let lx = rect.minX + rect.width * 0.12
            var ly = rect.maxY - barH - rect.height * 0.18
            for k in 0..<3 {
                let lw = rect.width * (k == 2 ? 0.40 : 0.66)
                ctx.fill(CGRect(x: lx, y: ly, width: lw, height: lineH))
                ly -= lineH * 2.4
            }
        }

        // Border / active highlight ring
        ctx.setStrokeColor(active
            ? CGColor(red: 1, green: 1, blue: 1, alpha: 0.95)
            : CGColor(red: 1, green: 1, blue: 1, alpha: 0.25))
        ctx.setLineWidth(active ? max(1.5, s * 0.014) : max(1, s * 0.006))
        ctx.addPath(path)
        ctx.strokePath()
    }

    // Back window (upper-left), then the active front window (lower-right).
    drawWindow(CGRect(x: s * 0.13, y: s * 0.40, width: s * 0.50, height: s * 0.40),
               accent: CGColor(red: 0.20, green: 0.52, blue: 0.92, alpha: 1), active: false)
    drawWindow(CGRect(x: s * 0.40, y: s * 0.15, width: s * 0.47, height: s * 0.40),
               accent: CGColor(red: 0.18, green: 0.74, blue: 0.55, alpha: 1), active: true)

    guard let cgImg = ctx.makeImage() else { return nil }
    let bmp = NSBitmapImageRep(cgImage: cgImg)
    return bmp.representation(using: .png, properties: [:])
}

// ── Build the iconset and run iconutil ──────────────────────────────────────
let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let iconsetPath = NSTemporaryDirectory() + "Stagehand.iconset"
try? FileManager.default.removeItem(atPath: iconsetPath)
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

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
        try? data.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(name).png"))
    }
}

let outURL = scriptDir.appendingPathComponent("AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetPath, "-o", outURL.path]
try? iconutil.run()
iconutil.waitUntilExit()

if iconutil.terminationStatus == 0 {
    print("✓ wrote \(outURL.path)")
} else {
    print("✗ iconutil failed")
    exit(1)
}

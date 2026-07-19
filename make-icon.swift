#!/usr/bin/env swift
// Generates AppIcon.icns programmatically: a night-dark squircle with a soft
// glowing ring — the wisp light only you can follow.
// Usage: swift make-icon.swift  (run from the wisp dir)

import AppKit
import Foundation

let here    = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = here.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

func makePNG(size px: Int) -> Data? {
    let pf = CGFloat(px)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32)
    else { return nil }
    rep.size = NSSize(width: pf, height: pf)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = ctx

    // Squircle background: deep night-blue gradient, like a dark marsh sky.
    let radius = pf * 0.225
    let squircle = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: pf, height: pf),
                                xRadius: radius, yRadius: radius)
    squircle.addClip()
    let grad = NSGradient(colors: [
        NSColor(red: 0.10, green: 0.13, blue: 0.28, alpha: 1),
        NSColor(red: 0.03, green: 0.05, blue: 0.13, alpha: 1),
    ])!
    grad.draw(in: NSRect(x: 0, y: 0, width: pf, height: pf), angle: -90)

    // The wisp: a glowing cyan ring. Glow is built from concentric strokes of
    // increasing width and decreasing alpha, plus a shadow for bloom.
    let center = NSPoint(x: pf / 2, y: pf / 2)
    let ringR  = pf * 0.27
    let wisp   = NSColor(red: 0.42, green: 0.82, blue: 1.0, alpha: 1)

    func ring(_ r: CGFloat, width: CGFloat, alpha: CGFloat) {
        let p = NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r,
                                            width: r * 2, height: r * 2))
        p.lineWidth = width
        wisp.withAlphaComponent(alpha).setStroke()
        p.stroke()
    }

    // Halo layers, widest first.
    ring(ringR, width: pf * 0.16, alpha: 0.10)
    ring(ringR, width: pf * 0.11, alpha: 0.16)
    ring(ringR, width: pf * 0.07, alpha: 0.28)

    // Bright core ring with a bloom shadow.
    let shadow = NSShadow()
    shadow.shadowColor = wisp
    shadow.shadowBlurRadius = pf * 0.05
    shadow.shadowOffset = .zero
    shadow.set()
    ring(ringR, width: pf * 0.045, alpha: 1.0)

    // A small bright pointer-dot at the center — the cursor the ring follows.
    let dotR = pf * 0.045
    let dot = NSBezierPath(ovalIn: NSRect(x: center.x - dotR, y: center.y - dotR,
                                          width: dotR * 2, height: dotR * 2))
    NSColor(red: 0.88, green: 0.97, blue: 1.0, alpha: 1).setFill()
    dot.fill()

    return rep.representation(using: .png, properties: [:])
}

for (name, px) in sizes {
    guard let data = makePNG(size: px) else { continue }
    try data.write(to: iconset.appendingPathComponent("\(name).png"))
}

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconset.path, "-o", here.appendingPathComponent("AppIcon.icns").path]
try proc.run()
proc.waitUntilExit()
print("Wrote AppIcon.icns")

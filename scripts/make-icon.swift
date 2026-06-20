#!/usr/bin/env swift
// Generates AppIcon.iconset (PNGs) for GrammarGem — a gold pen-nib on the ink
// brand square. Run from mac/:  swift scripts/make-icon.swift
// Then:  iconutil -c icns AppIcon.iconset -o AppSupport/AppIcon.icns
import AppKit
import Foundation

let ink = NSColor(red: 0x10 / 255.0, green: 0x23 / 255.0, blue: 0x1B / 255.0, alpha: 1)
let gold = NSColor(red: 0xC9 / 255.0, green: 0xA2 / 255.0, blue: 0x4B / 255.0, alpha: 1)

func png(size: Int) -> Data {
    let S = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let g = ctx.cgContext

    // Brand square (rounded).
    let rrect = CGPath(roundedRect: CGRect(x: 0, y: 0, width: S, height: S),
                       cornerWidth: S * 0.22, cornerHeight: S * 0.22, transform: nil)
    g.addPath(rrect); g.setFillColor(ink.cgColor); g.fillPath()

    // Gold nib (downward triangle), coordinates are y-up.
    let tri = CGMutablePath()
    tri.move(to: CGPoint(x: 0.18 * S, y: 0.78 * S))
    tri.addLine(to: CGPoint(x: 0.82 * S, y: 0.78 * S))
    tri.addLine(to: CGPoint(x: 0.50 * S, y: 0.10 * S))
    tri.closeSubpath()
    g.addPath(tri); g.setFillColor(gold.cgColor); g.fillPath()

    // Center slit.
    g.setStrokeColor(ink.cgColor)
    g.setLineWidth(max(1, S * 0.05)); g.setLineCap(.round)
    g.move(to: CGPoint(x: 0.50 * S, y: 0.20 * S))
    g.addLine(to: CGPoint(x: 0.50 * S, y: 0.60 * S))
    g.strokePath()

    // Vent hole.
    g.setFillColor(ink.cgColor)
    let r = S * 0.055
    g.addEllipse(in: CGRect(x: 0.50 * S - r, y: 0.64 * S - r, width: 2 * r, height: 2 * r))
    g.fillPath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let dir = "AppIcon.iconset"
try? fm.removeItem(atPath: dir)
try! fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

let specs: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, size) in specs {
    try! png(size: size).write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
}
print("wrote \(specs.count) icon images to \(dir)")

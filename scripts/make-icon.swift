// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
// Renders the approved SVG master with AppKit (the renderer the app itself uses) into an .iconset.
// Usage: swift scripts/make-icon.swift <master.svg> <out.iconset>
import AppKit
let a = CommandLine.arguments
guard a.count == 3, let img = NSImage(contentsOf: URL(fileURLWithPath: a[1])) else { FileHandle.standardError.write(Data("cannot load SVG\n".utf8)); exit(1) }
let out = URL(fileURLWithPath: a[2]); try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let sizes: [(String, Int)] = [("16x16",16),("16x16@2x",32),("32x32",32),("32x32@2x",64),("128x128",128),("128x128@2x",256),("256x256",256),("256x256@2x",512),("512x512",512),("512x512@2x",1024)]
for (name, px) in sizes {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.set(); NSRect(x: 0, y: 0, width: px, height: px).fill(using: .copy)
    let f = CGFloat(px)
    // macOS app-icon export: neutral graphite squircle plate (824/1024 of the canvas, Apple grid) carrying the approved loupe unchanged.
    let plate = NSRect(x: f * 100 / 1024, y: f * 100 / 1024, width: f * 824 / 1024, height: f * 824 / 1024)
    let path = NSBezierPath(roundedRect: plate, xRadius: plate.width * 0.2237, yRadius: plate.width * 0.2237)
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow(); sh.shadowColor = NSColor(white: 0, alpha: 0.35); sh.shadowBlurRadius = f * 0.018; sh.shadowOffset = NSSize(width: 0, height: -f * 0.010); sh.set()
    NSColor(white: 0.1, alpha: 1).setFill(); path.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [NSColor(srgbRed: 0.27, green: 0.29, blue: 0.32, alpha: 1), NSColor(srgbRed: 0.09, green: 0.10, blue: 0.11, alpha: 1)])!.draw(in: path, angle: -90)
    NSColor(white: 1, alpha: 0.10).setStroke(); path.lineWidth = max(1, f / 512); path.stroke()
    let side = plate.width * 0.80
    img.draw(in: NSRect(x: plate.midX - side / 2 - plate.width * 0.015, y: plate.midY - side / 2 + plate.width * 0.015, width: side, height: side), from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("icon_\(name).png"))
}

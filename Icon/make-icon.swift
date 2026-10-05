// Draws the app icon and writes Icon/AppIcon.icns.  Run: swift Icon/make-icon.swift
import AppKit

let canvas: CGFloat = 1024
let level: CGFloat = 0.62   // how far round the tick arc is lit

func drawIcon(in ctx: CGContext) {
    // Body: macOS icon grid, 824pt rounded square centred on a 1024 canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(bodyPath); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath); ctx.clip()
    let red = CGGradient(colorsSpace: nil, colors: [
        NSColor(srgbRed: 0.93, green: 0.16, blue: 0.20, alpha: 1).cgColor,
        NSColor(srgbRed: 0.62, green: 0.04, blue: 0.09, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(red, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()

    let center = CGPoint(x: 512, y: 500)

    // Tick arc: 270° sweep from bottom-left (min) clockwise to bottom-right (max), like a real knob.
    let ticks = 21
    let startAngle = CGFloat.pi * 1.25, sweep = CGFloat.pi * 1.5
    for i in 0..<ticks {
        let t = CGFloat(i) / CGFloat(ticks - 1)
        let a = startAngle - sweep * t
        let lit = t <= level
        let inner: CGFloat = 300, outer: CGFloat = lit ? 352 : 340
        ctx.setStrokeColor(lit ? NSColor.white.cgColor : NSColor.white.withAlphaComponent(0.28).cgColor)
        ctx.setLineWidth(18); ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: center.x + cos(a) * inner, y: center.y + sin(a) * inner))
        ctx.addLine(to: CGPoint(x: center.x + cos(a) * outer, y: center.y + sin(a) * outer))
        ctx.strokePath()
    }

    // Knob: dark skirt, then brushed-aluminium cap.
    let skirt = CGRect(x: center.x - 245, y: center.y - 245, width: 490, height: 490)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 30, color: NSColor.black.withAlphaComponent(0.5).cgColor)
    ctx.setFillColor(NSColor(white: 0.12, alpha: 1).cgColor)
    ctx.fillEllipse(in: skirt)
    ctx.restoreGState()

    let cap = skirt.insetBy(dx: 34, dy: 34)
    ctx.saveGState()
    ctx.addEllipse(in: cap); ctx.clip()
    let metal = CGGradient(colorsSpace: nil, colors: [
        NSColor(white: 0.97, alpha: 1).cgColor,
        NSColor(white: 0.78, alpha: 1).cgColor,
        NSColor(white: 0.60, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(metal, start: CGPoint(x: cap.minX, y: cap.maxY), end: CGPoint(x: cap.maxX, y: cap.minY), options: [])
    // Subtle conic sheen for a machined look.
    for i in 0..<48 {
        let a = CGFloat(i) / 48 * 2 * .pi
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(i % 2 == 0 ? 0.06 : 0).cgColor)
        ctx.setLineWidth(10)
        ctx.move(to: center)
        ctx.addLine(to: CGPoint(x: center.x + cos(a) * 260, y: center.y + sin(a) * 260))
        ctx.strokePath()
    }
    ctx.restoreGState()
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.7).cgColor)
    ctx.setLineWidth(4)
    ctx.strokeEllipse(in: cap.insetBy(dx: 2, dy: 2))

    // Pointer line, aimed at the current level.
    let a = startAngle - sweep * level
    ctx.setStrokeColor(NSColor(white: 0.15, alpha: 1).cgColor)
    ctx.setLineWidth(26); ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: center.x + cos(a) * 70, y: center.y + sin(a) * 70))
    ctx.addLine(to: CGPoint(x: center.x + cos(a) * 175, y: center.y + sin(a) * 175))
    ctx.strokePath()
}

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.cgContext.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    drawIcon(in: ctx.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let iconset = dir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try render(size: 1024).write(to: dir.appendingPathComponent("preview.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", dir.appendingPathComponent("AppIcon.icns").path]
try iconutil.run(); iconutil.waitUntilExit()
try FileManager.default.removeItem(at: iconset)
print("Wrote Icon/AppIcon.icns")

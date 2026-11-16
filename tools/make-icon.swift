// Renders the claudeGauge app icon (1024×1024 PNG) with CoreGraphics.
// Usage: swift tools/make-icon.swift <output.png>
//
// Concept: a small terra-cotta pixel critter whose antenna is the needle of a
// usage speedometer drawn above it. Original artwork; nothing copied.

import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

let green = rgb(0x788c5d), amber = rgb(0xd97757), red = rgb(0xc0392b)
let terra = rgb(0xd97757), terraDark = rgb(0xb25f42)
let ink = rgb(0x1a1918), cream = rgb(0xfaf9f5), track = rgb(0x3a3936)

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
                    bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// --- Background: macOS-style rounded square with a subtle vertical gradient.
let inset: CGFloat = 100   // Apple grid: ~824 pt artwork inside 1024 canvas
let bgRect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.35))
ctx.addPath(bgPath); ctx.setFillColor(rgb(0x262523)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(bgPath); ctx.clip()
let grad = CGGradient(colorsSpace: cs, colors: [rgb(0x34322f), rgb(0x1c1b1a)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: bgRect.maxY), end: CGPoint(x: 0, y: bgRect.minY), options: [])
ctx.restoreGState()

// --- Speedometer arc (180° → 0°), centred on the critter's head.
let pivot = CGPoint(x: size / 2, y: 470)
let radius: CGFloat = 300
let arcWidth: CGFloat = 54

func arc(from a0: CGFloat, to a1: CGFloat, color: CGColor) {
    ctx.setStrokeColor(color)
    ctx.setLineWidth(arcWidth)
    ctx.setLineCap(.butt)
    ctx.addArc(center: pivot, radius: radius, startAngle: a0, endAngle: a1, clockwise: true)
    ctx.strokePath()
}
let deg = CGFloat.pi / 180
// Track, then the three zones (0–50 green, 50–80 amber, 80–100 red), with small gaps.
arc(from: 180 * deg, to: 0, color: track)
arc(from: 180 * deg, to: 91 * deg, color: green)
arc(from: 89 * deg, to: 37 * deg, color: amber)
arc(from: 35 * deg, to: 0, color: red)

// Tick marks inside the arc.
ctx.setStrokeColor(rgb(0xfaf9f5, 0.55))
ctx.setLineCap(.round)
for i in 0...10 {
    let a = (180 - CGFloat(i) * 18) * deg
    let major = i % 5 == 0
    ctx.setLineWidth(major ? 12 : 7)
    let r0 = radius - arcWidth / 2 - (major ? 58 : 40)
    let r1 = radius - arcWidth / 2 - 16
    ctx.move(to: CGPoint(x: pivot.x + cos(a) * r0, y: pivot.y + sin(a) * r0))
    ctx.addLine(to: CGPoint(x: pivot.x + cos(a) * r1, y: pivot.y + sin(a) * r1))
    ctx.strokePath()
}

// --- Pixel critter (grid of square "pixels"), drawn below the pivot.
let px: CGFloat = 38
// Rows from top to bottom; "#" body, "e" eye, "." empty.
// A round-shouldered critter cheering with both arms up, on two legs.
let critter = [
    "#...###...#",
    "#.#######.#",
    "###e###e###",
    "###########",
    "..#######..",
    "..##...##..",
    "..##...##..",
]
let gridW = CGFloat(critter[0].count) * px
let top = pivot.y + 10          // head top sits just under the pivot
let left = size / 2 - gridW / 2
for (r, row) in critter.enumerated() {
    for (c, ch) in row.enumerated() where ch != "." {
        let rect = CGRect(x: left + CGFloat(c) * px, y: top - CGFloat(r + 1) * px, width: px, height: px)
        ctx.setFillColor(ch == "e" ? ink : (r >= 5 ? terraDark : terra))
        ctx.fill(rect.insetBy(dx: -0.5, dy: -0.5))
    }
}

// --- Needle = the critter's antenna, pointing at ~62 %.
let needleAngle = (180 - 0.62 * 180) * deg
let tip = CGPoint(x: pivot.x + cos(needleAngle) * (radius - 70), y: pivot.y + sin(needleAngle) * (radius - 70))
ctx.setStrokeColor(cream)
ctx.setLineWidth(22)
ctx.setLineCap(.round)
ctx.move(to: pivot); ctx.addLine(to: tip); ctx.strokePath()
// Antenna knob at the tip and hub on the head.
ctx.setFillColor(cream)
ctx.fillEllipse(in: CGRect(x: tip.x - 26, y: tip.y - 26, width: 52, height: 52))
ctx.setFillColor(terra)
ctx.fillEllipse(in: CGRect(x: tip.x - 13, y: tip.y - 13, width: 26, height: 26))
ctx.setFillColor(cream)
ctx.fillEllipse(in: CGRect(x: pivot.x - 30, y: pivot.y - 30, width: 60, height: 60))

// --- Write PNG.
let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")

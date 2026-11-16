// Renders the README illustrations with the app's own GaugeIcon code.
// Built and run by tools/make-readme-images.sh; output goes to docs/images/.

import AppKit

let outDir = CommandLine.arguments[1]
/// App version, read from ClaudeGauge/Info.plist by make-readme-images.sh.
let appVersion = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "?"
let scale: CGFloat = 2   // Retina-sized PNGs

func reading(_ p: Int) -> UsageReading {
    UsageReading(sessionPercent: p, sessionReset: nil, weeklyPercent: nil, weeklyReset: nil)
}
func ok(_ p: Int) -> GaugeState { .ok(reading(p), updated: Date()) }

func symbol(_ name: String) -> NSImage {
    let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
}

/// Draws an image tinted with the current label colour when it is a template.
func drawItem(_ item: NSImage, in rect: NSRect) {
    if item.isTemplate {
        NSImage(size: item.size, flipped: false) { b in
            item.draw(in: b); NSColor.labelColor.set(); b.fill(using: .sourceAtop); return true
        }.draw(in: rect)
    } else {
        item.draw(in: rect)
    }
}

func save(_ image: NSImage, _ name: String) {
    let w = Int(image.size.width * scale), h = Int(image.size.height * scale)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = image.size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(origin: .zero, size: image.size))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
    print("wrote \(name)")
}

func render(_ size: NSSize, dark: Bool, _ draw: @escaping (NSRect) -> Void) -> NSImage {
    let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
    let image = NSImage(size: size)
    appearance.performAsCurrentDrawingAppearance {
        image.lockFocus()
        draw(NSRect(origin: .zero, size: size))
        image.unlockFocus()
    }
    return image
}

let barH: CGFloat = 24

/// A slice of the macOS menu bar: claudeGauge next to some system icons and the clock.
func menuBar(_ state: GaugeState, dark: Bool) -> NSImage {
    let items: [NSImage] = [GaugeIcon.image(for: state), symbol("wifi"), symbol("battery.75percent"),
                            symbol("magnifyingglass"), symbol("switch.2")]
    let clock = "Mon 16 Nov  10:42"
    let font = NSFont.systemFont(ofSize: 13, weight: .medium)
    let clockW = (clock as NSString).size(withAttributes: [.font: font]).width
    let gap: CGFloat = 18
    let width = 14 + items.map { $0.size.width }.reduce(0, +) + gap * CGFloat(items.count) + clockW + 14
    return render(NSSize(width: width, height: barH), dark: dark) { rect in
        (dark ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        var x: CGFloat = 14
        for item in items {
            let s = item.size
            drawItem(item, in: NSRect(x: x, y: (barH - s.height) / 2, width: s.width, height: s.height))
            x += s.width + gap
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        let h = (clock as NSString).size(withAttributes: attrs).height
        (clock as NSString).draw(at: NSPoint(x: x, y: (barH - h) / 2), withAttributes: attrs)
    }
}

for (p, name) in [(25, "menubar-25"), (75, "menubar-75")] {
    save(menuBar(ok(p), dark: true), "\(name)-dark.png")
    save(menuBar(ok(p), dark: false), "\(name)-light.png")
}

// All states, enlarged, with captions.
let states: [(GaugeState, String)] = [
    (ok(0), "0%"), (ok(25), "25%"), (ok(50), "50%"), (ok(75), "75%"), (ok(100), "100%"),
    (.offline(last: reading(40), lastUpdate: nil), "Offline"),
    (.notLoggedIn, "Not logged in"), (.starting, "Starting"),
]
let zoom: CGFloat = 3
let cellW: CGFloat = 104, cellH: CGFloat = 92
for dark in [true, false] {
    let img = render(NSSize(width: cellW * CGFloat(states.count), height: cellH), dark: dark) { rect in
        (dark ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 0.97, alpha: 1)).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
        let caption: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium),
                                                      .foregroundColor: NSColor.secondaryLabelColor]
        for (i, (state, label)) in states.enumerated() {
            let s = GaugeIcon.size
            let w = s.width * zoom, h = s.height * zoom
            GaugeIcon.image(for: state).draw(in: NSRect(x: CGFloat(i) * cellW + (cellW - w) / 2, y: 26, width: w, height: h))
            let lw = (label as NSString).size(withAttributes: caption).width
            (label as NSString).draw(at: NSPoint(x: CGFloat(i) * cellW + (cellW - lw) / 2, y: 8), withAttributes: caption)
        }
    }
    save(img, "states-\(dark ? "dark" : "light").png")
}

// Illustration of the dropdown menu.
func menuMock(dark: Bool) -> NSImage {
    let lines: [(String, Bool)] = [
        ("Session: 25%  ·  resets in 3h 12m", false),
        ("Weekly: 41%  ·  resets Sun 20:00", false),
        ("Fable: 12%  ·  resets Sun 20:00", false),
        ("—", false),
        ("Launch at login", true),
        ("Log in…", true),
        ("—", false),
        ("About claudeGauge", true),
        ("Quit claudeGauge          ⌘Q", true),
        ("—", false),
        ("version \(appVersion)", false),
    ]
    let rowH: CGFloat = 22, sepH: CGFloat = 11, padV: CGFloat = 6
    let height = padV * 2 + lines.reduce(0) { $0 + ($1.0 == "—" ? sepH : rowH) }
    let width: CGFloat = 290
    return render(NSSize(width: width, height: height), dark: dark) { rect in
        (dark ? NSColor(white: 0.20, alpha: 1) : NSColor(white: 0.97, alpha: 1)).setFill()
        let panel = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        panel.fill()
        NSColor.separatorColor.setStroke(); panel.stroke()
        var y = height - padV
        let font = NSFont.menuFont(ofSize: 13)
        for (text, enabled) in lines {
            if text == "—" {
                y -= sepH
                NSColor.separatorColor.setFill()
                NSRect(x: 12, y: y + sepH / 2, width: width - 24, height: 1).fill()
                continue
            }
            y -= rowH
            let color = enabled ? NSColor.labelColor : NSColor.secondaryLabelColor
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            if text == "Launch at login" {
                ("✓" as NSString).draw(at: NSPoint(x: 10, y: y + 3), withAttributes: attrs)
            }
            let x = text.hasPrefix("version")
                ? (width - (text as NSString).size(withAttributes: attrs).width) / 2
                : 26
            (text as NSString).draw(at: NSPoint(x: x, y: y + 3), withAttributes: attrs)
        }
    }
}
save(menuMock(dark: true), "menu-dark.png")
save(menuMock(dark: false), "menu-light.png")

import AppKit

enum GaugeIcon {
    static let size = NSSize(width: 38, height: 16)

    static func label(for state: GaugeState) -> String {
        switch state {
        case .starting: return "--"
        case .ok(let reading, _): return "\(reading.sessionPercent)%"
        case .notLoggedIn: return "⚠"
        case .offline(let last, _): return last.map { "\($0.sessionPercent)%" } ?? "--"
        }
    }

    static func fillColor(for state: GaugeState) -> NSColor? {
        switch state {
        case .ok(let reading, _): return Theme.color(forPercent: reading.sessionPercent)
        case .offline(let last, _): return last == nil ? nil : NSColor.secondaryLabelColor
        case .starting, .notLoggedIn: return nil
        }
    }

    private static func percent(for state: GaugeState) -> Int? {
        switch state {
        case .ok(let reading, _): return reading.sessionPercent
        case .offline(let last, _): return last?.sessionPercent
        case .starting, .notLoggedIn: return nil
        }
    }

    static func image(for state: GaugeState) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            // Plain rounded bar (no battery nub) so it doesn't read as a battery.
            let body = NSRect(x: 1, y: 1, width: 36, height: 14)
            let outline = NSBezierPath(roundedRect: body, xRadius: 3, yRadius: 3)

            if let percent = percent(for: state), let fill = fillColor(for: state) {
                NSGraphicsContext.saveGraphicsState()
                outline.addClip()
                Theme.track.setFill()
                body.fill()
                let clamped = CGFloat(min(max(percent, 0), 100))
                fill.setFill()
                NSRect(x: body.minX, y: body.minY, width: body.width * clamped / 100, height: body.height).fill()
                NSGraphicsContext.restoreGraphicsState()
            }

            NSColor.labelColor.setStroke()
            outline.lineWidth = 1
            outline.stroke()

            drawLabel(label(for: state), in: body)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func drawLabel(_ text: String, in body: NSRect) {
        let font = NSFont.systemFont(ofSize: 10, weight: .bold)
        let strokePass: [NSAttributedString.Key: Any] = [
            .font: font,
            .strokeColor: NSColor.black,
            .strokeWidth: 20, // positive: stroke only, 2 pt on a 10 pt font
        ]
        let fillPass: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let measured = NSAttributedString(string: text, attributes: fillPass).size()
        let origin = NSPoint(x: body.midX - measured.width / 2, y: body.midY - measured.height / 2)
        NSAttributedString(string: text, attributes: strokePass).draw(at: origin)
        NSAttributedString(string: text, attributes: fillPass).draw(at: origin)
    }
}

import AppKit

/// Menu bar gauge: the top half of a dial. The needle starts lying flat to the
/// left (0 %) and sweeps clockwise to lie flat to the right (100 %); the sector
/// it has swept is painted in the usage colour. No text is drawn — the
/// percentage goes to the tooltip and VoiceOver via `label(for:)`.
enum GaugeIcon {
    /// 18 pt tall like system menu bar glyphs; the dial sits at the bottom so its
    /// base lines up with the bottom of the neighbouring icons.
    static let size = NSSize(width: 24, height: 18)

    private static let center = NSPoint(x: 12, y: 3.2)
    private static let radius: CGFloat = 11
    /// Tick marks at 25 %, 50 % and 75 %, drawn from the rim towards the centre.
    static let tickPercents = [25, 50, 75]
    private static let tickLength: CGFloat = 2.6

    /// Text for the tooltip and accessibility (never drawn in the icon).
    static func label(for state: GaugeState) -> String {
        switch state {
        case .starting: return "Claude usage: checking…"
        case .ok(let reading, _): return "Claude session usage: \(reading.sessionPercent)%"
        case .notLoggedIn: return "Claude usage: not logged in"
        case .offline(let last, _):
            return last.map { "Claude usage: offline (last \($0.sessionPercent)%)" } ?? "Claude usage: offline"
        }
    }

    static func fillColor(for state: GaugeState) -> NSColor? {
        switch state {
        case .ok(let reading, _): return Theme.color(forPercent: reading.sessionPercent)
        case .offline(let last, _): return last == nil ? nil : NSColor.secondaryLabelColor
        case .starting, .notLoggedIn: return nil
        }
    }

    /// Needle angle in radians: π (flat left) at 0 %, π/2 (straight up) at 50 %, 0 (flat right) at 100 %.
    static func needleAngle(forPercent percent: Int) -> CGFloat {
        let clamped = CGFloat(min(max(percent, 0), 100))
        return .pi * (1 - clamped / 100)
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
            let dial = NSBezierPath()
            dial.move(to: NSPoint(x: center.x - radius, y: center.y))
            dial.appendArc(withCenter: center, radius: radius, startAngle: 180, endAngle: 0, clockwise: true)
            dial.close()

            if let percent = percent(for: state), let fill = fillColor(for: state) {
                // Unswept part of the dial: a translucent label tint so the needle
                // stays visible on both light and dark menu bars.
                NSColor.labelColor.withAlphaComponent(0.15).setFill()
                dial.fill()

                // Swept sector: from flat-left, clockwise, down to the needle.
                let degrees = needleAngle(forPercent: percent) * 180 / .pi
                let sector = NSBezierPath()
                sector.move(to: center)
                sector.appendArc(withCenter: center, radius: radius, startAngle: 180, endAngle: degrees, clockwise: true)
                sector.close()
                fill.setFill()
                sector.fill()
            }

            NSColor.labelColor.setStroke()
            dial.lineWidth = 1.2
            dial.stroke()
            drawTicks()

            if let percent = percent(for: state) {
                drawNeedle(at: needleAngle(forPercent: percent))
            } else if case .notLoggedIn = state {
                drawExclamation()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func drawTicks() {
        let ticks = NSBezierPath()
        for percent in tickPercents {
            let angle = needleAngle(forPercent: percent)
            let outer = radius - 0.5
            let inner = radius - tickLength
            ticks.move(to: NSPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
            ticks.line(to: NSPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
        }
        ticks.lineWidth = 1.1
        ticks.lineCapStyle = .butt
        NSColor.labelColor.setStroke()
        ticks.stroke()
    }

    private static func drawNeedle(at angle: CGFloat) {
        let length = radius - 1
        let tip = NSPoint(x: center.x + cos(angle) * length, y: center.y + sin(angle) * length)
        let needle = NSBezierPath()
        needle.move(to: center)
        needle.line(to: tip)
        needle.lineWidth = 1.6
        needle.lineCapStyle = .round
        NSColor.labelColor.setStroke()
        needle.stroke()

        NSColor.labelColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - 1.6, y: center.y - 1.6, width: 3.2, height: 3.2)).fill()
    }

    private static func drawExclamation() {
        NSColor.labelColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: center.x - 0.9, y: center.y + 3.1, width: 1.8, height: 4.6), xRadius: 0.9, yRadius: 0.9).fill()
        NSBezierPath(ovalIn: NSRect(x: center.x - 1, y: center.y + 0.5, width: 2, height: 2)).fill()
    }
}

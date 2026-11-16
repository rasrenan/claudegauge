import AppKit

enum Theme {
    static let green = rgb(0x78, 0x8c, 0x5d)
    static let amber = rgb(0xd9, 0x77, 0x57)
    static let red = rgb(0xc0, 0x39, 0x2b)
    static let track = rgb(0x2a, 0x2a, 0x28)

    /// Gauge colour for a usage percentage: green below 50, amber 50-79, red from 80.
    static func color(forPercent percent: Int) -> NSColor {
        switch percent {
        case ..<50: return green
        case 50..<80: return amber
        default: return red
        }
    }

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }
}

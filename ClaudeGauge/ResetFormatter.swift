import Foundation

enum ResetFormatter {
    static func text(until reset: Date, now: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let secs = reset.timeIntervalSince(now)
        if secs <= 0 { return "resets now" }
        let minutes = Int((secs / 60).rounded(.up))
        if minutes < 60 { return "resets in \(minutes)m" }
        if minutes < 24 * 60 { return "resets in \(minutes / 60)h \(minutes % 60)m" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE j:mm")
        return "resets " + formatter.string(from: reset)
    }
}

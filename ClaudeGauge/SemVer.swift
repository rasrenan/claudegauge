import Foundation

struct SemVer: Comparable, CustomStringConvertible {
    let major: Int, minor: Int, patch: Int

    init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Accepts "1.2.3", with an optional leading "v"/"V" and surrounding whitespace.
    init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = text.first, first == "v" || first == "V" { text.removeFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = Int(part) else { return nil }
            numbers.append(value)
        }
        self.init(major: numbers[0], minor: numbers[1], patch: numbers[2])
    }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (a: SemVer, b: SemVer) -> Bool {
        (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
    }
}

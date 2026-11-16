import Foundation

struct Credentials: Equatable {
    let token: String
    let expiresAt: Date?
}

enum CredentialsDecoder {
    static func decode(_ raw: String) -> Credentials? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let jsonText = isHex(trimmed) ? (hexDecoded(trimmed) ?? "") : trimmed
        guard let data = jsonText.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        let object = (root["claudeAiOauth"] as? [String: Any]) ?? root
        guard let token = object["accessToken"] as? String, !token.isEmpty else { return nil }
        let expiresAt = (object["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return Credentials(token: token, expiresAt: expiresAt)
    }

    private static func isHex(_ s: String) -> Bool {
        !s.hasPrefix("{") && s.count % 2 == 0 && s.allSatisfy { $0.isHexDigit }
    }

    private static func hexDecoded(_ s: String) -> String? {
        var bytes = [UInt8]()
        var index = s.startIndex
        while index < s.endIndex {
            let next = s.index(index, offsetBy: 2)
            guard let byte = UInt8(s[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return String(bytes: bytes, encoding: .utf8)
    }
}

enum TokenStatus: Equatable {
    case valid(String)
    case missing
    case expired
}

struct TokenReader {
    var readRaw: () -> String? = TokenReader.securityCLI

    func status(now: Date) -> TokenStatus {
        guard let raw = readRaw(), let credentials = CredentialsDecoder.decode(raw) else { return .missing }
        if let expiresAt = credentials.expiresAt, expiresAt <= now { return .expired }
        return .valid(credentials.token)
    }

    /// Reads the Claude Code credentials via the `security` CLI. Returns nil on any failure.
    static func securityCLI() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

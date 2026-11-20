import CoreGraphics
import Foundation

public struct SensitiveMatch: Equatable, Sendable {
    public enum Kind: String, Sendable, Codable { case email, phone, iban, card, secret }
    public let kind: Kind
    public let range: Range<String.Index>
}

/// A sensitive match located in an image.
public struct SensitiveRegion: Sendable, Equatable {
    public let kind: SensitiveMatch.Kind
    public let text: String
    /// Image pixels, top-left origin (like `TextRegion.boundingBox`).
    public let boundingBox: CGRect

    public init(kind: SensitiveMatch.Kind, text: String, boundingBox: CGRect) {
        self.kind = kind
        self.text = text
        self.boundingBox = boundingBox
    }
}

/// Findet vertrauliche Angaben in erkanntem Text (Knippi-Spec §7.1).
public struct SensitiveDataDetector: Sendable {
    public init() {}

    public func matches(in text: String) -> [SensitiveMatch] {
        var result: [SensitiveMatch] = []
        // NSDataDetector reports IBAN/card digit runs as phone numbers, also when the
        // checksum rejects them. Such runs are not phone numbers: drop those hits.
        let ibanOrCardShapes = (regexMatches(in: text, pattern: Self.ibanPattern, kind: .iban) { _ in true }
            + regexMatches(in: text, pattern: Self.cardPattern, kind: .card) { _ in true }).map(\.range)
        result += dataDetectorMatches(in: text).filter { m in
            m.kind != .phone || !ibanOrCardShapes.contains { $0.overlaps(m.range) }
        }
        result += regexMatches(in: text, pattern: Self.ibanPattern, kind: .iban) { Self.isValidIBAN($0) }
        result += regexMatches(in: text, pattern: Self.cardPattern, kind: .card) { Self.passesLuhn($0) }
        for p in Self.secretPatterns {
            result += regexMatches(in: text, pattern: p, kind: .secret) { _ in true }
        }
        return Self.removingOverlaps(result).sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    static let ibanPattern = #"\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]{4}){2,7}(?: ?[A-Z0-9]{1,3})?\b"#
    static let cardPattern = #"\b(?:\d[ -]?){13,19}\b"#

    static let secretPatterns = [
        #"\bsk-[A-Za-z0-9_-]{20,}"#,
        #"\bgh[pousr]_[A-Za-z0-9]{30,}"#,
        #"\bAKIA[0-9A-Z]{16}\b"#,
        #"\bxox[abprs]-[A-Za-z0-9-]{10,}"#,
        #"\b[A-Fa-f0-9]{40,}\b"#
    ]

    private func dataDetectorMatches(in text: String) -> [SensitiveMatch] {
        let types: NSTextCheckingResult.CheckingType = [.link, .phoneNumber]
        guard let detector = try? NSDataDetector(types: types.rawValue) else {
            assertionFailure("NSDataDetector unavailable")
            return []
        }
        let ns = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: ns).compactMap { r in
            guard let range = Range(r.range, in: text) else { return nil }
            if r.resultType == .phoneNumber { return SensitiveMatch(kind: .phone, range: range) }
            if r.resultType == .link, r.url?.scheme == "mailto" { return SensitiveMatch(kind: .email, range: range) }
            return nil
        }
    }

    private func regexMatches(in text: String, pattern: String, kind: SensitiveMatch.Kind,
                              accept: (String) -> Bool) -> [SensitiveMatch] {
        guard let re = try? NSRegularExpression(pattern: pattern) else {
            assertionFailure("Bad pattern \(pattern)")
            return []
        }
        let ns = NSRange(text.startIndex..., in: text)
        return re.matches(in: text, range: ns).compactMap { m in
            guard let range = Range(m.range, in: text), accept(String(text[range])) else { return nil }
            return SensitiveMatch(kind: kind, range: range)
        }
    }

    static func isValidIBAN(_ raw: String) -> Bool {
        let s = raw.replacingOccurrences(of: " ", with: "").uppercased()
        guard (15...34).contains(s.count) else { return false }
        let rearranged = s.dropFirst(4) + s.prefix(4)
        var remainder = 0
        for ch in rearranged {
            let v: Int
            if let d = ch.wholeNumberValue { v = d }
            else if let a = ch.asciiValue, (65...90).contains(a) { v = Int(a) - 55 }
            else { return false }
            for digit in String(v) { remainder = (remainder * 10 + (digit.wholeNumberValue ?? 0)) % 97 }
        }
        return remainder == 1
    }

    static func passesLuhn(_ raw: String) -> Bool {
        let digits = raw.compactMap(\.wholeNumberValue)
        guard (13...19).contains(digits.count) else { return false }
        var sum = 0
        for (i, d) in digits.reversed().enumerated() {
            if i % 2 == 1 { let x = d * 2; sum += x > 9 ? x - 9 : x } else { sum += d }
        }
        return sum % 10 == 0
    }

    /// Überlappende Treffer: höhere Priorität gewinnt (Schlüssel vor IBAN vor Karte vor E-Mail vor Telefon).
    static func removingOverlaps(_ items: [SensitiveMatch]) -> [SensitiveMatch] {
        let priority: [SensitiveMatch.Kind: Int] = [.secret: 0, .iban: 1, .card: 2, .email: 3, .phone: 4]
        let sorted = items.sorted {
            let pa = priority[$0.kind] ?? 9, pb = priority[$1.kind] ?? 9
            if pa != pb { return pa < pb }
            return $0.range.lowerBound < $1.range.lowerBound
        }
        var kept: [SensitiveMatch] = []
        for m in sorted where !kept.contains(where: { $0.range.overlaps(m.range) }) { kept.append(m) }
        return kept
    }
}

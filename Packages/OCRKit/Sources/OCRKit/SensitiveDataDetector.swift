import CoreGraphics
import Foundation

public struct SensitiveMatch: Equatable, Sendable {
    public enum Kind: String, Sendable, Codable { case email, phone, iban, card, secret, face }
    public let kind: Kind
    public let range: Range<String.Index>
    /// False for IBAN/card-shaped text whose checksum failed or couldn't be checked
    /// (e.g. an IBAN cut off at line end). Still a suggestion: the user deselects.
    public let isVerified: Bool

    public init(kind: Kind, range: Range<String.Index>, isVerified: Bool = true) {
        self.kind = kind
        self.range = range
        self.isVerified = isVerified
    }
}

/// A sensitive match located in an image.
public struct SensitiveRegion: Sendable, Equatable {
    public let kind: SensitiveMatch.Kind
    /// The matched text, for in-process use only. Never persist or log it;
    /// regions coming back from the OCR helper process carry an empty string.
    public let text: String
    /// Image pixels, top-left origin (like `TextRegion.boundingBox`).
    public let boundingBox: CGRect
    public let isVerified: Bool

    public init(kind: SensitiveMatch.Kind, text: String, boundingBox: CGRect, isVerified: Bool) {
        self.kind = kind
        self.text = text
        self.boundingBox = boundingBox
        self.isVerified = isVerified
    }
}

/// Findet vertrauliche Angaben in erkanntem Text (Knippi-Spec §7.1).
///
/// Suggestions are user-deselectable, so the detector errs on the side of
/// over-redaction: a missed secret is a privacy bug, an extra box is not.
public struct SensitiveDataDetector: Sendable {
    public init() {}

    public func matches(in text: String) -> [SensitiveMatch] {
        var result: [SensitiveMatch] = []
        result += dataDetectorMatches(in: text)
        result += regexMatches(in: text, pattern: Self.ibanPattern, kind: .iban, options: .caseInsensitive)
            .map { SensitiveMatch(kind: .iban, range: $0.range, isVerified: Self.isValidIBAN(String(text[$0.range]))) }
        result += regexMatches(in: text, pattern: Self.ibanAtLineEndPattern, kind: .iban,
                               options: [.caseInsensitive, .anchorsMatchLines])
            .map { SensitiveMatch(kind: .iban, range: $0.range, isVerified: false) }
        result += cardMatches(in: text)
        for p in Self.secretPatterns {
            result += regexMatches(in: text, pattern: p, kind: .secret)
        }
        result += regexMatches(in: text, pattern: Self.shortHexPattern, kind: .secret) { Self.isMixedHex($0) }
        result += regexMatches(in: text, pattern: Self.genericTokenPattern, kind: .secret) { Self.isMixedToken($0) }
        result += keywordValueMatches(in: text)
        return Self.removingOverlaps(result).sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// A hit that ends at the end of its OCR line may continue on the next line
    /// (wrapped token, IBAN or card number). Returns the continuation in `nextLine`
    /// as an unverified match of the same kind, or nil.
    ///
    /// Secrets continue with the first word of the next line when it looks like a
    /// token piece (token characters, 4+, with a digit or one of `+/_=-`), so an
    /// ordinary following word ("Bitte …") stays visible. IBAN and card continue
    /// only when the hit itself is unverified (cut off), with the leading groups.
    public func continuation(of match: SensitiveMatch, in line: String, nextLine: String) -> SensitiveMatch? {
        guard line[match.range.upperBound...].allSatisfy({ $0 == " " || $0 == "\t" }) else { return nil }
        let pattern: String
        switch match.kind {
        case .secret: pattern = Self.secretContinuationPattern
        case .iban where !match.isVerified: pattern = Self.ibanContinuationPattern
        case .card where !match.isVerified: pattern = Self.cardContinuationPattern
        default: return nil
        }
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = re.firstMatch(in: nextLine, range: NSRange(nextLine.startIndex..., in: nextLine)),
              let range = Range(m.range(at: 1), in: nextLine) else { return nil }
        let piece = nextLine[range]
        if match.kind == .secret, !piece.contains(where: { $0.isNumber || "+/_=-".contains($0) }) { return nil }
        if match.kind == .iban, !piece.contains(where: \.isNumber) { return nil }
        return SensitiveMatch(kind: match.kind, range: range, isVerified: false)
    }

    static let ibanPattern = #"\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]{4}){2,7}(?: ?[A-Z0-9]{1,3})?\b"#
    /// IBAN start at the end of a line: the rest is on the next OCR line, so no checksum.
    /// One group is enough ("IBAN: DE89 3704" wraps after the bank code).
    static let ibanAtLineEndPattern = #"\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]{4}){1,}(?=[ \t]*$)"#
    /// Digit groups for card detection; groups joined by one space or dash form a run.
    static let digitGroupPattern = #"\d+"#
    static let genericTokenPattern = #"[A-Za-z0-9+/_-]{20,}={0,2}"#
    /// Short hex keys (16–39 chars); 40+ is covered by the plain hex pattern below.
    static let shortHexPattern = #"\b[A-Fa-f0-9]{16,39}\b"#
    /// Keyword followed by ":" or "=": the rest of the line is the value
    /// ("Passwort: Sommer2026!", "API-Key: 7f3a…", "PIN = 1234"). Group 1 is the value.
    static let keywordValuePattern = #"\b(?:passwor[dt]|passwd|pwd|kennwort|passphrase|token|secret|geheimnis|api[ _-]?key|access[ _-]?key|secret[ _-]?key|private[ _-]?key|key|schl(?:ü|ue)ssel|pin|puk|code|otp|tan)\b[ \t]*[:=][ \t]*(\S[^\n]*?)[ \t]*$"#
    /// Continuations at the start of the next OCR line; group 1 is the piece.
    static let secretContinuationPattern = #"^[ \t]*([A-Za-z0-9+/_=-]{4,})(?=\s|$)"#
    static let ibanContinuationPattern = #"^[ \t]*([A-Z0-9]{1,4}(?: [A-Z0-9]{1,4}){0,7})\b"#
    static let cardContinuationPattern = #"^[ \t]*(\d+(?:[ -]\d+)*)\b"#

    static let secretPatterns = [
        #"\bsk-[A-Za-z0-9_-]{20,}"#,
        #"\b(?:sk|rk)_(?:live|test)_[A-Za-z0-9]{16,}"#,
        #"\bgh[pousr]_[A-Za-z0-9]{30,}"#,
        #"\bAKIA[0-9A-Z]{16}\b"#,
        #"\bAIza[0-9A-Za-z_-]{35}"#,
        #"\beyJ[\w-]+\.[\w-]+\.[\w-]+"#,
        #"\bxox[abprs]-[A-Za-z0-9-]{10,}"#,
        #"\b[A-Fa-f0-9]{40,}\b"#
    ]

    static var allPatterns: [String] {
        [ibanPattern, ibanAtLineEndPattern, digitGroupPattern, genericTokenPattern, shortHexPattern,
         keywordValuePattern, secretContinuationPattern, ibanContinuationPattern, cardContinuationPattern]
            + secretPatterns
    }

    /// Values behind a keyword are unverified (heuristic): a specific secret pattern
    /// inside the value stays the verified hit, the whole value is still covered.
    private func keywordValueMatches(in text: String) -> [SensitiveMatch] {
        guard let re = try? NSRegularExpression(pattern: Self.keywordValuePattern,
                                                options: [.caseInsensitive, .anchorsMatchLines]) else {
            assertionFailure("Bad keyword pattern")
            return []
        }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { m in
            guard let range = Range(m.range(at: 1), in: text) else { return nil }
            return SensitiveMatch(kind: .secret, range: range, isVerified: false)
        }
    }

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
                              options: NSRegularExpression.Options = [],
                              accept: (String) -> Bool = { _ in true }) -> [SensitiveMatch] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else {
            assertionFailure("Bad pattern \(pattern)")
            return []
        }
        let ns = NSRange(text.startIndex..., in: text)
        return re.matches(in: text, range: ns).compactMap { m in
            guard let range = Range(m.range, in: text), accept(String(text[range])) else { return nil }
            return SensitiveMatch(kind: kind, range: range)
        }
    }

    /// Card numbers: digit groups joined by single spaces/dashes form runs. Every
    /// contiguous sub-run of 13–19 digits passing Luhn is a verified card (longest
    /// first, non-overlapping), so neighbouring numbers ("Nr 12 …", "… 12/28") don't
    /// hide it. A run with 13+ digits and no Luhn hit is reported unverified.
    private func cardMatches(in text: String) -> [SensitiveMatch] {
        let groups = regexMatches(in: text, pattern: Self.digitGroupPattern, kind: .card).map(\.range)
        var runs: [[Range<String.Index>]] = []
        for group in groups {
            if let previous = runs.last?.last, Self.isSingleSeparator(text[previous.upperBound..<group.lowerBound]) {
                runs[runs.count - 1].append(group)
            } else {
                runs.append([group])
            }
        }

        var result: [SensitiveMatch] = []
        for run in runs {
            let counts = run.map { text.distance(from: $0.lowerBound, to: $0.upperBound) }
            var candidates: [(range: Range<String.Index>, digits: Int)] = []
            for i in run.indices {
                var digits = 0
                for j in i..<run.count {
                    digits += counts[j]
                    if digits > 19 { break }
                    if digits >= 13 { candidates.append((run[i].lowerBound..<run[j].upperBound, digits)) }
                }
            }
            guard !candidates.isEmpty else {
                // A card number wrapped onto the next line: its first 8–12 digits end this
                // line ("Visa 4111 1111 1111"). Groups of 3+ digits keep dates like 2026-11-20 out.
                let digits = counts.reduce(0, +)
                let atLineEnd = text[run[run.count - 1].upperBound...].allSatisfy { $0 == " " || $0 == "\t" }
                if (8...12).contains(digits), counts.allSatisfy({ $0 >= 3 }), atLineEnd {
                    result.append(SensitiveMatch(kind: .card, range: run[0].lowerBound..<run[run.count - 1].upperBound,
                                                 isVerified: false))
                }
                continue
            }
            var verified: [Range<String.Index>] = []
            for c in candidates.sorted(by: { $0.digits > $1.digits })
            where Self.passesLuhn(String(text[c.range])) && !verified.contains(where: { $0.overlaps(c.range) }) {
                verified.append(c.range)
            }
            if verified.isEmpty {
                result.append(SensitiveMatch(kind: .card, range: run[0].lowerBound..<run[run.count - 1].upperBound,
                                             isVerified: false))
            } else {
                result += verified.map { SensitiveMatch(kind: .card, range: $0) }
            }
        }
        return result
    }

    private static func isSingleSeparator(_ s: Substring) -> Bool {
        s == " " || s == "-"
    }

    /// Generic base64/base64url tokens: only with digit, lower- and uppercase letter,
    /// so long ordinary words don't qualify.
    static func isMixedToken(_ s: String) -> Bool {
        s.contains(where: \.isNumber) && s.contains(where: \.isLowercase) && s.contains(where: \.isUppercase)
    }

    /// Short hex keys need a digit and a letter, so plain numbers and words like
    /// "deadbeefcafebabe…" without digits don't qualify.
    static func isMixedHex(_ s: String) -> Bool {
        s.contains(where: \.isNumber) && s.contains(where: \.isLetter)
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

    /// Überlappende Treffer (ein Treffer fällt nur weg, wenn ein behaltener ihn ganz enthält),
    /// Rangfolge: verifizierte vor unverifizierten, dann Schlüssel vor IBAN
    /// vor Karte vor E-Mail vor Telefon, dann der frühere, bei gleichem Start der längere.
    static func removingOverlaps(_ items: [SensitiveMatch]) -> [SensitiveMatch] {
        let priority: [SensitiveMatch.Kind: Int] = [.secret: 0, .iban: 1, .card: 2, .email: 3, .phone: 4]
        let sorted = items.sorted {
            if $0.isVerified != $1.isVerified { return $0.isVerified }
            let pa = priority[$0.kind] ?? 9, pb = priority[$1.kind] ?? 9
            if pa != pb { return pa < pb }
            if $0.range.lowerBound != $1.range.lowerBound { return $0.range.lowerBound < $1.range.lowerBound }
            return $0.range.upperBound > $1.range.upperBound
        }
        var kept: [SensitiveMatch] = []
        // Only drop a hit that a kept one covers completely: a partly overlapping
        // loser still hides characters the winner leaves visible (over-redact).
        for m in sorted where !kept.contains(where: {
            $0.range.lowerBound <= m.range.lowerBound && $0.range.upperBound >= m.range.upperBound
        }) { kept.append(m) }
        return kept
    }
}

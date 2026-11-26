import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import OCRKit

@Suite("Sensitive data detector")
struct SensitiveDataDetectorTests {
    let d = SensitiveDataDetector()

    @Test func email() { #expect(d.matches(in: "Kontakt: max.muster@example.org bitte").map(\.kind) == [.email]) }
    @Test func phoneDE() { #expect(d.matches(in: "Tel. +49 89 1234567").map(\.kind) == [.phone]) }
    @Test func phoneDEWithoutCountryCode() { #expect(d.matches(in: "Tel. 089 1234567").map(\.kind) == [.phone]) }
    @Test func ibanValid() { #expect(d.matches(in: "IBAN DE89 3704 0044 0532 0130 00").map(\.kind) == [.iban]) }
    @Test func ibanValidIsVerified() { #expect(d.matches(in: "IBAN DE89 3704 0044 0532 0130 00").map(\.isVerified) == [true]) }
    @Test func ibanLowercase() {
        let m = d.matches(in: "de89 3704 0044 0532 0130 00")
        #expect(m.map(\.kind) == [.iban])
        #expect(m.map(\.isVerified) == [true])
    }
    /// Checksum failure: never a verified IBAN, but still suggested (phone or unverified hit).
    @Test func ibanInvalidChecksum() {
        let m = d.matches(in: "DE00 3704 0044 0532 0130 00")
        #expect(!m.contains { $0.kind == .iban && $0.isVerified })
        #expect(!m.isEmpty)
    }
    /// An IBAN broken across OCR lines: the start at line end is an unverified suggestion.
    @Test func ibanStartAtLineEnd() throws {
        let s = "Konto DE89 3704 0044"
        let m = try #require(d.matches(in: s).first { $0.kind == .iban })
        #expect(!m.isVerified)
        #expect(String(s[m.range]) == "DE89 3704 0044")
    }
    @Test func cardLuhn() { #expect(d.matches(in: "Karte 4111 1111 1111 1111").map(\.kind) == [.card]) }
    @Test func cardBadLuhn() {
        let m = d.matches(in: "4111 1111 1111 1112")
        #expect(!m.contains { $0.kind == .card && $0.isVerified })
        #expect(!m.isEmpty)
    }
    @Test func cardFollowedByExpiry() { #expect(verifiedText(.card, in: "4111 1111 1111 1111 12/28") == "4111 1111 1111 1111") }
    @Test func cardPrecededByNumber() { #expect(verifiedText(.card, in: "Nr 12 4111 1111 1111 1111") == "4111 1111 1111 1111") }
    @Test func mobilePhone() { #expect(covered("+49 151 23456789", in: "+49 151 23456789")) }
    @Test func longLandline() { #expect(covered("+49 89 123456789", in: "+49 89 123456789")) }
    @Test func twoPhones() {
        let s = "089 1234567 089 7654321"
        #expect(covered("1234567", in: s))
        #expect(covered("7654321", in: s))
    }
    @Test func apiKeys() {
        let openAI = "sk-" + "proj-" + String(repeating: "a", count: 24)
        let github = "gh" + "p_" + String(repeating: "b", count: 36)
        let aws = "AK" + "IA" + String(repeating: "C", count: 16)
        let kinds = d.matches(in: "\(openAI) \(github) \(aws)").map(\.kind)
        #expect(kinds == [.secret, .secret, .secret])
    }
    @Test func moreSecrets() {
        let mixed = String(repeating: "aB3x", count: 6)                    // 24 chars
        let stripe = "sk" + "_live_" + mixed
        let google = "AI" + "za" + String(repeating: "Xy7_", count: 8) + "abc" // 35 after prefix
        let jwt = "ey" + "J" + "hbGciOiJIUzI1NiJ9" + "." + "ey" + "JzdWIiOiIxIn0" + "." + "c2lnbmF0dXJl"
        let generic = String(repeating: "Qw9z", count: 9)                   // 36 chars
        for token in [stripe, google, jwt, generic] {
            let s = "Token: \(token) Ende"
            #expect(verifiedText(.secret, in: s) == token, "\(token)")
        }
    }
    @Test func longGermanTextIsNotASecret() {
        #expect(d.matches(in: "Donaudampfschifffahrtsgesellschaftskapitaensmuetzenabzeichen").isEmpty)
        #expect(d.matches(in: "Die Rindfleischetikettierungsueberwachungsaufgabenuebertragungsgesetze gelten seit 2026").isEmpty)
    }
    @Test func detectorsAreVerified() {
        let m = d.matches(in: "a@b.de Tel. 089 1234567")
        #expect(m.map(\.kind) == [.email, .phone])
        #expect(m.allSatisfy { $0.isVerified })
    }
    @Test func allPatternsCompile() throws {
        #expect(!SensitiveDataDetector.allPatterns.isEmpty)
        for pattern in SensitiveDataDetector.allPatterns {
            #expect((try? NSRegularExpression(pattern: pattern)) != nil, "\(pattern)")
        }
    }
    @Test func rangesPointAtMatch() throws {
        let s = "Mail: a@b.de"
        let m = try #require(d.matches(in: s).first)
        #expect(String(s[m.range]) == "a@b.de")
    }
    @Test func plainTextHasNoMatches() { #expect(d.matches(in: "Willkommen bei Knippi 2026").isEmpty) }
    @Test func dateAndOrderNumberAreNotFlagged() { #expect(d.matches(in: "Bestellung 2026-11-20 Nr. 4711").isEmpty) }

    // A card number or IBAN wrapped onto the next OCR line: the first part is suggested unverified.
    @Test func cardStartAtLineEnd() throws {
        let m = try #require(d.matches(in: "Visa 4111 1111 1111").first)
        #expect(m.kind == .card)
        #expect(!m.isVerified)
        #expect(String("Visa 4111 1111 1111"[m.range]) == "4111 1111 1111")
    }
    @Test func cardStartWithoutGroupsAtLineEnd() {
        #expect(d.matches(in: "Karte 411111111111").map(\.kind) == [.card])
    }
    @Test func shortIbanStartAtLineEnd() throws {
        let m = try #require(d.matches(in: "IBAN: DE89 3704").first { $0.kind == .iban })
        #expect(!m.isVerified)
    }
    @Test func dateAtLineEndIsNotACard() { #expect(d.matches(in: "Stand 2026-11-20").isEmpty) }
    @Test func digitsMidLineAreNotACardStart() {
        #expect(!d.matches(in: "4111 1111 1111 Stück").contains { $0.kind == .card })
    }

    // Keyword values, short keys and secrets wrapped onto the next OCR line.
    @Test func passwordBehindKeyword() {
        #expect(covered("Sommer2026!", in: "Passwort: Sommer2026!"))
        #expect(!covered("Passwort", in: "Passwort: Sommer2026!"))
    }
    @Test func shortApiKeyBehindKeyword() { #expect(covered("7f3a9c2e1b4d8f6a0c5e", in: "API-Key: 7f3a9c2e1b4d8f6a0c5e")) }
    @Test func pinBehindKeyword() { #expect(covered("4821", in: "PIN = 4821")) }
    @Test func keywordValueCoversRestOfLine() { #expect(covered("geheim wort", in: "Kennwort: geheim wort  ")) }
    @Test func shortHexKeyWithoutKeyword() {
        #expect(verifiedText(.secret, in: "Schlüssel 7f3a9c2e1b4d8f6a0c5e hier") == "7f3a9c2e1b4d8f6a0c5e")
    }
    @Test func plainLongNumberIsNotAHexKey() { #expect(d.matches(in: "Auftrag 1234567890123456789 ok").allSatisfy { $0.kind != .secret }) }
    @Test func tokenWrappedOntoNextLine() throws {
        let line = "token: " + "gh" + "p_ABCDEFGHIJKLMNOPQRSTUV"
        let next = "WXYZ0123456789abcdef"
        #expect(covered("gh" + "p_ABCDEFGHIJKLMNOPQRSTUV", in: line))
        let last = try #require(d.matches(in: line).last)
        let rest = try #require(d.continuation(of: last, in: line, nextLine: next))
        #expect(rest.kind == .secret)
        #expect(String(next[rest.range]) == next)
    }
    @Test func ordinaryWordAfterSecretStaysVisible() throws {
        let line = "Passwort: Sommer2026!"
        let last = try #require(d.matches(in: line).last)
        #expect(d.continuation(of: last, in: line, nextLine: "Bitte nach dem Login ändern") == nil)
    }
    @Test func cardWrappedOntoNextLine() throws {
        let line = "Visa 4111 1111 1111"
        let next = "1111 gültig bis 12/28"
        let first = try #require(d.matches(in: line).first)
        let rest = try #require(d.continuation(of: first, in: line, nextLine: next))
        #expect(String(next[rest.range]) == "1111")
    }
    @Test func ibanWrappedOntoNextLine() throws {
        let line = "IBAN DE89 3704 0044"
        let next = "0532 0130 00"
        let first = try #require(d.matches(in: line).first { $0.kind == .iban })
        let rest = try #require(d.continuation(of: first, in: line, nextLine: next))
        #expect(String(next[rest.range]) == "0532 0130 00")
    }
    @Test func hitMidLineHasNoContinuation() throws {
        let line = "Karte 4111 1111 1111 1111 ok"
        let first = try #require(d.matches(in: line).first)
        #expect(d.continuation(of: first, in: line, nextLine: "1234") == nil)
    }
    @Test func nextLineIsTheOneDirectlyBelow() {
        // Vision-normalized, bottom-left origin: 0 = top line, 1 = far below, 2 = directly below, 3 = other column.
        let boxes = [CGRect(x: 0.1, y: 0.80, width: 0.5, height: 0.05),
                     CGRect(x: 0.1, y: 0.50, width: 0.5, height: 0.05),
                     CGRect(x: 0.1, y: 0.73, width: 0.3, height: 0.05),
                     CGRect(x: 0.7, y: 0.73, width: 0.2, height: 0.05)]
        #expect(TextRecognizer.nextLineIndex(after: 0, boxes: boxes) == 2)
        #expect(TextRecognizer.nextLineIndex(after: 1, boxes: boxes) == nil)
    }

    private func verifiedText(_ kind: SensitiveMatch.Kind, in s: String) -> String? {
        d.matches(in: s).first { $0.kind == kind && $0.isVerified }.map { String(s[$0.range]) }
    }
    /// True when every character of `needle` in `s` lies inside some match.
    private func covered(_ needle: String, in s: String) -> Bool {
        guard let r = s.range(of: needle) else { return false }
        let ms = d.matches(in: s)
        return s[r].indices.allSatisfy { i in ms.contains { $0.range.contains(i) } }
    }
}

@Suite("Sensitive regions (Vision)")
struct SensitiveRegionsTests {
    /// 600×80, black "mail a@b.de" on white, 32 pt.
    static func renderTestImage() throws -> CGImage {
        let width = 600, height = 80
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica" as CFString, 32, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "mail a@b.de", attributes: attributes))
        // Place the line so "mail " is left of the midline and the address starts
        // at x = 320: a whole-line box would cross the midline, a tight one doesn't.
        let emailOffset = CTLineGetOffsetForStringIndex(line, 5, nil)
        context.textPosition = CGPoint(x: 320 - emailOffset, y: 28)
        CTLineDraw(line, context)
        return try #require(context.makeImage())
    }

    @Test func emailRegionIsTight() async throws {
        let image = try Self.renderTestImage()
        let regions: [SensitiveRegion]
        do {
            regions = try await TextRecognizer.sensitiveRegions(image: image)
        } catch {
            // Vision may be unusable in this environment (macOS-27 TextRecognition
            // fault, see OCRProcessFallback); don't fail the logic suite for it.
            withKnownIssue("Vision unavailable: \(error.localizedDescription)") { throw error }
            return
        }
        #expect(regions.map(\.kind) == [.email])
        let box = try #require(regions.first?.boundingBox)
        #expect(box.minX > 300, "box \(box) should lie in the right half")
        #expect(box.height < 80)
    }
}

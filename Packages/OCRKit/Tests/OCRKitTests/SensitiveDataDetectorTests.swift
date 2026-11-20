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
    @Test func ibanInvalidChecksum() { #expect(d.matches(in: "DE00 3704 0044 0532 0130 00").isEmpty) }
    @Test func cardLuhn() { #expect(d.matches(in: "Karte 4111 1111 1111 1111").map(\.kind) == [.card]) }
    @Test func cardBadLuhn() { #expect(d.matches(in: "4111 1111 1111 1112").isEmpty) }
    @Test func apiKeys() {
        let openAI = "sk-" + "proj-" + String(repeating: "a", count: 24)
        let github = "gh" + "p_" + String(repeating: "b", count: 36)
        let aws = "AK" + "IA" + String(repeating: "C", count: 16)
        let kinds = d.matches(in: "\(openAI) \(github) \(aws)").map(\.kind)
        #expect(kinds == [.secret, .secret, .secret])
    }
    @Test func rangesPointAtMatch() throws {
        let s = "Mail: a@b.de"
        let m = try #require(d.matches(in: s).first)
        #expect(String(s[m.range]) == "a@b.de")
    }
    @Test func plainTextHasNoMatches() { #expect(d.matches(in: "Willkommen bei Knippi 2026").isEmpty) }
    @Test func dateAndOrderNumberAreNotFlagged() { #expect(d.matches(in: "Bestellung 2026-11-20 Nr. 4711").isEmpty) }
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

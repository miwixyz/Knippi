import CoreGraphics
import Testing
@testable import OCRKit

@Suite("Redaction rects from sensitive regions")
struct SensitiveRedactionTests {
    let size = CGSize(width: 400, height: 200)

    func region(_ rect: CGRect, _ kind: SensitiveMatch.Kind = .email, verified: Bool = true) -> SensitiveRegion {
        SensitiveRegion(kind: kind, text: "", boundingBox: rect, isVerified: verified)
    }

    @Test func padsEachBox() {
        let rects = redactionRects(from: [region(CGRect(x: 100, y: 50, width: 40, height: 10))], imageSize: size)
        #expect(rects == [CGRect(x: 96, y: 47, width: 48, height: 16)])
    }

    @Test func overlappingRegionsMergeIntoUnion() {
        let rects = redactionRects(from: [
            region(CGRect(x: 100, y: 50, width: 60, height: 10), .iban),
            region(CGRect(x: 130, y: 52, width: 60, height: 10), .phone)
        ], imageSize: size)
        #expect(rects == [CGRect(x: 96, y: 47, width: 98, height: 18)])
    }

    @Test func touchingPaddedBoxesMerge() {
        // 8 px gap closes after padding by 4 on both sides.
        let rects = redactionRects(from: [
            region(CGRect(x: 10, y: 10, width: 20, height: 10)),
            region(CGRect(x: 38, y: 10, width: 20, height: 10))
        ], imageSize: size)
        #expect(rects.count == 1)
    }

    @Test func disjointRegionsStaySeparate() {
        let rects = redactionRects(from: [
            region(CGRect(x: 10, y: 10, width: 20, height: 10)),
            region(CGRect(x: 200, y: 100, width: 20, height: 10))
        ], imageSize: size)
        #expect(rects.count == 2)
    }

    @Test func mergeRepeatsUntilStable() {
        // A and C don't touch, but B bridges them only after A∪B grows.
        let rects = redactionRects(from: [
            region(CGRect(x: 10, y: 10, width: 20, height: 10)),
            region(CGRect(x: 100, y: 10, width: 20, height: 10)),
            region(CGRect(x: 25, y: 12, width: 80, height: 6))
        ], imageSize: size)
        #expect(rects.count == 1)
    }

    @Test func clampsToImage() {
        let rects = redactionRects(from: [region(CGRect(x: 1, y: 195, width: 20, height: 5))], imageSize: size)
        #expect(rects == [CGRect(x: 0, y: 192, width: 25, height: 8)])
    }

    @Test func dropsBoxesOutsideImage() {
        let rects = redactionRects(from: [region(CGRect(x: 500, y: 500, width: 20, height: 5))], imageSize: size)
        #expect(rects.isEmpty)
    }

    @Test func mergedSuggestionIsUnverifiedOnlyIfAllPartsAre() {
        let mixed = redactionSuggestions(from: [
            region(CGRect(x: 100, y: 50, width: 60, height: 10), .iban, verified: false),
            region(CGRect(x: 130, y: 52, width: 60, height: 10), .phone, verified: true)
        ], imageSize: size)
        #expect(mixed.map(\.isVerified) == [true])

        let unverified = redactionSuggestions(from: [
            region(CGRect(x: 100, y: 50, width: 60, height: 10), .card, verified: false)
        ], imageSize: size)
        #expect(unverified.map(\.isVerified) == [false])
    }
}

import Foundation
import CoreGraphics
import Testing
@testable import OCRKit

@Suite("Gesichtssuche: Planung, Duplikate, Rahmen")
struct FaceDetectorTests {
    // MARK: Streifen

    @Test func normalImageIsOneWindow() {
        #expect(FaceDetector.searchWindows(width: 2940, height: 1912) == [CGRect(x: 0, y: 0, width: 2940, height: 1912)])
        #expect(FaceDetector.searchWindows(width: 8000, height: 8000).count == 1)
    }

    @Test func tallImageIsCutIntoOverlappingStrips() {
        let windows = FaceDetector.searchWindows(width: 1513, height: 30439)
        #expect(windows.count > 10)
        #expect(windows.allSatisfy { $0.width == 1513 && $0.height <= 2000 })
        #expect(windows.first?.minY == 0)
        #expect(windows.last?.maxY == 30439)
        // Überlappung: jedes Fenster beginnt vor dem Ende des vorigen, nichts bleibt ungeprüft.
        for (a, b) in zip(windows, windows.dropFirst()) { #expect(b.minY < a.maxY) }
    }

    @Test func wideImageGetsStripsAlongX() {
        let windows = FaceDetector.searchWindows(width: 12000, height: 900)
        #expect(windows.count > 5)
        #expect(windows.allSatisfy { $0.height == 900 })
        #expect(windows.last?.maxX == 12000)
    }

    // MARK: Kacheln

    @Test func tilesCoverTheImageWithOverlap() {
        let starts = FaceDetector.tileStarts(length: 1920)
        #expect(starts.first == 0)
        #expect(starts.last == 1920 - 640)
        for (a, b) in zip(starts, starts.dropFirst()) { #expect(b - a <= 640 - 100) }
        #expect(FaceDetector.tileStarts(length: 300) == [0])
    }

    @Test func tileCountMatchesProbe() {
        // Gemessen in A0c: 1920×1080 = 8 Kacheln, 1965×1217 = 12, 3440×1440 = 24, 2940×1912 = 28.
        #expect(FaceDetector.tileRects(width: 1920, height: 1080).count == 8)
        #expect(FaceDetector.tileRects(width: 1965, height: 1217).count == 12)
        #expect(FaceDetector.tileRects(width: 3440, height: 1440).count == 24)
        #expect(FaceDetector.tileRects(width: 2940, height: 1912).count == 28)
        #expect(FaceDetector.tileRects(width: 1513, height: 30439).count > FaceDetector.maxTiles)
    }

    // MARK: Duplikate

    private func face(_ r: CGRect, _ c: Float = 0.9) -> FaceDetector.Face { .init(rect: r, confidence: c) }

    @Test func sameFaceFromTwoSearchesIsOne() {
        let out = FaceDetector.deduplicated([
            face(CGRect(x: 100, y: 100, width: 80, height: 80), 0.6),
            face(CGRect(x: 104, y: 98, width: 78, height: 82), 0.9),
        ])
        #expect(out.count == 1)
        #expect(out[0].confidence == 0.9)
    }

    @Test func doubleFrameBelowAFaceIsDropped() {
        // Panem-Plakat (25.11.): zweiter Rahmen auf Brust/Kragen unter einem echten Gesicht.
        let out = FaceDetector.deduplicated([
            face(CGRect(x: 100, y: 100, width: 100, height: 100)),
            face(CGRect(x: 120, y: 190, width: 60, height: 50), 0.7),
        ])
        #expect(out.count == 1)
    }

    @Test func neighbouringFacesStaySeparate() {
        let out = FaceDetector.deduplicated([
            face(CGRect(x: 100, y: 100, width: 100, height: 100)),
            face(CGRect(x: 215, y: 110, width: 90, height: 90)),
            face(CGRect(x: 100, y: 330, width: 100, height: 100)),
        ])
        #expect(out.count == 3)
    }

    // MARK: Vorschläge

    @Test func faceBoxIsEnlargedProportionally() {
        let size = CGSize(width: 1000, height: 1000)
        let box = CGRect(x: 400, y: 400, width: 100, height: 100)
        let s = redactionSuggestions(
            from: [SensitiveRegion(kind: .face, text: "", boundingBox: box, isVerified: true)], imageSize: size)
        #expect(s.count == 1)
        #expect(s[0].isFace)
        #expect(s[0].rect == CGRect(x: 360, y: 330, width: 180, height: 205))
    }

    @Test func faceIsClampedToImage() {
        let s = redactionSuggestions(
            from: [SensitiveRegion(kind: .face, text: "", boundingBox: CGRect(x: 5, y: 5, width: 100, height: 100),
                                   isVerified: true)],
            imageSize: CGSize(width: 300, height: 300))
        #expect(s[0].rect.minX == 0 && s[0].rect.minY == 0)
    }

    @Test func faceNeverMergesWithText() {
        let size = CGSize(width: 800, height: 400)
        let text = SensitiveRegion(kind: .email, text: "", boundingBox: CGRect(x: 100, y: 100, width: 200, height: 20),
                                   isVerified: true)
        let face = SensitiveRegion(kind: .face, text: "", boundingBox: CGRect(x: 180, y: 90, width: 80, height: 80),
                                   isVerified: true)
        let s = redactionSuggestions(from: [text, face], imageSize: size)
        #expect(s.count == 2)
        #expect(s.filter(\.isFace).count == 1)
        #expect(s.filter { !$0.isFace }.first?.rect == CGRect(x: 96, y: 97, width: 208, height: 26))
    }

    @Test func facesDoNotMergeWithEachOther() {
        let size = CGSize(width: 800, height: 400)
        let a = SensitiveRegion(kind: .face, text: "", boundingBox: CGRect(x: 100, y: 100, width: 80, height: 80), isVerified: true)
        let b = SensitiveRegion(kind: .face, text: "", boundingBox: CGRect(x: 190, y: 100, width: 80, height: 80), isVerified: false)
        let s = redactionSuggestions(from: [a, b], imageSize: size)
        #expect(s.count == 2)
        #expect(s.map(\.isVerified) == [true, false])
    }

    @Test func faceKindSurvivesJSON() throws {
        let data = try JSONEncoder().encode([SensitiveMatch.Kind.face, .email])
        #expect(try JSONDecoder().decode([SensitiveMatch.Kind].self, from: data) == [.face, .email])
    }
}

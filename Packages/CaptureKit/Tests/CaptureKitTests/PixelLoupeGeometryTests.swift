import CoreGraphics
import Testing
@testable import CaptureKit

@Suite("Pixel loupe geometry")
struct PixelLoupeGeometryTests {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let size = CGSize(width: 132, height: 156)

    @Test func placesBelowRightOfCursorByDefault() {
        let origin = PixelLoupeGeometry.loupeOrigin(cursor: CGPoint(x: 500, y: 400), loupeSize: size, bounds: bounds)
        #expect(origin == CGPoint(x: 524, y: 400 - 24 - 156))
    }

    @Test func flipsLeftAtRightEdgeAndUpAtBottomEdge() {
        let origin = PixelLoupeGeometry.loupeOrigin(cursor: CGPoint(x: 950, y: 50), loupeSize: size, bounds: bounds)
        #expect(origin == CGPoint(x: 950 - 24 - 132, y: 74))
    }

    @Test func mapsViewPointToTopLeftImagePixelWithBackingScale() {
        // 1000×800 pt view, 2000×1600 px image (Retina)
        let p = PixelLoupeGeometry.imagePixel(
            forViewPoint: CGPoint(x: 10.4, y: 799.9),
            viewSize: bounds.size,
            imageSize: CGSize(width: 2000, height: 1600)
        )
        #expect(p == CGPoint(x: 20, y: 0))
    }

    @Test func clampsPixelToImage() {
        let p = PixelLoupeGeometry.imagePixel(
            forViewPoint: CGPoint(x: 1000, y: 0),
            viewSize: bounds.size,
            imageSize: CGSize(width: 2000, height: 1600)
        )
        #expect(p == CGPoint(x: 1999, y: 1599))
    }
}

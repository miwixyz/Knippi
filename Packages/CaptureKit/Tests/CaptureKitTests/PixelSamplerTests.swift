import CoreGraphics
import Testing
import SharedKit
@testable import CaptureKit

@Suite("Pixel sampler")
struct PixelSamplerTests {
    /// Builds a width×height RGBA8 image in `space`, filled with `fill` except `pixel` = `value`.
    private func makeImage(
        width: Int, height: Int, space: CGColorSpace,
        fill: (UInt8, UInt8, UInt8), pixel: (Int, Int), value: (UInt8, UInt8, UInt8)
    ) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let v = (x, y) == pixel ? value : fill
                bytes[i] = v.0; bytes[i + 1] = v.1; bytes[i + 2] = v.2; bytes[i + 3] = 255
            }
        }
        let ctx = CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return ctx.makeImage()!
    }

    @Test func exactSRGBPixelTopLeftOrigin() {
        let image = makeImage(width: 4, height: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              fill: (0, 0, 0), pixel: (1, 2), value: (46, 111, 128))
        #expect(sampleColor(in: image, atPixel: CGPoint(x: 1, y: 2)) == RGBColor(r: 46, g: 111, b: 128))
        #expect(sampleColor(in: image, atPixel: CGPoint(x: 2, y: 1)) == RGBColor(r: 0, g: 0, b: 0))
    }

    @Test func displayP3RedConvertsToClampedSRGBRed() throws {
        let image = makeImage(width: 2, height: 2, space: CGColorSpace(name: CGColorSpace.displayP3)!,
                              fill: (255, 0, 0), pixel: (0, 0), value: (255, 0, 0))
        let c = try #require(sampleColor(in: image, atPixel: CGPoint(x: 1, y: 1)))
        #expect(abs(c.r - 255) <= 2)
        #expect(c.g <= 2)
        #expect(c.b <= 2)
    }

    @Test func pointOutsideReturnsNil() {
        let image = makeImage(width: 4, height: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              fill: (0, 0, 0), pixel: (0, 0), value: (0, 0, 0))
        #expect(sampleColor(in: image, atPixel: CGPoint(x: 4, y: 0)) == nil)
        #expect(sampleColor(in: image, atPixel: CGPoint(x: -1, y: 2)) == nil)
        #expect(sampleColor(in: image, atPixel: CGPoint(x: 0, y: 4)) == nil)
    }
}

import Testing
import Foundation
import CoreGraphics
@testable import AnnotationKit

/// Confidential-text pixelation adds a fixed per-block brightness offset so the
/// block values can't be matched against candidate texts.
@Suite("Redaction noise")
struct RedactionNoiseTests {
    private func grayImage(width: Int = 240, height: Int = 40, level: CGFloat = 0.5) throws -> CGImage {
        let ctx = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.setFillColor(CGColor(red: level, green: level, blue: level, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(ctx.makeImage())
    }

    /// Red channel of every pixel, row by row.
    private func reds(_ image: CGImage) throws -> [Int] {
        let ctx = try #require(CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = try #require(ctx.data).assumingMemoryBound(to: UInt8.self)
        return stride(from: 0, to: image.width * image.height * 4, by: 4).map { Int(data[$0]) }
    }

    @Test func sameSeedGivesSamePicture() throws {
        let source = try grayImage()
        let a = try #require(PixelateObject.makePixelatedImage(from: source, blockSize: 20, noiseSeed: 7))
        let b = try #require(PixelateObject.makePixelatedImage(from: source, blockSize: 20, noiseSeed: 7))
        #expect(try reds(a) == reds(b))
    }

    @Test func blocksDifferWithNoiseAndStayWithinRange() throws {
        let source = try grayImage()
        let plain = try reds(try #require(PixelateObject.makePixelatedImage(from: source, blockSize: 20)))
        let noisy = try reds(try #require(PixelateObject.makePixelatedImage(from: source, blockSize: 20, noiseSeed: 42)))
        #expect(Set(plain).count == 1, "uniform source stays uniform without noise")
        #expect(Set(noisy).count > 1, "blocks get different offsets")
        let base = plain[0]
        #expect(noisy.allSatisfy { abs($0 - base) <= PixelateObject.noiseAmplitude })
    }

    @Test func differentSeedsGiveDifferentPictures() throws {
        let source = try grayImage()
        let a = try reds(try #require(PixelateObject.makePixelatedImage(from: source, blockSize: 20, noiseSeed: 1)))
        let b = try reds(try #require(PixelateObject.makePixelatedImage(from: source, blockSize: 20, noiseSeed: 2)))
        #expect(a != b)
    }

    @Test func copyKeepsTheSeed() throws {
        let original = PixelateObject(rect: CGRect(x: 0, y: 0, width: 10, height: 10), noiseSeed: 99)
        let copy = try #require(original.copy() as? PixelateObject)
        #expect(copy.noiseSeed == 99)
    }
}

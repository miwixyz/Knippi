import CoreGraphics
import Foundation
import Testing
@testable import CaptureKit

@Suite("ScrollStitcher")
struct ScrollStitcherTests {
    @Test("A slightly changing fixed header is not repeated in the stitched image")
    func changingFixedHeaderIsNotRepeated() throws {
        let first = makeFrame(rowsTopToBottom: [
            .red,
            .orange,
            .yellow,
            .green,
            .cyan,
            .blue,
        ])
        let next = makeFrame(
            rowsTopToBottom: [
                .red,
                .green,
                .cyan,
                .blue,
                .purple,
                .white,
            ],
            changedHeaderPixel: true
        )

        let stitcher = ScrollStitcher()
        stitcher.setInitialFrame(first)
        _ = stitcher.stitch(newFrame: next, detectedOffset: 2)

        let result = try #require(stitcher.mergedImage)
        #expect(result.height == 8)
        #expect(rowsTopToBottom(in: result) == [
            .red,
            .orange,
            .yellow,
            .green,
            .cyan,
            .blue,
            .purple,
            .white,
        ])
    }

    private enum RowColor: Equatable {
        case red, orange, yellow, green, cyan, blue, purple, white

        var components: (CGFloat, CGFloat, CGFloat, CGFloat) {
            switch self {
            case .red: (1, 0, 0, 1)
            case .orange: (1, 0.5, 0, 1)
            case .yellow: (1, 1, 0, 1)
            case .green: (0, 1, 0, 1)
            case .cyan: (0, 1, 1, 1)
            case .blue: (0, 0, 1, 1)
            case .purple: (0.5, 0, 1, 1)
            case .white: (1, 1, 1, 1)
            }
        }
    }

    private func makeFrame(
        rowsTopToBottom: [RowColor],
        changedHeaderPixel: Bool = false
    ) -> CGImage {
        let width = 32
        let height = rowsTopToBottom.count
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        for (topRow, color) in rowsTopToBottom.enumerated() {
            let components = color.components
            context.setFillColor(
                red: components.0,
                green: components.1,
                blue: components.2,
                alpha: components.3
            )
            context.fill(CGRect(x: 0, y: height - topRow - 1, width: width, height: 1))
        }

        if changedHeaderPixel {
            context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: height - 1, width: 1, height: 1))
        }

        return context.makeImage()!
    }

    private func rowsTopToBottom(in image: CGImage) -> [RowColor] {
        (0..<image.height).map { topRow in
            classify(samplePixel(image, x: image.width / 2, y: image.height - topRow - 1))
        }
    }

    private func samplePixel(
        _ image: CGImage,
        x: Int,
        y: Int
    ) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: -x, y: -y, width: image.width, height: image.height))
        return (
            CGFloat(pixel[0]) / 255,
            CGFloat(pixel[1]) / 255,
            CGFloat(pixel[2]) / 255
        )
    }

    private func classify(_ pixel: (r: CGFloat, g: CGFloat, b: CGFloat)) -> RowColor {
        let candidates: [RowColor] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .white]
        return candidates.min { lhs, rhs in
            distance(pixel, from: lhs) < distance(pixel, from: rhs)
        }!
    }

    private func distance(
        _ pixel: (r: CGFloat, g: CGFloat, b: CGFloat),
        from color: RowColor
    ) -> CGFloat {
        let components = color.components
        return abs(pixel.r - components.0)
            + abs(pixel.g - components.1)
            + abs(pixel.b - components.2)
    }
}

@Suite("ScrollStitcher cost")
struct ScrollStitcherCostTests {
    private static func strip(width: Int, height: Int, shade: UInt8) -> CGImage {
        var pixels = [UInt8](repeating: shade, count: width * height * 4)
        for i in stride(from: 3, to: pixels.count, by: 4) { pixels[i] = 255 }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: CGDataProvider(data: Data(pixels) as CFData)!,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }

    /// Seconds to stitch `count` frames that each add `step` new rows.
    private static func stitchTime(count: Int, width: Int = 200, frameHeight: Int = 200, step: Int = 40) -> Double {
        let frames = (0..<4).map { strip(width: width, height: frameHeight, shade: UInt8(40 + $0 * 50)) }
        let stitcher = ScrollStitcher()
        stitcher.setInitialFrame(frames[0])
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for index in 0..<count {
                _ = stitcher.stitch(newFrame: frames[index % 4], detectedOffset: step)
            }
        }
        #expect(stitcher.totalHeight == frameHeight + count * step)
        return Double(elapsed.components.attoseconds) / 1e18 + Double(elapsed.components.seconds)
    }

    @Test("Stitching grows linearly with page length, not quadratically")
    func stitchingIsLinear() {
        _ = Self.stitchTime(count: 50) // warm-up
        // Fastest of three runs each, so other tests running in parallel do not skew it.
        let short = (0..<3).map { _ in Self.stitchTime(count: 500) }.min()!
        let long = (0..<3).map { _ in Self.stitchTime(count: 2000) }.min()!
        // 4× the frames: linear ≈ 4×, quadratic ≈ 16×.
        #expect(long / short < 8, "500 frames \(short)s, 2000 frames \(long)s")
    }

    @Test("Live preview is small and follows the page")
    func previewIsSmall() throws {
        let stitcher = ScrollStitcher()
        stitcher.setInitialFrame(Self.strip(width: 1200, height: 600, shade: 80))
        for _ in 0..<20 {
            _ = stitcher.stitch(newFrame: Self.strip(width: 1200, height: 600, shade: 160), detectedOffset: 100)
        }
        let preview = try #require(stitcher.previewImage)
        #expect(preview.width == ScrollStitcher.previewWidth)
        #expect(abs(preview.height - (600 + 20 * 100) / 5) <= 1)
    }
}

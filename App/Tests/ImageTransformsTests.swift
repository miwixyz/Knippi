import CoreGraphics
import XCTest
@testable import Knippi

/// Audit A4 (21.11.): the image turned clockwise while the crop rect was remapped
/// counter-clockwise, so after "Rotate" the crop sat on a different part of the picture.
final class ImageTransformsTests: XCTestCase {
    func testRotatedCropStillCoversTheSamePixel() throws {
        // 4×2 image, a single red pixel top-left, everything else white.
        let source = try XCTUnwrap(makeImage(width: 4, height: 2, redAt: (0, 0)))
        let rotated = try XCTUnwrap(ImageTransforms.rotate90CCW(source))
        XCTAssertEqual(rotated.width, 2)
        XCTAssertEqual(rotated.height, 4)

        let crop = RectTransforms.rotate90CCW(CGRect(x: 0, y: 0, width: 1, height: 1), in: CGSize(width: 4, height: 2))
        XCTAssertTrue(isRed(rotated, x: Int(crop.minX), y: Int(crop.minY)), "crop \(crop) must still cover the red pixel")
    }

    /// Top-left origin, like the canvas.
    private func makeImage(width: Int, height: Int, redAt: (Int, Int)) -> CGImage? {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        let i = (redAt.1 * width + redAt.0) * 4
        bytes[i] = 255; bytes[i + 1] = 0; bytes[i + 2] = 0; bytes[i + 3] = 255
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }

    private func isRed(_ image: CGImage, x: Int, y: Int) -> Bool {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let ctx = CGContext(
            data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let i = (y * image.width + x) * 4  // row 0 = top
        return bytes[i] > 200 && bytes[i + 1] < 50 && bytes[i + 2] < 50
    }
}

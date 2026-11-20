import Testing
import CoreGraphics
@testable import CaptureKit

@Suite("Scroll capture cancel")
struct ScrollCaptureCancelTests {
    @Test("Cancelled capture delivers no image")
    func cancelledDeliversNil() throws {
        let ctx = try #require(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(ctx.makeImage())
        #expect(ScrollCaptureController.completionImage(image, userCancelled: true) == nil)
        #expect(ScrollCaptureController.completionImage(image, userCancelled: false) === image)
    }
}

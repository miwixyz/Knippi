import AppKit
import CaptureKit
import SharedKit
import XCTest
@testable import Knippi

/// A capture must not stay in memory once nothing shows it any more. A long
/// scrolling capture is 180 MB and more (measured 2026-11-21: Knippi kept
/// the last image for good, 229 MB after the preview was closed).
@MainActor
final class CaptureResultReleaseTests: XCTestCase {
    /// Set by the image's data provider when its pixels are freed.
    private final class ReleaseFlag: @unchecked Sendable { var released = false }

    func testCaptureImageIsFreedAfterHandlingWithNothingShown() throws {
        let suite = "CaptureResultReleaseTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.screenshotShowPreview = false
        settings.screenshotAutoCopy = false
        settings.screenshotAutoSave = false
        settings.playShutterSound = false

        let flag = ReleaseFlag()
        let coordinator = CaptureCoordinator(settings: settings)
        autoreleasepool {
            let image = Self.image(onRelease: flag)
            coordinator.handleCaptureResult(CaptureResult(
                image: image, mode: .scrolling, captureRect: CGRect(x: 0, y: 0, width: 8, height: 6), displayID: 0
            ))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertTrue(flag.released, "the coordinator still holds the captured image")
        _ = coordinator
    }

    private static func image(onRelease flag: ReleaseFlag) -> CGImage {
        let width = 8, height = 6, bytesPerRow = width * 4
        let bytes = UnsafeMutableRawPointer.allocate(byteCount: bytesPerRow * height, alignment: 16)
        bytes.initializeMemory(as: UInt8.self, repeating: 200, count: bytesPerRow * height)
        let provider = CGDataProvider(
            dataInfo: Unmanaged.passRetained(flag).toOpaque(), data: bytes, size: bytesPerRow * height,
            releaseData: { info, data, _ in
                let flag = Unmanaged<ReleaseFlag>.fromOpaque(info!).takeRetainedValue()
                flag.released = true
                data.deallocate()
            }
        )!
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }
}

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import CaptureKit

/// Replays frames recorded by the app (`debugScrollFramesFolder`) through the
/// real capture loop. Runs only when KNIPPI_SCROLL_FRAMES points at such a
/// folder; writes the stitched page to KNIPPI_SCROLL_OUT.
@Suite("Scroll capture replay")
struct ScrollCaptureReplayTests {
    private struct EndOfFrames: Error {}

    @Test("Recorded frames stitch into one page",
          .enabled(if: ProcessInfo.processInfo.environment["KNIPPI_SCROLL_FRAMES"] != nil))
    func replayRecordedFrames() async throws {
        let env = ProcessInfo.processInfo.environment
        let folder = URL(fileURLWithPath: try #require(env["KNIPPI_SCROLL_FRAMES"]))
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "png" && $0.lastPathComponent.hasPrefix("frame-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let frames = files.compactMap { url -> CGImage? in
            CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        }
        #expect(frames.count == files.count)

        final class Feed: @unchecked Sendable {
            let lock = NSLock(); var index = 0; let frames: [CGImage]
            init(_ frames: [CGImage]) { self.frames = frames }
            func next() throws -> CGImage {
                try lock.withLock {
                    guard index < frames.count else { throw EndOfFrames() }
                    defer { index += 1 }
                    return frames[index]
                }
            }
        }
        let feed = Feed(frames)
        let controller = ScrollCaptureController(
            config: ScrollCaptureConfig(captureRect: .zero, displayID: 0,
                                        debugFrameDirectory: env["KNIPPI_SCROLL_DEBUG"].map { URL(fileURLWithPath: $0) }),
            frameInterval: .zero, maxConsecutiveFailures: 1,
            frameSource: { try feed.next() }
        )
        let clock = ContinuousClock()
        let started = clock.now
        let outcome = await withCheckedContinuation { continuation in
            controller.start(onProgress: { _ in }, onComplete: { continuation.resume(returning: $0) })
        }
        let elapsed = started.duration(to: clock.now)
        let page: CGImage
        switch outcome {
        case let .failed(_, partial?): page = partial   // ran out of frames
        case let .finished(image): page = image          // maximum height reached
        default:
            Issue.record("expected the page after the last frame, got \(outcome)")
            return
        }
        print("REPLAY \(frames.count) frames → \(page.width)×\(page.height) px in \(elapsed)")
        if let out = env["KNIPPI_SCROLL_OUT"],
           let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, page, nil)
            CGImageDestinationFinalize(destination)
        }
    }
}

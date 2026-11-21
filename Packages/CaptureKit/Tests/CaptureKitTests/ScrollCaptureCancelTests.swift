import CoreGraphics
import Foundation
import ScreenCaptureKit
import Testing
@testable import CaptureKit

/// Drives `ScrollCaptureController` with a fake frame source instead of
/// ScreenCaptureKit: cancel/restart races, failures, permission loss.
@Suite("Scroll capture controller")
struct ScrollCaptureCancelTests {
    private struct Failure: Error {}

    private static func frame(seed: UInt8 = 1) -> CGImage {
        let (width, height) = (64, 48)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = UInt8(truncatingIfNeeded: i &* 7 &+ Int(seed))
            pixels[i + 1] = UInt8(truncatingIfNeeded: i / 3)
            pixels[i + 3] = 255
        }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: CGDataProvider(data: Data(pixels) as CFData)!,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }

    private static func controller(
        maxFailures: Int = 5,
        source: @escaping ScrollCaptureController.FrameSource
    ) -> ScrollCaptureController {
        ScrollCaptureController(
            config: ScrollCaptureConfig(captureRect: CGRect(x: 0, y: 0, width: 64, height: 48), displayID: 1),
            frameInterval: .milliseconds(1),
            maxConsecutiveFailures: maxFailures,
            frameSource: source
        )
    }

    /// Starts the controller and waits for its single completion.
    private static func run(
        _ controller: ScrollCaptureController,
        whileRunning: @escaping @Sendable () async -> Void = {}
    ) async -> (ScrollCaptureOutcome, completions: Int) {
        let counter = Counter()
        let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<ScrollCaptureOutcome, Never>) in
            controller.start(onProgress: { _ in }, onComplete: { outcome in
                if counter.increment() == 1 { continuation.resume(returning: outcome) }
            })
            Task { await whileRunning() }
        }
        try? await Task.sleep(for: .milliseconds(20))
        return (outcome, counter.value)
    }

    @Test("Cancel delivers no image, exactly once")
    func cancelDeliversNothing() async {
        let controller = Self.controller { Self.frame() }
        let (outcome, completions) = await Self.run(controller) {
            try? await Task.sleep(for: .milliseconds(30))
            controller.cancel()
        }
        guard case .cancelled = outcome else { Issue.record("expected cancelled, got \(outcome)"); return }
        #expect(completions == 1)
    }

    @Test("Done delivers the page")
    func stopDeliversImage() async {
        let calls = Counter()
        let controller = Self.controller { calls.increment(); return Self.frame() }
        let (outcome, _) = await Self.run(controller) {
            for _ in 0..<500 where calls.value < 3 {
                try? await Task.sleep(for: .milliseconds(10))
            }
            controller.stop()
        }
        guard case let .finished(image) = outcome else { Issue.record("expected finished, got \(outcome)"); return }
        #expect(image.height == 48)
    }

    @Test("Start twice runs one loop")
    func secondStartIsIgnored() async {
        let calls = Counter()
        let controller = Self.controller { calls.increment(); return Self.frame() }
        let completions = Counter()
        controller.start(onProgress: { _ in }, onComplete: { _ in completions.increment() })
        controller.start(onProgress: { _ in }, onComplete: { _ in completions.increment() })
        try? await Task.sleep(for: .milliseconds(30))
        controller.cancel()
        for _ in 0..<500 where completions.value == 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(completions.value == 1)
    }

    @Test("Fast cancel and restart from many threads: each run ends once, cancelled runs give nothing")
    func cancelRestartRace() async {
        let runs = 40
        let results = await withTaskGroup(of: (Bool, ScrollCaptureOutcome, Int).self) { group in
            for index in 0..<runs {
                group.addTask {
                    let controller = Self.controller { Self.frame(seed: UInt8(index)) }
                    let cancel = index.isMultiple(of: 2)
                    let (outcome, completions) = await Self.run(controller) {
                        if index % 3 == 0 { try? await Task.sleep(for: .microseconds(index * 50)) }
                        if cancel { controller.cancel() } else { controller.stop() }
                        // Late calls after the end must be harmless.
                        controller.cancel()
                        controller.stop()
                    }
                    return (cancel, outcome, completions)
                }
            }
            var all: [(Bool, ScrollCaptureOutcome, Int)] = []
            for await result in group { all.append(result) }
            return all
        }
        #expect(results.count == runs)
        for (cancelled, outcome, completions) in results {
            #expect(completions == 1)
            if cancelled, case .cancelled = outcome { continue }
            if !cancelled { continue }
            Issue.record("cancelled run delivered \(outcome)")
        }
    }

    @Test("Permission loss ends the loop at once and keeps the page so far")
    func permissionLossEndsLoop() async {
        let calls = Counter()
        let controller = Self.controller(maxFailures: 1000) {
            if calls.increment() == 1 { return Self.frame() }
            throw NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue)
        }
        let (outcome, completions) = await Self.run(controller)
        guard case let .failed(error, partial) = outcome else { Issue.record("expected failed, got \(outcome)"); return }
        #expect(ScrollCaptureController.isPermissionError(error))
        #expect(partial?.height == 48)
        #expect(calls.value == 2)
        #expect(completions == 1)
    }

    @Test("A screen that never answers ends after a few tries instead of looping forever")
    func repeatedFailuresEndLoop() async {
        let calls = Counter()
        let controller = Self.controller(maxFailures: 5) {
            calls.increment()
            throw Failure()
        }
        let (outcome, _) = await Self.run(controller)
        guard case let .failed(_, partial) = outcome else { Issue.record("expected failed, got \(outcome)"); return }
        #expect(partial == nil)
        #expect(calls.value == 5)
    }

    @Test("A single hiccup does not end the capture")
    func singleFailureIsRetried() async {
        let calls = Counter()
        let controller = Self.controller(maxFailures: 3) {
            let n = calls.increment()
            if n == 2 || n == 4 { throw Failure() }
            return Self.frame()
        }
        let (outcome, _) = await Self.run(controller) {
            for _ in 0..<500 where calls.value < 6 {
                try? await Task.sleep(for: .milliseconds(10))
            }
            controller.stop()
        }
        guard case .finished = outcome else { Issue.record("expected finished, got \(outcome)"); return }
        #expect(calls.value > 4)
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    @discardableResult func increment() -> Int { lock.withLock { count += 1; return count } }
    var value: Int { lock.withLock { count } }
}

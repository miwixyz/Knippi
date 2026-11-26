// Packages/CaptureKit/Sources/CaptureKit/Scrolling/ScrollCaptureController.swift
import CoreGraphics
import Foundation
import ImageIO
import os
@preconcurrency import ScreenCaptureKit

public struct ScrollCaptureConfig: Sendable {
    public let captureRect: CGRect
    public let displayID: CGDirectDisplayID
    public let maxHeight: Int
    /// Diagnostics: every captured frame is written here as PNG, with the
    /// detected offsets in `offsets.csv`. Nil in normal use.
    public let debugFrameDirectory: URL?

    public init(
        captureRect: CGRect,
        displayID: CGDirectDisplayID,
        maxHeight: Int = 30_000,
        debugFrameDirectory: URL? = nil
    ) {
        self.captureRect = captureRect
        self.displayID = displayID
        self.maxHeight = maxHeight
        self.debugFrameDirectory = debugFrameDirectory
    }
}

public struct ScrollCaptureProgress: @unchecked Sendable {
    public let currentHeight: Int
    public let maxHeight: Int
    public let frameCount: Int
    /// Small copy of the page so far, for the live preview.
    public let preview: CGImage?
    /// Scrolled too fast: Knippi no longer knows where it is on the page.
    /// Scrolling back to the last captured part continues the capture.
    public let isTrackingLost: Bool
}

/// How a scrolling capture ended.
public enum ScrollCaptureError: Error, Equatable, LocalizedError {
    /// Auto mode lost its place on the page; scrolling on would only produce a gap.
    case trackingLost

    public var errorDescription: String? { "Lost track of the page while scrolling automatically." }
}

public enum ScrollCaptureOutcome: @unchecked Sendable {
    /// Done was clicked or the maximum height was reached.
    case finished(CGImage)
    /// Cancelled by the user (or stopped before the first frame); no image.
    case cancelled
    /// The screen could no longer be read, e.g. Screen Recording permission
    /// was revoked. `partial` is the page stitched until then, if any.
    case failed(Error, partial: CGImage?)
}

public final class ScrollCaptureController: @unchecked Sendable {
    public typealias FrameSource = @Sendable () async throws -> CGImage
    /// Scrolls the page one step further (auto mode).
    public typealias AutoScroller = @Sendable () async -> Void

    private struct RunState {
        var started = false
        var stopRequested = false
        var cancelled = false
    }

    private let config: ScrollCaptureConfig
    private let frameInterval: Duration
    private let maxConsecutiveFailures: Int
    private let injectedFrameSource: FrameSource?
    private let autoScroller: AutoScroller?
    /// Auto mode: frames in a row that did not move after a scroll step.
    private var unmovedSteps = 0
    /// Written from the caller's thread, read by the capture loop.
    private let state = OSAllocatedUnfairLock(initialState: RunState())

    // Only touched by the capture loop task.
    private let stitcher = ScrollStitcher()
    private var frameCount = 0
    /// A/B frame model. `shotA` is the last frame that was stitched.
    private var shotA: CGImage?
    private var fixedRegions: FixedRegions?
    private var shotAProfile: RowProfileMatcher.Profile?
    /// Last captured frame and its position below `shotA` (nil: track lost).
    private var previousFrame: CGImage?
    private var previousFrameProfile: RowProfileMatcher.Profile?
    /// Pixel bytes of the frame the next one is compared against.
    private var comparisonData: (frame: CGImage, data: CFData)?
    private var previousPosition: Int? = 0
    private var trackingLost = false
    private var debugFrameIndex = 0
    /// Cached ScreenCaptureKit objects (created once, reused)
    private var cachedFilter: SCContentFilter?
    private var cachedStreamConfig: SCStreamConfiguration?

    /// With `autoScroller` (auto mode) Knippi scrolls itself and stops at the
    /// end of the page; otherwise the user scrolls.
    public convenience init(config: ScrollCaptureConfig, autoScroller: AutoScroller? = nil) {
        self.init(config: config, frameInterval: .milliseconds(50), maxConsecutiveFailures: 10,
                  frameSource: nil, autoScroller: autoScroller)
    }

    /// `frameSource` replaces ScreenCaptureKit (tests).
    init(
        config: ScrollCaptureConfig,
        frameInterval: Duration,
        maxConsecutiveFailures: Int,
        frameSource: FrameSource?,
        autoScroller: AutoScroller? = nil
    ) {
        self.config = config
        self.frameInterval = frameInterval
        self.maxConsecutiveFailures = max(1, maxConsecutiveFailures)
        self.injectedFrameSource = frameSource
        self.autoScroller = autoScroller
    }

    /// Starts the capture loop once; later calls are ignored.
    /// `onComplete` is called exactly once, on a background thread.
    public func start(
        onProgress: @escaping @Sendable (ScrollCaptureProgress) -> Void,
        onComplete: @escaping @Sendable (ScrollCaptureOutcome) -> Void
    ) {
        let isFirstStart = state.withLock { state -> Bool in
            guard !state.started else { return false }
            state.started = true
            return true
        }
        guard isFirstStart else { return }
        Task.detached(priority: .utility) { [self] in
            onComplete(await self.runCaptureLoop(onProgress: onProgress))
        }
    }

    /// Beendet die Aufnahme und liefert das bisher zusammengesetzte Bild.
    public func stop() {
        state.withLock { $0.stopRequested = true }
    }

    /// Bricht ab; `onComplete` bekommt `.cancelled`.
    public func cancel() {
        state.withLock {
            $0.cancelled = true
            $0.stopRequested = true
        }
    }

    private var stopRequested: Bool { state.withLock { $0.stopRequested } }

    /// By hand, a short pause keeps neighbouring frames overlapping even on a
    /// fast flick (150 ms lost the track on the first flick in Safari,
    /// 2026-11-21). In auto mode the page needs time to settle after each
    /// step: frameInterval × this factor (300 ms, as measured fine).
    static let autoStepSettle = 6

    /// Auto mode ends after this many scroll steps without any movement.
    static let unmovedStepsAtPageEnd = 2

    // MARK: - Capture Loop

    private func runCaptureLoop(
        onProgress: @escaping @Sendable (ScrollCaptureProgress) -> Void
    ) async -> ScrollCaptureOutcome {
        var failures = 0

        // Runs until the user clicks Done (stop) or Cancel, the maximum height
        // is reached, or the screen can no longer be read. No auto-stop on
        // pause/jitter.
        while !stopRequested {
            if stitcher.totalHeight >= config.maxHeight { break }

            if frameCount > 0 || failures > 0 {
                if let autoScroller, failures == 0 {
                    await autoScroller()
                }
                try? await Task.sleep(for: autoScroller == nil ? frameInterval : frameInterval * Self.autoStepSettle)
                guard !stopRequested else { break }
            }

            let shotB: CGImage
            do {
                shotB = try await nextFrame()
                failures = 0
            } catch {
                failures += 1
                if Self.isPermissionError(error) || failures >= maxConsecutiveFailures {
                    return outcome(failure: error)
                }
                continue
            }

            debugFrameIndex += 1
            Self.writeDebugFrame(shotB, index: debugFrameIndex, to: config.debugFrameDirectory)

            guard let shotA else {
                stitcher.setInitialFrame(shotB)
                self.shotA = shotB
                frameCount = 1
                reportProgress(onProgress)
                continue
            }

            // Skip if identical to the previous frame (user not scrolling)
            // The bytes of the previous frame are kept, so each tick copies
            // only the new frame instead of both.
            let previous = previousFrame ?? shotA
            let previousData: CFData?
            if let cached = comparisonData, cached.frame === previous {
                previousData = cached.data
            } else {
                previousData = previous.dataProvider?.data
                comparisonData = previousData.map { (frame: previous, data: $0) }
            }
            let newData = shotB.dataProvider?.data
            if let dataA = previousData,
               let dataB = newData,
               CFDataGetLength(dataA) == CFDataGetLength(dataB),
               memcmp(CFDataGetBytePtr(dataA)!, CFDataGetBytePtr(dataB)!, CFDataGetLength(dataA)) == 0 {
                // Auto mode: the page no longer moves, so its end is reached.
                if autoScroller != nil {
                    unmovedSteps += 1
                    if unmovedSteps >= Self.unmovedStepsAtPageEnd { break }
                }
                continue
            }

            // Sticky bars are measured on every pair: a page can change its
            // header once it starts scrolling (measured in Safari).
            let regions = FixedRegions.detect(frame1: previous, frame2: shotB)
            if fixedRegions == nil {
                fixedRegions = regions
                stitcher.setFooterHeight(regions.footer)
            }
            let bottom = max(regions.footer, fixedRegions?.footer ?? 0)

            guard let profileB = RowProfileMatcher.Profile(shotB) else { continue }
            if shotAProfile == nil { shotAProfile = RowProfileMatcher.Profile(shotA) }
            let previousProfile = previousFrameProfile ?? shotAProfile

            // Track the position frame by frame: neighbouring frames overlap a
            // lot, so look-alike lines further down cannot win. Only when the
            // track is lost, re-find the last stitched frame, strictly.
            var position: Int?
            var debugMatch: RowProfileMatcher.Match?
            if let known = previousPosition, let previousProfile,
               let match = RowProfileMatcher.offset(from: previousProfile, to: profileB,
                                                    top: regions.header, bottom: bottom) {
                position = known + match.offset
                debugMatch = match
            } else if let shotAProfile,
                      let match = RowProfileMatcher.offset(from: shotAProfile, to: profileB,
                                                           top: regions.header, bottom: bottom, strict: true) {
                position = match.offset
                debugMatch = match
            }
            Self.appendDebugLine(
                "\(debugFrameIndex),\(frameCount),\(position.map(String.init) ?? ""),\(regions.header),\(regions.footer),\(debugMatch.map { "\($0.offset) \(String(format: "%.2f", $0.error)) \(String(format: "%.2f", $0.runnerUpError))" } ?? "")",
                to: config.debugFrameDirectory
            )

            previousFrame = shotB
            comparisonData = newData.map { (frame: shotB, data: $0) }
            previousFrameProfile = profileB
            previousPosition = position
            if (position == nil) != trackingLost {
                trackingLost = position == nil
                reportProgress(onProgress)
            }

            if autoScroller != nil {
                // Auto mode: lost track = scrolling on would only leave a gap, so stop and
                // say so instead of returning the part as if it were the whole page (audit C2).
                guard let offset = position else {
                    return outcome(failure: ScrollCaptureError.trackingLost)
                }
                // Hardly any movement counts as "page end" too, not only identical frames:
                // a video or spinner at the end keeps frames different (audit C8).
                if offset < 3 {
                    unmovedSteps += 1
                    if unmovedSteps >= Self.unmovedStepsAtPageEnd { break }
                    continue
                }
            }

            // Position relative to the last stitched frame; small or upward
            // moves wait, a move past the overlap waits for the user to
            // scroll back.
            guard let offset = position, offset >= 3 else { continue }
            if case .stitched = stitcher.stitch(newFrame: shotB, detectedOffset: offset) {
                self.shotA = shotB
                shotAProfile = profileB
                previousPosition = 0
                unmovedSteps = 0
                frameCount += 1
                reportProgress(onProgress)
            }
        }

        return outcome(failure: nil)
    }

    private func reportProgress(_ onProgress: @Sendable (ScrollCaptureProgress) -> Void) {
        onProgress(ScrollCaptureProgress(
            currentHeight: stitcher.totalHeight,
            maxHeight: config.maxHeight,
            frameCount: frameCount,
            preview: stitcher.previewImage,
            isTrackingLost: trackingLost
        ))
    }

    private func outcome(failure: Error?) -> ScrollCaptureOutcome {
        if state.withLock({ $0.cancelled }) { return .cancelled }
        let image = frameCount > 0 ? stitcher.mergedImage : nil
        if let image { Self.writeDebugFrame(image, name: "result.png", to: config.debugFrameDirectory) }
        if let failure { return .failed(failure, partial: image) }
        if let image { return .finished(image) }
        return .cancelled
    }

    /// Screen Recording permission missing or revoked: retrying cannot help.
    static func isPermissionError(_ error: Error) -> Bool {
        if case CaptureError.capturePermissionDenied = error { return true }
        let nsError = error as NSError
        return nsError.domain == SCStreamErrorDomain
            && nsError.code == SCStreamError.Code.userDeclined.rawValue
    }

    private func nextFrame() async throws -> CGImage {
        if let injectedFrameSource { return try await injectedFrameSource() }
        do {
            return try await captureFrame()
        } catch {
            // The display set may have changed; rebuild the filter next time.
            cachedFilter = nil
            cachedStreamConfig = nil
            throw error
        }
    }

    // MARK: - Frame Capture

    private func captureFrame() async throws -> CGImage {
        if cachedFilter == nil {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            // No fallback to another display: the capture rect is in this
            // display's coordinates, so any other display would yield the
            // wrong content (audit C17, 21.11.).
            guard let display = content.displays.first(where: {
                $0.displayID == config.displayID
            }) else {
                throw CaptureError.noDisplayFound
            }

            let excludedBundleIDs: Set<String> = [
                Bundle.main.bundleIdentifier ?? "",
                "com.apple.dock",
                "com.apple.controlcenter",
                "com.apple.notificationcenterui",
                "com.apple.Spotlight",
            ]
            let excludedWindows = content.windows.filter { window in
                guard let bundleID = window.owningApplication?.bundleIdentifier else {
                    return false
                }
                return excludedBundleIDs.contains(bundleID)
            }

            let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
            let streamConfig = SCStreamConfiguration()
            streamConfig.captureResolution = .best
            streamConfig.showsCursor = false
            streamConfig.sourceRect = config.captureRect
            let scale = CGFloat(filter.pointPixelScale)
            streamConfig.width = Int(config.captureRect.width * scale)
            streamConfig.height = Int(config.captureRect.height * scale)

            cachedFilter = filter
            cachedStreamConfig = streamConfig
        }

        guard let filter = cachedFilter, let cfg = cachedStreamConfig else {
            throw CaptureError.noDisplayFound
        }

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: cfg
        )
    }

    // MARK: - Diagnostics

    private static func writeDebugFrame(_ frame: CGImage, index: Int, to directory: URL?) {
        writeDebugFrame(frame, name: String(format: "frame-%04d.png", index), to: directory)
    }

    private static func writeDebugFrame(_ frame: CGImage, name: String, to directory: URL?) {
        guard let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, frame, nil)
        CGImageDestinationFinalize(destination)
    }

    /// Columns: frame index (file), frames stitched so far, accepted offset to
    /// the last stitched frame, header rows, footer rows, best candidate
    /// (offset, error, runner-up error).
    private static func appendDebugLine(_ line: String, to directory: URL?) {
        guard let directory else { return }
        let url = directory.appendingPathComponent("offsets.csv")
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    // MARK: - Offset Detection

    /// Rows that stay put while the page scrolls.
    struct FixedRegions: Equatable {
        var header = 0
        var footer = 0

        static func detect(frame1: CGImage, frame2: CGImage) -> FixedRegions {
            let rows = HeaderDetector.detectFixedRows(frame1: frame1, frame2: frame2)
            return FixedRegions(header: rows.header, footer: rows.footer)
        }
    }

    /// How many pixel rows `later` is scrolled down relative to `earlier`
    /// (negative when scrolled up), measured only inside the scrolling area.
    /// Nil when no offset is clearly right.
    static func verticalOffset(from earlier: CGImage, to later: CGImage, ignoring fixed: FixedRegions) -> Int? {
        guard let a = RowProfileMatcher.Profile(earlier),
              let b = RowProfileMatcher.Profile(later) else { return nil }
        return RowProfileMatcher.offset(from: a, to: b, top: fixed.header, bottom: fixed.footer)?.offset
    }
}

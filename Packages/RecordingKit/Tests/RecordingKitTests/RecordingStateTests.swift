// Packages/RecordingKit/Tests/RecordingKitTests/RecordingStateTests.swift
import Testing
import CoreMedia
import Foundation
@testable import RecordingKit

@Suite("RecordingState")
struct RecordingStateTests {
    @Test("RecordingState has expected cases")
    func states() {
        let states: [RecordingState] = [.idle, .preparing, .recording, .paused, .stopping]
        #expect(states.count == 5)
    }

    @Test("RecordingState isActive")
    func isActive() {
        #expect(RecordingState.recording.isActive == true)
        #expect(RecordingState.paused.isActive == true)
        #expect(RecordingState.idle.isActive == false)
        #expect(RecordingState.preparing.isActive == false)
        #expect(RecordingState.stopping.isActive == false)
    }

    @Test("RecordingFormat has two cases")
    func formats() {
        let formats: [RecordingFormat] = [.video, .gif]
        #expect(formats.count == 2)
    }

    @Test("RecordingConfig defaults")
    func configDefaults() {
        let rect = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let config = RecordingConfig(captureRect: rect, displayID: 1)
        #expect(config.target == .displayArea(displayID: 1, rect: rect))
        #expect(config.format == .video)
        #expect(config.fps == 30)
        #expect(config.captureSystemAudio == true)
        #expect(config.captureMicrophone == false)
        #expect(config.showCursor == true)
    }

    @Test("RecordingConfig can target a window")
    func configWindowTarget() {
        let config = RecordingConfig(windowID: 42, captureSystemAudio: false)

        #expect(config.target == .window(windowID: 42))
        #expect(config.captureSystemAudio == false)
        #expect(config.captureMicrophone == false)
        #expect(config.showCursor == true)
    }
}

@Suite("Recording pause")
struct RecordingPauseTests {
    private func t(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 600) }

    @Test("The cut is exactly the time between pause and resume")
    func pauseLengthIsTheClockTime() {
        #expect(RecordingWriterTiming.pauseLength(pausedAt: t(30), resumedAt: t(40)) == t(10))
        #expect(RecordingWriterTiming.pauseLength(pausedAt: t(30), resumedAt: t(29)) == .zero)
    }

    /// Audit R1 (21.11.): on a still screen SCK sends only idle frames, so the old cut
    /// (last changed frame → next changed frame) also removed the still part before the
    /// pause and made audio timestamps run backwards.
    @Test("Still screen: video and audio stay in line after a pause")
    func stillScreenKeepsVideoAndAudioInLine() {
        let offset = RecordingWriterTiming.pauseLength(pausedAt: t(30), resumedAt: t(40))
        // Last changed frame at 10 s, next one at 45 s; audio written up to 30 s.
        let nextFrame = CMTimeSubtract(t(45), offset)
        let nextAudio = CMTimeSubtract(t(40.5), offset)
        #expect(nextFrame == t(35))
        #expect(CMTimeCompare(nextAudio, t(30)) > 0)
    }

    @Test("Buffers stamped inside the pause are dropped, later ones kept")
    func buffersFromThePauseAreDropped() {
        #expect(RecordingWriterTiming.isFromPause(t(39.9), resumedAt: t(40)))
        #expect(!RecordingWriterTiming.isFromPause(t(40), resumedAt: t(40)))
        #expect(!RecordingWriterTiming.isFromPause(t(12), resumedAt: nil))
    }
}

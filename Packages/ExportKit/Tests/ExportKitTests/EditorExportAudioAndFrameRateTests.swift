import AVFoundation
import EditorKit
import Foundation
import SharedKit
import Testing

@testable import ExportKit

/// Editor export paths (effects compositor, cut export) must mix system audio
/// and microphone into one track like `MP4Exporter` does (audit E6, 21.11.),
/// and the compositor must never derive an invalid frame duration from a
/// sparse recording's nominal frame rate (audit E4, 21.11.).
struct EditorExportAudioAndFrameRateTests {

    // MARK: - E4

    @Test("Frame duration is always positive and smooth", arguments: [
        (Float(0), Int32(30)),
        (Float(0.25), Int32(30)),
        (Float(3.4), Int32(30)),
        (Float(29.97), Int32(30)),
        (Float(60), Int32(60)),
        (Float(240), Int32(60)),
        (Float.nan, Int32(30)),
        (Float.infinity, Int32(30)),
        (Float(1e12), Int32(60)),
    ])
    func frameDurationIsValid(nominal: Float, expectedFPS: Int32) {
        let duration = CompositorExporter.frameDuration(forNominalFrameRate: nominal)
        #expect(duration.isValid)
        #expect(duration.seconds > 0)
        #expect(duration == CMTime(value: 1, timescale: expectedFPS))
    }

    // MARK: - E6

    @Test("Compositor export mixes two audio tracks into one")
    func compositorExportMergesAudio() async throws {
        let source = try DualAudioFixture.make(durationSeconds: 1)
        defer { try? FileManager.default.removeItem(at: source) }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("e6-compositor-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: dest) }

        let project = RecordingProject(
            sourceVideoURL: source,
            videoDuration: 1,
            videoSize: CGSize(width: 160, height: 120),
            recordingAreaSize: CGSize(width: 160, height: 120),
            backgroundStyle: BackgroundStyle(enabled: true)
        )
        let exported = try await CompositorExporter.export(
            source: source,
            project: project,
            cursorTimeline: nil,
            zoomInterpolator: nil,
            destination: dest,
            quality: .maximum
        )

        let asset = AVURLAsset(url: exported)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
    }

    @Test("Cut export mixes two audio tracks into one")
    func cutExportMergesAudio() async throws {
        // ≤ 1 s: the fixture writes video before audio, longer clips stall the
        // writer's interleaving.
        let source = try DualAudioFixture.make(durationSeconds: 1)
        defer { try? FileManager.default.removeItem(at: source) }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("e6-cut-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: dest) }

        let exported = try await CutExporter.exportMP4(
            source: source,
            trimRegions: [TrimRegion(startTime: 0.3, endTime: 0.6)],
            quality: .maximum,
            destination: dest
        )

        let asset = AVURLAsset(url: exported)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - 0.7) < 0.1, "Cut must still remove 0.3 s, got \(duration)")
    }
}

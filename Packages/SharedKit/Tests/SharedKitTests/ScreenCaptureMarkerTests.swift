import Testing
import Foundation
@testable import SharedKit

@Suite("Screen capture marker")
struct ScreenCaptureMarkerTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("knippi-marker-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func file(_ dir: URL, _ name: String = "shot.png") throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data([1, 2, 3]).write(to: url)
        return url
    }

    @Test func valueIsABinaryPlistOfTrue() throws {
        let decoded = try PropertyListSerialization.propertyList(from: ScreenCaptureMarker.value, format: nil)
        #expect(decoded as? Bool == true)
        #expect(ScreenCaptureMarker.value.starts(with: Array("bplist00".utf8)))
        #expect(ScreenCaptureMarker.value.count == 42)   // the size macOS writes
    }

    @Test func markSetsTheAttributeAndOnlyOnThatFile() throws {
        let dir = try folder()
        let marked = try file(dir, "a.png"), other = try file(dir, "b.png")
        #expect(!ScreenCaptureMarker.isMarked(marked))
        #expect(ScreenCaptureMarker.mark(marked))
        #expect(ScreenCaptureMarker.isMarked(marked))
        #expect(!ScreenCaptureMarker.isMarked(other))
    }

    @Test func markingAMissingFileFailsWithoutCrashing() throws {
        let missing = try folder().appendingPathComponent("weg.png")
        #expect(!ScreenCaptureMarker.mark(missing))
        #expect(!ScreenCaptureMarker.isMarked(missing))
    }

    @Test func aSymbolicLinkIsNotFollowed() throws {
        let dir = try folder()
        let target = try file(dir, "target.png")
        let link = dir.appendingPathComponent("link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        _ = ScreenCaptureMarker.mark(link)
        #expect(!ScreenCaptureMarker.isMarked(target), "the file behind a link stays untouched")
    }

    @Test func aNewScreenshotIsMarkedWhenSaved() throws {
        let dir = try folder()
        let result = ScreenshotSaver.write(Data([9, 9]), to: dir.appendingPathComponent("Knippi.png"))
        let url = try result.get()
        #expect(ScreenCaptureMarker.isMarked(url))
    }

    @Test func aSecondScreenshotWithTheSameNameIsMarkedToo() throws {
        let dir = try folder()
        let first = try ScreenshotSaver.write(Data([1]), to: dir.appendingPathComponent("Knippi.png")).get()
        let second = try ScreenshotSaver.write(Data([2]), to: dir.appendingPathComponent("Knippi.png")).get()
        #expect(first != second)
        #expect(ScreenCaptureMarker.isMarked(first) && ScreenCaptureMarker.isMarked(second))
    }

    @Test func replacingTheOriginalKeepsTheMark() throws {
        let dir = try folder()
        let url = try ScreenshotSaver.write(Data([1]), to: dir.appendingPathComponent("Knippi.png")).get()
        let original = try #require(SavedScreenshotFile(url: url))
        #expect(ScreenCaptureMarker.isMarked(url))

        // The editor's save writes atomically: a new file takes the old one's place and the attribute is gone.
        let result = ScreenshotSaver.replaceOriginal(
            Data([2, 2]), original: original, fileExtension: "png",
            replaceWriter: { data, target in try data.write(to: target, options: .atomic) })
        guard case .success(let replaced)? = result else { Issue.record("not replaced"); return }
        #expect(replaced == url)
        #expect(try Data(contentsOf: url) == Data([2, 2]))
        #expect(ScreenCaptureMarker.isMarked(url), "marked again after the atomic rewrite")
    }

    @Test func writeReplacingKeepsTheMarkToo() throws {
        let dir = try folder()
        let url = try ScreenshotSaver.write(Data([1]), to: dir.appendingPathComponent("Knippi.png")).get()
        let original = try #require(SavedScreenshotFile(url: url))
        let outcome = try ScreenshotSaver.write(
            Data([3, 3, 3]), to: dir.appendingPathComponent("Knippi.png"), replacing: original,
            replaceWriter: { data, target in try data.write(to: target, options: .atomic) }).get()
        #expect(outcome.replacedOriginal)
        #expect(ScreenCaptureMarker.isMarked(outcome.url))
    }

    @Test func aFailedReplaceLeavesTheOriginalAndItsMark() throws {
        let dir = try folder()
        let url = try ScreenshotSaver.write(Data([1]), to: dir.appendingPathComponent("Knippi.png")).get()
        let original = try #require(SavedScreenshotFile(url: url))
        struct Boom: Error {}
        let result = ScreenshotSaver.replaceOriginal(
            Data([2]), original: original, fileExtension: "png", replaceWriter: { _, _ in throw Boom() })
        guard case .failure? = result else { Issue.record("expected a failure"); return }
        #expect(ScreenCaptureMarker.isMarked(url))
        #expect(try Data(contentsOf: url) == Data([1]))
    }
}

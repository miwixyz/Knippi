import Foundation
import Testing
@testable import SharedKit

@Suite("ScreenshotSaver")
struct ScreenshotSaverTests {
    private func tempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("knippi-saver-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Creates a missing folder and writes the file")
    func createsFolderAndWrites() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Knippi", isDirectory: true)
        let url = folder.appendingPathComponent("a.png")

        let result = ScreenshotSaver.write(Data([1, 2, 3]), to: url)

        #expect(try result.get() == url)
        #expect(try Data(contentsOf: url) == Data([1, 2, 3]))
    }

    @Test("Folder path that is a regular file fails with folderUnavailable")
    func folderIsRegularFile() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let blocker = root.appendingPathComponent("blocker")
        try Data([0]).write(to: blocker)
        let url = blocker.appendingPathComponent("a.png")

        let result = ScreenshotSaver.write(Data([1]), to: url)

        guard case .failure(let error) = result else {
            Issue.record("expected failure")
            return
        }
        guard case .folderUnavailable(let folder) = error else {
            Issue.record("expected folderUnavailable, got \(error)")
            return
        }
        #expect(folder.standardizedFileURL.path == blocker.standardizedFileURL.path)
    }

    @Test("Never overwrites: a second write with the same name gets \" 2\", a third \" 3\"")
    func neverOverwrites() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Knippi 2026-11-20 um 13.05.12.png")

        let first = try ScreenshotSaver.write(Data([1]), to: url).get()
        let second = try ScreenshotSaver.write(Data([2]), to: url).get()
        let third = try ScreenshotSaver.write(Data([3]), to: url).get()

        #expect(first == url)
        #expect(second.lastPathComponent == "Knippi 2026-11-20 um 13.05.12 2.png")
        #expect(third.lastPathComponent == "Knippi 2026-11-20 um 13.05.12 3.png")
        #expect(try Data(contentsOf: first) == Data([1]), "the first screenshot is untouched")
        #expect(try Data(contentsOf: second) == Data([2]))
        #expect(try Data(contentsOf: third) == Data([3]))
    }

    @Test("Clipboard copy is needed after a failed save only when not already copied")
    func clipboardDecision() {
        #expect(ScreenshotSaver.failureNeedsClipboardCopy(alreadyCopied: false))
        #expect(!ScreenshotSaver.failureNeedsClipboardCopy(alreadyCopied: true))
    }
}

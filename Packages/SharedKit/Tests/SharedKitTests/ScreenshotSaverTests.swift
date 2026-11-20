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

    @Test("Clipboard copy is needed after a failed save only when not already copied")
    func clipboardDecision() {
        #expect(ScreenshotSaver.failureNeedsClipboardCopy(alreadyCopied: false))
        #expect(!ScreenshotSaver.failureNeedsClipboardCopy(alreadyCopied: true))
    }
}

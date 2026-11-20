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

    // MARK: - Editor save replaces the auto-saved original

    @Test("Target: tracked original that exists and is writable is replaced")
    func targetReplacesExistingOriginal() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("A.png")
        try Data([1]).write(to: original)
        let proposed = root.appendingPathComponent("A.png")

        #expect(ScreenshotSaver.target(for: proposed, replacing: original) == .replace(original))
    }

    @Test("Target: no tracked original, missing original, or other format → new numbered file")
    func targetFallsBackToNewFile() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let proposed = root.appendingPathComponent("A.png")
        let missing = root.appendingPathComponent("gone.png")
        let jpeg = root.appendingPathComponent("A.jpg")
        try Data([1]).write(to: jpeg)

        #expect(ScreenshotSaver.target(for: proposed, replacing: nil) == .new(proposed))
        #expect(ScreenshotSaver.target(for: proposed, replacing: missing) == .new(proposed))
        #expect(ScreenshotSaver.target(for: proposed, replacing: jpeg) == .new(proposed))
    }

    @Test("Auto-save writes A.png, editor save with tracked A replaces A.png, no \"A 2.png\"")
    func editorSaveReplacesAutoSavedOriginal() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let name = root.appendingPathComponent("A.png")

        let autoSaved = try ScreenshotSaver.write(Data([1, 1, 1]), to: name).get()
        let outcome = try ScreenshotSaver.write(Data([2, 2]), to: name, replacing: autoSaved).get()

        #expect(outcome == ScreenshotSaveOutcome(url: autoSaved, replacedOriginal: true))
        #expect(try Data(contentsOf: autoSaved) == Data([2, 2]), "the unredacted original is gone")
        let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(files == ["A.png"])
    }

    @Test("Tracked original deleted meanwhile → normal save, not reported as replaced")
    func editorSaveWithDeletedOriginal() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let name = root.appendingPathComponent("A.png")
        let autoSaved = try ScreenshotSaver.write(Data([1]), to: name).get()
        try FileManager.default.removeItem(at: autoSaved)

        let outcome = try ScreenshotSaver.write(Data([2]), to: name, replacing: autoSaved).get()

        #expect(outcome == ScreenshotSaveOutcome(url: name, replacedOriginal: false))
        #expect(try Data(contentsOf: name) == Data([2]))
    }

    @Test("Read-only original is left alone; the edit goes to \"A 2.png\"")
    func editorSaveWithReadOnlyOriginal() throws {
        let root = try tempDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: root.appendingPathComponent("A.png").path)
            try? FileManager.default.removeItem(at: root)
        }
        let name = root.appendingPathComponent("A.png")
        let autoSaved = try ScreenshotSaver.write(Data([1]), to: name).get()
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: autoSaved.path)

        let outcome = try ScreenshotSaver.write(Data([2]), to: name, replacing: autoSaved).get()

        #expect(outcome.replacedOriginal == false)
        #expect(outcome.url.lastPathComponent == "A 2.png")
        #expect(try Data(contentsOf: autoSaved) == Data([1]))
    }

    @Test("Replacing fails although allowed → new numbered file, outcome reports replaceFailed")
    func editorSaveReportsFailedReplace() throws {
        struct Boom: Error {}
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let name = root.appendingPathComponent("A.png")
        let autoSaved = try ScreenshotSaver.write(Data([1]), to: name).get()

        let outcome = try ScreenshotSaver.write(
            Data([2]), to: name, replacing: autoSaved,
            replaceWriter: { _, _ in throw Boom() }
        ).get()

        #expect(outcome.replacedOriginal == false)
        #expect(outcome.replaceFailed)
        #expect(outcome.replaceError != nil)
        #expect(outcome.url.lastPathComponent == "A 2.png")
        #expect(try Data(contentsOf: autoSaved) == Data([1]))
    }

    @Test("Successful replace and plain new saves do not report replaceFailed")
    func noReplaceFailedOnNormalPaths() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let name = root.appendingPathComponent("A.png")
        let autoSaved = try ScreenshotSaver.write(Data([1]), to: name).get()

        let replaced = try ScreenshotSaver.write(Data([2]), to: name, replacing: autoSaved).get()
        let plain = try ScreenshotSaver.write(Data([3]), to: name, replacing: nil).get()

        #expect(!replaced.replaceFailed)
        #expect(!plain.replaceFailed)
    }

    @Test("Clipboard copy is needed after a failed save only when not already copied")
    func clipboardDecision() {
        #expect(ScreenshotSaver.failureNeedsClipboardCopy(alreadyCopied: false))
        #expect(!ScreenshotSaver.failureNeedsClipboardCopy(alreadyCopied: true))
    }
}

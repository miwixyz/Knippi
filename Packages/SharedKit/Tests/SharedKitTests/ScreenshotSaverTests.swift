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

    /// The auto-saved file as the app tracks it: URL plus identity read right after the write.
    private func tracked(_ url: URL) throws -> SavedScreenshotFile {
        try #require(SavedScreenshotFile(url: url))
    }

    /// Audit A2 (21.11.): copy, pin and "Save As" from the editor left the unredacted
    /// auto-saved original in the folder. They now replace it – and never add a new file.
    @Test("replaceOriginal overwrites the tracked original in place")
    func replaceOriginalOverwrites() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("shot.png")
        try Data([1]).write(to: original)
        let tracked = try #require(SavedScreenshotFile(url: original))

        let result = ScreenshotSaver.replaceOriginal(Data([9, 9]), original: tracked, fileExtension: "png")

        #expect(try result?.get() == original)
        #expect(try Data(contentsOf: original) == Data([9, 9]))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 1)
    }

    @Test("replaceOriginal writes nothing when there is no original or it can't be replaced")
    func replaceOriginalNeverCreatesFiles() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(ScreenshotSaver.replaceOriginal(Data([1]), original: nil, fileExtension: "png") == nil)

        let original = root.appendingPathComponent("shot.png")
        try Data([1]).write(to: original)
        let tracked = try #require(SavedScreenshotFile(url: original))
        let otherFormat = ScreenshotSaver.replaceOriginal(Data([2]), original: tracked, fileExtension: "jpg")
        guard case .failure = otherFormat else { Issue.record("expected failure"); return }
        #expect(try Data(contentsOf: original) == Data([1]))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 1)
    }

    @Test("Target: tracked original that exists and is writable is replaced")
    func targetReplacesExistingOriginal() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("A.png")
        try Data([1]).write(to: original)
        let proposed = root.appendingPathComponent("A.png")

        #expect(ScreenshotSaver.target(for: proposed, replacing: try tracked(original)) == .replace(original))
    }

    @Test("Target: no tracked original or missing original → plain new file")
    func targetFallsBackToNewFile() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let proposed = root.appendingPathComponent("A.png")
        let gone = root.appendingPathComponent("gone.png")
        try Data([1]).write(to: gone)
        let trackedGone = try tracked(gone)
        try FileManager.default.removeItem(at: gone)

        #expect(ScreenshotSaver.target(for: proposed, replacing: nil) == .new(proposed))
        #expect(ScreenshotSaver.target(for: proposed, replacing: trackedGone) == .new(proposed))
    }

    @Test("Target: original of another format is kept, and that is reported")
    func targetKeepsOriginalOfOtherFormat() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let proposed = root.appendingPathComponent("A.png")
        let jpeg = root.appendingPathComponent("A.jpg")
        try Data([1]).write(to: jpeg)

        guard case .newKeepingOriginal(let url, _) = ScreenshotSaver.target(for: proposed, replacing: try tracked(jpeg)) else {
            Issue.record("expected newKeepingOriginal")
            return
        }
        #expect(url == proposed)
    }

    @Test("Auto-save writes A.png, editor save with tracked A replaces A.png, no \"A 2.png\"")
    func editorSaveReplacesAutoSavedOriginal() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let name = root.appendingPathComponent("A.png")

        let autoSaved = try ScreenshotSaver.write(Data([1, 1, 1]), to: name).get()
        let outcome = try ScreenshotSaver.write(Data([2, 2]), to: name, replacing: try tracked(autoSaved)).get()

        #expect(outcome == ScreenshotSaveOutcome(url: autoSaved, replacedOriginal: true))
        #expect(!outcome.originalKept)
        #expect(try Data(contentsOf: autoSaved) == Data([2, 2]), "the unredacted original is gone")
        let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(files == ["A.png"])
    }

    @Test("Tracked original deleted meanwhile → normal save, not reported as replaced or kept")
    func editorSaveWithDeletedOriginal() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let name = root.appendingPathComponent("A.png")
        let autoSaved = try tracked(try ScreenshotSaver.write(Data([1]), to: name).get())
        try FileManager.default.removeItem(at: autoSaved.url)

        let outcome = try ScreenshotSaver.write(Data([2]), to: name, replacing: autoSaved).get()

        #expect(outcome == ScreenshotSaveOutcome(url: name, replacedOriginal: false))
        #expect(!outcome.originalKept)
        #expect(try Data(contentsOf: name) == Data([2]))
    }

    @Test("Another file now at the original's path is never overwritten")
    func editorSaveDoesNotOverwriteOtherFileAtSamePath() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let name = root.appendingPathComponent("A.png")
        let autoSaved = try tracked(try ScreenshotSaver.write(Data([1]), to: name).get())
        try FileManager.default.removeItem(at: autoSaved.url)
        try Data([7, 7, 7]).write(to: name)   // e.g. a later capture that got the freed name

        #expect(ScreenshotSaver.target(for: name, replacing: autoSaved) == .new(name))
        let outcome = try ScreenshotSaver.write(Data([2]), to: name, replacing: autoSaved).get()

        #expect(outcome.replacedOriginal == false)
        #expect(!outcome.originalKept, "the original is gone; a plain new save is correct")
        #expect(outcome.url.lastPathComponent == "A 2.png")
        #expect(try Data(contentsOf: name) == Data([7, 7, 7]), "the other file stays intact")
    }

    @Test("A symlink at the original's path is not the tracked file")
    func editorSaveDoesNotReplaceSymlink() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let name = root.appendingPathComponent("A.png")
        let elsewhere = root.appendingPathComponent("elsewhere.png")
        try Data([9]).write(to: elsewhere)
        let autoSaved = try tracked(try ScreenshotSaver.write(Data([1]), to: name).get())
        try FileManager.default.removeItem(at: name)
        try FileManager.default.createSymbolicLink(at: name, withDestinationURL: elsewhere)

        #expect(ScreenshotSaver.target(for: name, replacing: autoSaved) == .new(name))
    }

    @Test("Repeated saves: re-tracking after a replace keeps replacing the same file")
    func repeatedReplaceNeedsFreshIdentity() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let name = root.appendingPathComponent("A.png")
        let autoSaved = try tracked(try ScreenshotSaver.write(Data([1]), to: name).get())

        let first = try ScreenshotSaver.write(Data([2]), to: name, replacing: autoSaved).get()
        #expect(first.replacedOriginal)
        let retracked = try tracked(first.url)
        #expect(retracked != autoSaved, "an atomic replace creates a new file")

        let second = try ScreenshotSaver.write(Data([3]), to: name, replacing: retracked).get()
        #expect(second.replacedOriginal)
        #expect(try Data(contentsOf: name) == Data([3]))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["A.png"])
    }

    @Test("Read-only original is left alone; the edit goes to \"A 2.png\" and that is reported")
    func editorSaveWithReadOnlyOriginal() throws {
        let root = try tempDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: root.appendingPathComponent("A.png").path)
            try? FileManager.default.removeItem(at: root)
        }
        let name = root.appendingPathComponent("A.png")
        let autoSaved = try ScreenshotSaver.write(Data([1]), to: name).get()
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: autoSaved.path)

        let outcome = try ScreenshotSaver.write(Data([2]), to: name, replacing: try tracked(autoSaved)).get()

        #expect(outcome.replacedOriginal == false)
        #expect(outcome.originalKept)
        #expect(outcome.url.lastPathComponent == "A 2.png")
        #expect(try Data(contentsOf: autoSaved) == Data([1]))
    }

    @Test("Locked (\"Geschützt\") original is left alone and that is reported")
    func editorSaveWithLockedOriginal() throws {
        let root = try tempDirectory()
        let name = root.appendingPathComponent("A.png")
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: name.path)
            try? FileManager.default.removeItem(at: root)
        }
        let autoSaved = try ScreenshotSaver.write(Data([1]), to: name).get()
        let trackedOriginal = try tracked(autoSaved)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: autoSaved.path)

        let outcome = try ScreenshotSaver.write(Data([2]), to: name, replacing: trackedOriginal).get()

        #expect(outcome.replacedOriginal == false)
        #expect(outcome.originalKept)
        #expect(outcome.url.lastPathComponent == "A 2.png")
        #expect(try Data(contentsOf: autoSaved) == Data([1]))
    }

    @Test("Original of another format is left alone; the edit is a new file and that is reported")
    func editorSaveWithOtherFormatOriginal() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let jpeg = try ScreenshotSaver.write(Data([1]), to: root.appendingPathComponent("A.jpg")).get()

        let outcome = try ScreenshotSaver.write(
            Data([2]), to: root.appendingPathComponent("A.png"), replacing: try tracked(jpeg)
        ).get()

        #expect(outcome.replacedOriginal == false)
        #expect(outcome.originalKept)
        #expect(outcome.url.lastPathComponent == "A.png")
        #expect(try Data(contentsOf: jpeg) == Data([1]))
    }

    @Test("Replacing fails although allowed → new numbered file, outcome reports replaceFailed")
    func editorSaveReportsFailedReplace() throws {
        struct Boom: Error {}
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let name = root.appendingPathComponent("A.png")
        let autoSaved = try ScreenshotSaver.write(Data([1]), to: name).get()

        let outcome = try ScreenshotSaver.write(
            Data([2]), to: name, replacing: try tracked(autoSaved),
            replaceWriter: { _, _ in throw Boom() }
        ).get()

        #expect(outcome.replacedOriginal == false)
        #expect(outcome.replaceFailed)
        #expect(outcome.originalKept)
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

        let replaced = try ScreenshotSaver.write(Data([2]), to: name, replacing: try tracked(autoSaved)).get()
        let plain = try ScreenshotSaver.write(Data([3]), to: name, replacing: nil).get()

        #expect(!replaced.replaceFailed)
        #expect(!plain.replaceFailed)
        #expect(!plain.originalKept)
    }

    @Test("Clipboard copy is needed after a failed save only when not already copied")
    func clipboardDecision() {
        #expect(ScreenshotSaver.failureNeedsClipboardCopy(alreadyCopied: false))
        #expect(!ScreenshotSaver.failureNeedsClipboardCopy(alreadyCopied: true))
    }
}

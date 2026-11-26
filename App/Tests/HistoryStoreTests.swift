import AppKit
import SwiftUI
import XCTest
import OCRKit
import SharedKit
@testable import Knippi

@MainActor
final class HistoryStoreTests: XCTestCase {

    private var root: URL!
    private var indexFile: URL!
    private var suite: String!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("knippi-history-app-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        indexFile = root.appendingPathComponent("index/SearchIndex.json")
        // One fixed suite, emptied before and after every test (the tests of this class run
        // one after another). A fresh UUID suite per test left one .plist per test behind.
        suite = "knippi.history.tests"
        UserDefaults().removePersistentDomain(forName: suite)
    }

    override func tearDown() async throws {
        UserDefaults().removePersistentDomain(forName: suite)
        pasteboard?.releaseGlobally()
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Helpers

    private func png(_ name: String, age: TimeInterval) throws {
        let url = root.appendingPathComponent("shots").appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let ctx = CGContext(data: nil, width: 320, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.8, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 320, height: 200))
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path)
    }

    private var pasteboard: NSPasteboard!
    private var trashed: [URL] = []
    private var trashFails = false
    private var editorOpened: [URL] = []

    private func makeStore(autoSave: Bool = false, keep: Int = 50, texts: [String: String] = [:]) -> (HistoryStore, SearchIndex, AppSettings) {
        let defaults = UserDefaults(suiteName: suite)!
        let settings = AppSettings(defaults: defaults)
        settings.setExportLocation(root.appendingPathComponent("shots"))
        settings.screenshotAutoSave = autoSave
        settings.historyKeepCount = keep
        let index = SearchIndex(fileURL: indexFile, recognizer: { url in texts[url.lastPathComponent] ?? "" })
        pasteboard = NSPasteboard(name: NSPasteboard.Name("knippi.history.tests.\(UUID().uuidString)"))
        let store = HistoryStore(
            settings: settings, index: index, pasteboard: pasteboard,
            trash: { [unowned self] url in
                if trashFails { throw CocoaError(.fileWriteNoPermission) }
                trashed.append(url)
                // Like the real Trash: the file leaves its folder and lands somewhere else.
                let bin = root.appendingPathComponent("Trash", isDirectory: true)
                try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
                let target = bin.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: target)
                return target
            },
            openInEditor: { [unowned self] url in editorOpened.append(url) })
        return (store, index, settings)
    }

    /// Waits until the condition holds, at most `seconds`.
    private func wait(_ seconds: Double = 5, until condition: () -> Bool) async {
        let end = Date().addingTimeInterval(seconds)
        while !condition() && Date() < end { try? await Task.sleep(for: .milliseconds(50)) }
    }

    // MARK: Tests

    func testListsNewestFirstIncludingMonthlyFolders() async throws {
        try png("old.png", age: 300)
        try png("2026-11/new.png", age: 10)
        let (store, _, _) = makeStore()
        store.activate()
        await wait { store.items.count == 2 }
        store.deactivate()
        XCTAssertEqual(store.items.map(\.url.lastPathComponent), ["new.png", "old.png"])
    }

    func testSearchFindsOnlyScreenshotsWithThatText() async throws {
        try png("a.png", age: 30)
        try png("b.png", age: 20)
        let (store, _, _) = makeStore(texts: ["a.png": "Rechnung 4711", "b.png": "Fahrplan"])
        store.activate()
        await wait { store.items.count == 2 && !store.isIndexing }
        await wait { store.items.count == 2 }
        store.query = "rechnung"
        await wait { store.matches.count == 1 }
        store.deactivate()
        XCTAssertEqual(store.matches.map(\.url.lastPathComponent), ["a.png"])
        store.query = ""
        XCTAssertEqual(store.matches.count, 2)
    }

    func testNothingIsReadWhileInactive() async throws {
        try png("a.png", age: 30)
        let (store, index, _) = makeStore(texts: ["a.png": "x"])
        try? await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(store.items.isEmpty)
        let count = await index.count
        XCTAssertEqual(count, 0)
    }

    func testAutoSaveNoticeFollowsTheSetting() async throws {
        try png("a.png", age: 30)
        let (store, _, settings) = makeStore(autoSave: false)
        store.activate()
        await wait { !store.items.isEmpty }
        XCTAssertTrue(store.autoSaveIsOff)
        store.enableAutoSave()
        store.deactivate()
        XCTAssertFalse(store.autoSaveIsOff)
        XCTAssertTrue(settings.screenshotAutoSave)
    }

    func testReplacedFileLosesItsOldTextAtOnce() async throws {
        try png("a.png", age: 30)
        let (store, index, _) = makeStore(texts: ["a.png": "Kontonummer 123"])
        store.activate()
        await wait { store.items.count == 1 }
        await wait { !store.isIndexing }
        var readCount = await index.count
        for _ in 0..<40 where readCount == 0 {
            try? await Task.sleep(for: .milliseconds(100)); readCount = await index.count
        }
        XCTAssertEqual(readCount, 1)

        let file = store.items[0].url
        store.deactivate()                       // no re-reading until we look
        NotificationCenter.default.post(name: .screenshotFileReplaced, object: file)
        var after = 1
        for _ in 0..<40 where after != 0 {
            try? await Task.sleep(for: .milliseconds(50)); after = await index.count
        }
        XCTAssertEqual(after, 0)
    }

    // MARK: Off by default, switching, deleting

    private func waitForIndexCount(_ index: SearchIndex, _ target: Int) async -> Int {
        var count = await index.count
        for _ in 0..<80 where count != target {
            try? await Task.sleep(for: .milliseconds(50))
            count = await index.count
        }
        return count
    }

    func testOffByDefaultReadsAndKeepsNothing() async throws {
        try png("a.png", age: 30)
        let (store, index, _) = makeStore(keep: 0, texts: ["a.png": "geheim"])
        store.activate()
        try? await Task.sleep(for: .milliseconds(500))
        XCTAssertFalse(store.isOn)
        XCTAssertTrue(store.items.isEmpty)
        let count = await index.count
        XCTAssertEqual(count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: indexFile.path))
        store.deactivate()
    }

    func testTurningOnInTheWindowStartsReading() async throws {
        try png("a.png", age: 30)
        let (store, _, settings) = makeStore(keep: 0, texts: ["a.png": "x"])
        store.activate()                              // window open, history off
        store.enableHistory()
        await wait { store.items.count == 1 }
        store.deactivate()
        XCTAssertTrue(store.isOn)
        XCTAssertEqual(settings.historyKeepCount, HistoryStore.defaultKeepCount)
        XCTAssertEqual(store.items.count, 1)
    }

    func testKeepCountLimitsTheList() async throws {
        for n in 0..<30 { try png("s\(n).png", age: Double(n + 1)) }
        let (store, _, _) = makeStore(keep: 25)
        store.activate()
        await wait { store.items.count == 25 }
        store.deactivate()
        XCTAssertEqual(store.items.count, 25)
    }

    func testSwitchingOffDeletesTheStoredText() async throws {
        try png("a.png", age: 30)
        let (store, index, settings) = makeStore(texts: ["a.png": "Kontonummer"])
        store.activate()
        await wait { store.items.count == 1 }
        let before = await waitForIndexCount(index, 1)
        XCTAssertEqual(before, 1)

        settings.historyKeepCount = 0
        NotificationCenter.default.post(name: .historySettingsChanged, object: nil)
        let after = await waitForIndexCount(index, 0)
        XCTAssertEqual(after, 0)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: indexFile.path))
        store.deactivate()
    }

    func testDeleteIndexRequestRemovesTheText() async throws {
        try png("a.png", age: 30)
        let (store, index, _) = makeStore(texts: ["a.png": "x"])
        store.activate()
        _ = await waitForIndexCount(index, 1)
        store.deactivate()                             // no re-reading after the delete
        NotificationCenter.default.post(name: .historyIndexDeleteRequested, object: nil)
        let count = await waitForIndexCount(index, 0)
        XCTAssertEqual(count, 0)
    }

    // MARK: Actions

    func testCopyPutsTheImageOnTheClipboard() async throws {
        try png("a.png", age: 30)
        let (store, _, _) = makeStore()
        store.activate()
        await wait { store.items.count == 1 }
        store.copy(store.items[0])
        store.deactivate()
        XCTAssertEqual(store.notice, HistoryStore.Notice(text: String(localized: "Copied"), isError: false))
        XCTAssertNotNil(NSImage(pasteboard: pasteboard))
    }

    func testCopyOfAMissingFileSaysSo() async throws {
        let (store, _, _) = makeStore()
        let ghost = HistoryScanner.Item(url: root.appendingPathComponent("weg.png"), modified: Date())
        store.copy(ghost)
        XCTAssertEqual(store.notice?.isError, true)
        XCTAssertNil(NSImage(pasteboard: pasteboard))
    }

    func testTrashRemovesTheItemAndItsText() async throws {
        try png("a.png", age: 30)
        try png("b.png", age: 20)
        let (store, index, _) = makeStore(texts: ["a.png": "eins", "b.png": "zwei"])
        store.activate()
        await wait { store.items.count == 2 }
        _ = await waitForIndexCount(index, 2)
        let target = try XCTUnwrap(store.items.first { $0.url.lastPathComponent == "a.png" })
        store.deactivate()
        store.moveToTrash(target)
        XCTAssertEqual(trashed, [target.url])
        XCTAssertEqual(store.items.map(\.url.lastPathComponent), ["b.png"])
        let count = await waitForIndexCount(index, 1)
        XCTAssertEqual(count, 1)
    }

    func testFailedTrashKeepsTheItemAndReportsIt() async throws {
        try png("a.png", age: 30)
        let (store, _, _) = makeStore()
        store.activate()
        await wait { store.items.count == 1 }
        store.deactivate()
        trashFails = true
        store.moveToTrash(store.items[0])
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.notice?.isError, true)
    }

    func testOpenInEditorHandsTheFileOver() async throws {
        try png("a.png", age: 30)
        let (store, _, _) = makeStore()
        store.activate()
        await wait { store.items.count == 1 }
        store.deactivate()
        store.openInEditor(store.items[0])
        XCTAssertEqual(editorOpened, [store.items[0].url])
    }

    func testTurnOffInTheWindowSwitchesHistoryOffAndDeletesText() async throws {
        try png("a.png", age: 30)
        let (store, index, settings) = makeStore(texts: ["a.png": "Kontonummer"])
        store.activate()
        _ = await waitForIndexCount(index, 1)
        store.turnOff()
        XCTAssertFalse(store.isOn)
        XCTAssertEqual(settings.historyKeepCount, 0)
        XCTAssertTrue(store.items.isEmpty)
        let count = await waitForIndexCount(index, 0)
        XCTAssertEqual(count, 0)
        store.deactivate()
    }

    func testDeleteStoredTextFromTheWindowMenuSaysSo() async throws {
        try png("a.png", age: 30)
        let (store, index, _) = makeStore(texts: ["a.png": "x"])
        store.activate()
        _ = await waitForIndexCount(index, 1)
        store.deactivate()
        store.deleteStoredText()
        XCTAssertEqual(store.notice?.isError, false)
        let count = await waitForIndexCount(index, 0)
        XCTAssertEqual(count, 0)
    }

    // MARK: Selection, undo, Return, Quick Look

    private func loaded(_ names: [String], texts: [String: String] = [:]) async throws -> HistoryStore {
        for (n, name) in names.enumerated() { try png(name, age: Double(10 * (n + 1))) }
        let (store, _, _) = makeStore(texts: texts)
        store.activate()
        await wait { store.items.count == names.count }
        store.deactivate()
        return store
    }

    func testPlainClickChoosesOnlyThatOneWithoutCopying() async throws {
        let store = try await loaded(["a.png", "b.png"])
        store.click(store.items[0], extend: true)
        store.click(store.items[1], extend: false)
        XCTAssertEqual(store.selected, [store.items[1].url])
        XCTAssertNil(NSImage(pasteboard: pasteboard))
    }

    func testExtendedClickAddsAndRemovesWithoutCopying() async throws {
        let store = try await loaded(["a.png", "b.png", "c.png"])
        store.click(store.items[0], extend: true)
        store.click(store.items[2], extend: true)
        XCTAssertEqual(store.selected, [store.items[0].url, store.items[2].url])
        XCTAssertNil(NSImage(pasteboard: pasteboard))
        store.click(store.items[0], extend: true)
        XCTAssertEqual(store.selected, [store.items[2].url])
        XCTAssertEqual(store.targets(for: store.items[2]).map(\.url), [store.items[2].url])
        XCTAssertEqual(store.targets(for: store.items[1]).map(\.url), [store.items[1].url])   // not chosen: just it
    }

    func testSelectAllThenCopyPutsEveryImageOnTheClipboard() async throws {
        let store = try await loaded(["a.png", "b.png", "c.png"])
        store.selectAll()
        store.copy(store.selectedItems)
        let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage]
        XCTAssertEqual(images?.count, 3)
        XCTAssertEqual(store.notice?.isError, false)
        store.clearSelection()
        XCTAssertTrue(store.selected.isEmpty)
    }

    func testTrashSeveralThenUndoPutsThemBackWhereTheyWere() async throws {
        let store = try await loaded(["a.png", "b.png", "c.png"])
        let originals = store.items.map(\.url)
        store.click(store.items[0], extend: true)
        store.click(store.items[1], extend: true)
        let chosen = store.selectedItems
        store.moveToTrash(chosen)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertTrue(store.canUndoTrash)
        for url in chosen.map(\.url) { XCTAssertFalse(FileManager.default.fileExists(atPath: url.path)) }

        store.undoTrash()
        for url in originals { XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), url.lastPathComponent) }
        XCTAssertFalse(store.canUndoTrash)
        XCTAssertEqual(store.notice?.text, String(localized: "Restored"))
        XCTAssertEqual(store.selected, Set(chosen.map(\.url)))
    }

    func testUndoNeverOverwritesAFileThatIsThereAgain() async throws {
        let store = try await loaded(["a.png"])
        let original = store.items[0].url
        store.moveToTrash(store.items[0])
        try Data("neu".utf8).write(to: original)                 // someone saved a new file under that name
        store.undoTrash()
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "neu")
        XCTAssertEqual(store.notice?.isError, true)
        XCTAssertTrue(store.canUndoTrash)                         // still undoable once the name is free
    }

    func testUndoWithNothingToUndoDoesNothing() async throws {
        let store = try await loaded(["a.png"])
        store.undoTrash()
        XCTAssertNil(store.notice)
    }

    func testReturnInSearchCopiesTheNewestMatch() async throws {
        let store = try await loaded(["a.png", "b.png"], texts: ["a.png": "Rechnung", "b.png": "Rechnung Mai"])
        store.activate()
        for _ in 0..<60 where store.isIndexing || store.matches.count != 2 { try? await Task.sleep(for: .milliseconds(50)) }
        store.query = "rechnung"
        await wait { store.matches.count == 2 }
        store.copyFirstMatch()
        store.deactivate()
        XCTAssertEqual(store.selected, [store.matches[0].url])
        XCTAssertNotNil(NSImage(pasteboard: pasteboard))
    }

    func testReturnWithoutMatchesDoesNothing() async throws {
        let store = try await loaded(["a.png"])
        store.query = "gibtesnicht"
        try? await Task.sleep(for: .milliseconds(300))
        store.copyFirstMatch()
        XCTAssertNil(NSImage(pasteboard: pasteboard))
    }

    func testQuickLookStartsAtTheFirstChosenAndCoversTheWholeList() async throws {
        let store = try await loaded(["a.png", "b.png", "c.png"])
        XCTAssertEqual(store.quickLookTargets()?.index, 0)          // nothing chosen: start at the first
        store.click(store.items[2], extend: true)
        let target = try XCTUnwrap(store.quickLookTargets())
        XCTAssertEqual(target.urls.count, 3)
        XCTAssertEqual(target.index, 2)
    }

    func testQuickLookWithNoScreenshotsIsNil() async throws {
        let (store, _, _) = makeStore()
        XCTAssertNil(store.quickLookTargets())
    }

    /// Renders the window content to a PNG when KNIPPI_SNAPSHOT_DIR is set (for a visual check).
    func testRenderSnapshotsForVisualCheck() async throws {
        guard let dir = ProcessInfo.processInfo.environment["KNIPPI_SNAPSHOT_DIR"] else { return }
        FamilyTheme.app = .knippi
        try png("a.png", age: 60)
        try png("b.png", age: 600)
        try png("2026-11/c.png", age: 3600)
        for (name, autoSave, query) in [("history-off", false, "__off__"),
                                        ("history-grid-autosave-off", false, ""),
                                        ("history-search", true, "rechnung"),
                                        ("history-empty-autosave-off", false, "__empty__")] {
            let (store, _, _) = makeStore(autoSave: autoSave, keep: query == "__off__" ? 0 : 50,
                                          texts: ["a.png": "Rechnung 4711", "b.png": "Fahrplan", "c.png": "Quittung"])
            if query == "__empty__" {
                let defaults = UserDefaults(suiteName: suite)!
                AppSettings(defaults: defaults).setExportLocation(root.appendingPathComponent("leer"))
                try FileManager.default.createDirectory(at: root.appendingPathComponent("leer"), withIntermediateDirectories: true)
            }
            store.activate()
            if query != "__off__" { await wait { store.items.count == 3 && !store.isIndexing } }
            try? await Task.sleep(for: .milliseconds(800))
            if query != "__empty__" && query != "__off__" { store.query = query; try? await Task.sleep(for: .milliseconds(500)) }
            let host = NSHostingView(rootView: HistoryView(store: store))
            host.frame = NSRect(x: 0, y: 0, width: 640, height: 520)
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(600))
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
            store.deactivate()
        }
    }
}

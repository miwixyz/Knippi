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
        suite = "knippi.history.tests.\(UUID().uuidString)"
    }

    override func tearDown() async throws {
        UserDefaults().removePersistentDomain(forName: suite)
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

    private func makeStore(autoSave: Bool = false, texts: [String: String] = [:]) -> (HistoryStore, SearchIndex, AppSettings) {
        let defaults = UserDefaults(suiteName: suite)!
        let settings = AppSettings(defaults: defaults)
        settings.setExportLocation(root.appendingPathComponent("shots"))
        settings.screenshotAutoSave = autoSave
        let index = SearchIndex(fileURL: indexFile, recognizer: { url in texts[url.lastPathComponent] ?? "" })
        return (HistoryStore(settings: settings, index: index), index, settings)
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

    /// Renders the window content to a PNG when KNIPPI_SNAPSHOT_DIR is set (for a visual check).
    func testRenderSnapshotsForVisualCheck() async throws {
        guard let dir = ProcessInfo.processInfo.environment["KNIPPI_SNAPSHOT_DIR"] else { return }
        FamilyTheme.app = .knippi
        try png("a.png", age: 60)
        try png("b.png", age: 600)
        try png("2026-11/c.png", age: 3600)
        for (name, autoSave, query) in [("history-grid-autosave-off", false, ""),
                                        ("history-search", true, "rechnung"),
                                        ("history-empty-autosave-off", false, "__empty__")] {
            let (store, _, _) = makeStore(autoSave: autoSave,
                                          texts: ["a.png": "Rechnung 4711", "b.png": "Fahrplan", "c.png": "Quittung"])
            if query == "__empty__" {
                let defaults = UserDefaults(suiteName: suite)!
                AppSettings(defaults: defaults).setExportLocation(root.appendingPathComponent("leer"))
                try FileManager.default.createDirectory(at: root.appendingPathComponent("leer"), withIntermediateDirectories: true)
            }
            store.activate()
            await wait { store.items.count == 3 && !store.isIndexing }
            try? await Task.sleep(for: .milliseconds(800))
            if query != "__empty__" { store.query = query; try? await Task.sleep(for: .milliseconds(500)) }
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

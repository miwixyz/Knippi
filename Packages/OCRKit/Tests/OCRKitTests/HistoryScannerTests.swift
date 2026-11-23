import Testing
import Foundation
@testable import OCRKit

@Suite("History scanner")
struct HistoryScannerTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("knippi-history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func make(_ root: URL, _ path: String, age: TimeInterval) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0]).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_700_000_000 - age)], ofItemAtPath: url.path)
        return url
    }

    @Test func newestFirstAndLimited() throws {
        let root = try folder()
        let old = try make(root, "old.png", age: 300)
        let mid = try make(root, "mid.png", age: 200)
        let new = try make(root, "new.png", age: 100)
        #expect(HistoryScanner.scan(folder: root, limit: 10).map(\.url.lastPathComponent)
                == [new, mid, old].map(\.lastPathComponent))
        #expect(HistoryScanner.scan(folder: root, limit: 2).count == 2)
        #expect(HistoryScanner.scan(folder: root, limit: 0).isEmpty)
    }

    @Test func monthlySubfoldersCount() throws {
        let root = try folder()
        try make(root, "2026-11/a.png", age: 10)
        try make(root, "2026-10/b.jpg", age: 20)
        #expect(HistoryScanner.scan(folder: root, limit: 10).count == 2)
    }

    @Test func onlyImagesNoHiddenNoLinks() throws {
        let root = try folder()
        try make(root, "ok.png", age: 10)
        try make(root, "notes.txt", age: 10)
        try make(root, "clip.mp4", age: 10)
        try make(root, ".hidden.png", age: 10)
        try make(root, ".trash/inside.png", age: 10)
        let outside = try make(try folder(), "elsewhere.png", age: 10)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link.png"), withDestinationURL: outside)
        #expect(HistoryScanner.scan(folder: root, limit: 10).map(\.url.lastPathComponent) == ["ok.png"])
    }

    @Test func missingFolderIsEmpty() {
        let nowhere = FileManager.default.temporaryDirectory.appendingPathComponent("nicht-da-\(UUID().uuidString)")
        #expect(HistoryScanner.scan(folder: nowhere, limit: 10).isEmpty)
    }

    @Test func doesNotWalkDeeperThanTheMonthlyFolders() throws {
        let root = try folder()
        try make(root, "top.png", age: 10)
        try make(root, "2026-11/month.png", age: 20)
        try make(root, "2026-11/deeper/too-deep.png", age: 30)
        try make(root, "a/b/c/way-too-deep.png", age: 40)
        #expect(HistoryScanner.scan(folder: root, limit: 10).map(\.url.lastPathComponent) == ["top.png", "month.png"])
        #expect(HistoryScanner.scan(folder: root, limit: 10, maxDepth: 4).count == 4)
    }
}

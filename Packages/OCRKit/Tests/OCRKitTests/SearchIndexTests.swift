import Testing
import Foundation
@testable import OCRKit
import CoreGraphics
import CoreText
import ImageIO

/// Counts recognizer calls and hands out canned text per file name.
private final class Reader: @unchecked Sendable {
    private let lock = NSLock()
    private var texts: [String: String?]
    private(set) var calls: [String] = []
    var onRead: (@Sendable (URL) -> Void)?

    init(_ texts: [String: String?]) { self.texts = texts }

    func set(_ name: String, _ text: String?) {
        lock.withLock { texts[name] = .some(text) }
    }

    private func record(_ url: URL) -> String? {
        lock.withLock {
            calls.append(url.lastPathComponent)
            return texts[url.lastPathComponent] ?? nil
        }
    }

    var recognizer: SearchIndex.Recognizer {
        { [self] url in
            let result = record(url)
            onRead?(url)
            return result
        }
    }

    var callCount: Int { lock.withLock { calls.count } }
}

private func makeFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("knippi-searchindex-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@discardableResult
private func touch(_ folder: URL, _ name: String, modified: Date = Date(timeIntervalSince1970: 1_700_000_000)) throws -> URL {
    let url = folder.appendingPathComponent(name)
    try Data([0]).write(to: url)
    try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    return url
}

@Suite("Search index")
struct SearchIndexTests {

    // MARK: Folding

    @Test func foldIgnoresCaseAccentsAndWidth() {
        #expect(SearchIndex.fold("Menú") == "menu")
        #expect(SearchIndex.fold("MENÜ") == "menu")
        #expect(SearchIndex.fold("ＭＥＮＵ") == "menu")
    }

    @Test func wordsAreSplitAndFolded() {
        #expect(SearchIndex.words("  Rechnung   Müller 4711 ") == ["rechnung", "muller", "4711"])
        #expect(SearchIndex.words("   ").isEmpty)
    }

    // MARK: Reading

    @Test func readsNewFilesOnceAndNotAgain() async throws {
        let folder = try makeFolder()
        let a = try touch(folder, "a.png"), b = try touch(folder, "b.jpg")
        let reader = Reader(["a.png": "Hallo Welt", "b.jpg": "Rechnung 4711"])
        let index = SearchIndex(fileURL: folder.appendingPathComponent("idx.json"), recognizer: reader.recognizer)

        #expect(await index.update([a, b]) == 2)
        #expect(await index.update([a, b]) == 0)
        #expect(reader.callCount == 2)
        #expect(await index.count == 2)
    }

    @Test func changedFileIsReadAgain() async throws {
        let folder = try makeFolder()
        let a = try touch(folder, "a.png")
        let reader = Reader(["a.png": "alt"])
        let index = SearchIndex(fileURL: folder.appendingPathComponent("idx.json"), recognizer: reader.recognizer)
        await index.update([a])
        #expect(await index.search("alt", in: [a]) == [a])

        // The editor replaced the file in place: same path, new date, new content.
        try touch(folder, "a.png", modified: Date(timeIntervalSince1970: 1_700_000_500))
        reader.set("a.png", "neu")
        #expect(await index.isCurrent(a) == false)
        await index.update([a])

        #expect(await index.search("neu", in: [a]) == [a])
        #expect(await index.search("alt", in: [a]).isEmpty)
    }

    @Test func goneFileLosesItsEntry() async throws {
        let folder = try makeFolder()
        let a = try touch(folder, "a.png"), b = try touch(folder, "b.png")
        let reader = Reader(["a.png": "eins", "b.png": "zwei"])
        let index = SearchIndex(fileURL: folder.appendingPathComponent("idx.json"), recognizer: reader.recognizer)
        await index.update([a, b])
        try FileManager.default.removeItem(at: b)

        await index.update([a])

        #expect(await index.count == 1)
        #expect(await index.search("zwei", in: [a, b]).isEmpty)
    }

    @Test func forgetDropsOneFileAtOnce() async throws {
        let folder = try makeFolder()
        let a = try touch(folder, "a.png")
        let reader = Reader(["a.png": "geheim"])
        let file = folder.appendingPathComponent("idx.json")
        let index = SearchIndex(fileURL: file, recognizer: reader.recognizer)
        await index.update([a])
        await index.forget(a)

        #expect(await index.count == 0)
        // Also gone from disk: a new instance does not know it.
        let reopened = SearchIndex(fileURL: file, recognizer: reader.recognizer)
        #expect(await reopened.count == 0)
    }

    @Test func failedReadIsNotStoredAndTriedAgain() async throws {
        let folder = try makeFolder()
        let a = try touch(folder, "a.png")
        let reader = Reader(["a.png": nil])
        let index = SearchIndex(fileURL: folder.appendingPathComponent("idx.json"), recognizer: reader.recognizer)

        #expect(await index.update([a]) == 0)
        #expect(await index.count == 0)

        reader.set("a.png", "jetzt da")
        #expect(await index.update([a]) == 1)
        #expect(await index.search("jetzt", in: [a]) == [a])
    }

    @Test func fileReplacedWhileReadingIsNotStored() async throws {
        let folder = try makeFolder()
        let a = try touch(folder, "a.png")
        let reader = Reader(["a.png": "vom alten Bild"])
        reader.onRead = { url in
            // Replaced during recognition: the text read belongs to the old file.
            try? FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 1_700_009_999)], ofItemAtPath: url.path)
        }
        let index = SearchIndex(fileURL: folder.appendingPathComponent("idx.json"), recognizer: reader.recognizer)

        #expect(await index.update([a]) == 0)
        #expect(await index.count == 0)
    }

    @Test func nonImagesAreIgnored() async throws {
        let folder = try makeFolder()
        let notes = try touch(folder, "notes.txt"), movie = try touch(folder, "clip.mp4")
        let reader = Reader([:])
        let index = SearchIndex(fileURL: folder.appendingPathComponent("idx.json"), recognizer: reader.recognizer)

        #expect(await index.update([notes, movie]) == 0)
        #expect(reader.callCount == 0)
    }

    @Test func uppercaseExtensionCounts() async throws {
        let folder = try makeFolder()
        let a = try touch(folder, "SCREEN.PNG")
        let reader = Reader(["SCREEN.PNG": "text"])
        let index = SearchIndex(fileURL: folder.appendingPathComponent("idx.json"), recognizer: reader.recognizer)
        #expect(await index.update([a]) == 1)
    }

    // MARK: Searching

    @Test func everyWordMustBeInTheFile() async throws {
        let folder = try makeFolder()
        let a = try touch(folder, "a.png"), b = try touch(folder, "b.png"), c = try touch(folder, "c.png")
        let reader = Reader(["a.png": "Rechnung 4711 Müller", "b.png": "Rechnung 0815", "c.png": "nichts"])
        let index = SearchIndex(fileURL: folder.appendingPathComponent("idx.json"), recognizer: reader.recognizer)
        await index.update([a, b, c])

        #expect(await index.search("rechnung", in: [a, b, c]) == [a, b])
        #expect(await index.search("rechnung muller", in: [a, b, c]) == [a])
        #expect(await index.search("rechnung xyz", in: [a, b, c]).isEmpty)
    }

    @Test func emptyQueryReturnsAllInGivenOrder() async throws {
        let folder = try makeFolder()
        let a = try touch(folder, "a.png"), b = try touch(folder, "b.png")
        let index = SearchIndex(fileURL: folder.appendingPathComponent("idx.json"), recognizer: Reader([:]).recognizer)
        #expect(await index.search("  ", in: [b, a]) == [b, a])
    }

    @Test func fileNotYetReadIsNotFoundByAWord() async throws {
        let folder = try makeFolder()
        let a = try touch(folder, "a.png")
        let index = SearchIndex(fileURL: folder.appendingPathComponent("idx.json"), recognizer: Reader([:]).recognizer)
        #expect(await index.search("irgendwas", in: [a]).isEmpty)
    }

    // MARK: On disk

    @Test func survivesRestartWithoutReading() async throws {
        let folder = try makeFolder()
        let a = try touch(folder, "a.png")
        let file = folder.appendingPathComponent("idx.json")
        let first = Reader(["a.png": "Gedächtnis"])
        await SearchIndex(fileURL: file, recognizer: first.recognizer).update([a])

        let second = Reader([:])
        let reopened = SearchIndex(fileURL: file, recognizer: second.recognizer)
        #expect(await reopened.update([a]) == 0)
        #expect(second.callCount == 0)
        #expect(await reopened.search("gedachtnis", in: [a]) == [a])
    }

    @Test func indexFileIsPrivateToTheUser() async throws {
        let folder = try makeFolder()
        let a = try touch(folder, "a.png")
        let sub = folder.appendingPathComponent("Knippi", isDirectory: true)
        let file = sub.appendingPathComponent("idx.json")
        let index = SearchIndex(fileURL: file, recognizer: Reader(["a.png": "x"]).recognizer)
        await index.update([a])

        let fileMode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        let dirMode = try FileManager.default.attributesOfItem(atPath: sub.path)[.posixPermissions] as? Int
        #expect(fileMode == 0o600)
        #expect(dirMode == 0o700)
        // No leftovers from writing.
        let names = try FileManager.default.contentsOfDirectory(atPath: sub.path)
        #expect(names == ["idx.json"])
    }

    @Test func rewriteKeepsPrivateRights() async throws {
        let folder = try makeFolder()
        let a = try touch(folder, "a.png"), b = try touch(folder, "b.png")
        let file = folder.appendingPathComponent("idx.json")
        let index = SearchIndex(fileURL: file, recognizer: Reader(["a.png": "x", "b.png": "y"]).recognizer)
        await index.update([a])
        await index.update([a, b])

        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    @Test func removeAllDeletesTheFile() async throws {
        let folder = try makeFolder()
        let a = try touch(folder, "a.png")
        let file = folder.appendingPathComponent("idx.json")
        let index = SearchIndex(fileURL: file, recognizer: Reader(["a.png": "x"]).recognizer)
        await index.update([a])
        #expect(FileManager.default.fileExists(atPath: file.path))

        await index.removeAll()

        #expect(await index.count == 0)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func damagedIndexFileStartsEmpty() async throws {
        let folder = try makeFolder()
        let file = folder.appendingPathComponent("idx.json")
        try Data("{ kaputt".utf8).write(to: file)
        let index = SearchIndex(fileURL: file, recognizer: Reader([:]).recognizer)
        #expect(await index.count == 0)
    }
}

// MARK: - Audit 23.11.: concurrent removeAll, tall captures

/// Holds a recognizer until the test lets it go, so an update can be paused mid-read.
private actor Gate {
    private var started = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func enter() async {
        started += 1
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() { isOpen = true; waiters.forEach { $0.resume() }; waiters = [] }
    func hasStarted() -> Bool { started > 0 }
}

/// A white PNG with one line of black text near the bottom.
private func writeCapture(width: Int, height: Int, text: String, fontSize: CGFloat = 56, to url: URL) throws {
    let space = CGColorSpaceCreateDeviceRGB()
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
    let attributed = NSAttributedString(string: text, attributes: [
        .font: font, .foregroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1)])
    let line = CTLineCreateWithAttributedString(attributed)
    context.textPosition = CGPoint(x: 60, y: 120)   // bottom of the image (origin bottom-left)
    CTLineDraw(line, context)
    let image = try #require(context.makeImage())
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
}

@Suite("Search index, audit findings")
struct SearchIndexAuditTests {

    @Test func removeAllDuringUpdateStaysEmpty() async throws {
        let folder = try makeFolder()
        let a = try touch(folder, "a.png"), b = try touch(folder, "b.png")
        let gate = Gate()
        let file = folder.appendingPathComponent("idx.json")
        let index = SearchIndex(fileURL: file, recognizer: { _ in
            await gate.enter()
            return "geheim"
        })

        let running = Task { await index.update([a, b]) }
        while !(await gate.hasStarted()) { try await Task.sleep(for: .milliseconds(5)) }
        await index.removeAll()          // user chose "Index löschen" while reading
        await gate.open()
        _ = await running.value

        #expect(await index.count == 0)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func normalCaptureIsReadable() async throws {
        let folder = try makeFolder()
        let url = folder.appendingPathComponent("normal.png")
        try writeCapture(width: 1600, height: 900, text: "Quittung 4711", to: url)
        let text = try #require(await SearchIndex.visionRecognizer(url))
        #expect(SearchIndex.fold(text).contains("quittung"))
    }

    @Test func tallScrollCaptureIsReadable() async throws {
        let folder = try makeFolder()
        let url = folder.appendingPathComponent("tall.png")
        // Like a real scroll capture (measured 1513 x 30 439 px): ordinary body text
        // (28 px on a Retina screen) at the very bottom of a very tall image.
        try writeCapture(width: 1500, height: 30_000, text: "Quittung 4711", fontSize: 28, to: url)
        let text = try #require(await SearchIndex.visionRecognizer(url))
        #expect(SearchIndex.fold(text).contains("quittung"))
    }
}

@Suite("Search index, geometry and leftovers")
struct SearchIndexGeometryTests {
    @Test func normalScreenshotIsOneSliceAndShrunkToTheShortSide() {
        // 2880 x 1800 (Retina 16:10): short side 1800 -> 1500, one slice of 2400 x 1500.
        let factor = SearchIndex.shrinkFactor(width: 2880, height: 1800)
        #expect(abs(factor - 1500.0 / 1800.0) < 0.0001)
        #expect(SearchIndex.slices(width: 2400, height: 1500).count == 1)
    }

    @Test func smallImageIsNotEnlarged() {
        #expect(SearchIndex.shrinkFactor(width: 800, height: 600) == 1)
    }

    @Test func tallImageKeepsItsWidthUntilThePixelBudget() {
        // 1513 x 30 439 = 46 MP: only the 24 MP budget shrinks it, to about 72 %.
        let factor = SearchIndex.shrinkFactor(width: 1513, height: 30_439)
        #expect(factor > 0.70 && factor < 0.74)
    }

    @Test func slicesCoverTheLongSideWithOverlap() {
        let slices = SearchIndex.slices(width: 1400, height: 7000)
        #expect(slices.first?.minY == 0)
        #expect(slices.last?.maxY == 7000)
        for (a, b) in zip(slices, slices.dropFirst()) {
            #expect(b.minY < a.maxY)                 // overlap, nothing between
            #expect(a.maxY - b.minY == 120)
        }
        #expect(slices.allSatisfy { $0.height <= 2400 && $0.width == 1400 })
    }

    @Test func wideImageIsSlicedAlongX() {
        let slices = SearchIndex.slices(width: 6000, height: 900)
        #expect(slices.count > 1)
        #expect(slices.allSatisfy { $0.height == 900 && $0.width <= 2400 })
        #expect(slices.last?.maxX == 6000)
    }

    @Test func leftoverTempFilesAreRemovedAtStart() throws {
        let folder = try makeFolder()
        let stale = folder.appendingPathComponent(".SearchIndex-ABC.tmp")
        let other = folder.appendingPathComponent("keep.txt")
        try Data("secret".utf8).write(to: stale)
        try Data("x".utf8).write(to: other)
        _ = SearchIndex(fileURL: folder.appendingPathComponent("idx.json"), recognizer: { _ in nil })
        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
    }
}

@Suite("Search index, pending")
struct SearchIndexPendingTests {
    @Test func pendingCountFollowsWhatWasRead() async throws {
        let folder = try makeFolder()
        let a = try touch(folder, "a.png"), b = try touch(folder, "b.png"), c = try touch(folder, "c.txt")
        let index = SearchIndex(fileURL: folder.appendingPathComponent("idx.json"),
                                recognizer: Reader(["a.png": "x", "b.png": "y"]).recognizer)
        #expect(await index.pendingCount([a, b, c]) == 2)     // the text file is not an image
        await index.update([a])
        #expect(await index.pendingCount([a, b, c]) == 1)
        await index.update([a, b])
        #expect(await index.pendingCount([a, b, c]) == 0)
    }
}

// Packages/OCRKit/Sources/OCRKit/SearchIndex.swift
import Foundation
import CoreGraphics
import ImageIO
import os

private let logger = Logger(subsystem: "dev.mwlr.knippi", category: "SearchIndex")

/// The words in the saved screenshots, so the history can be searched.
///
/// The text is read once per file, in the background, from the file as it is
/// on disk. Because the editor replaces a screenshot in place after redacting
/// it, what is indexed is what was kept, never the unredacted original.
/// An entry is keyed by path and modification date: a replaced file is read
/// again, a file that is gone loses its entry on the next `update`.
///
/// The index lives in a single JSON file readable only by the user.
/// Idea after Tendedero's search index (MIT, Alejandro Buján); written anew.
public actor SearchIndex {

    /// The text read from one file, with the modification date it came from.
    public struct Entry: Codable, Equatable, Sendable {
        public var modified: Double
        public var text: String
    }

    /// Reads the text of the image at a URL. `nil`: it could not be read now
    /// (try again on the next update). Empty string: read, no text in it.
    public typealias Recognizer = @Sendable (URL) async -> String?

    public static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "tif", "tiff", "gif", "webp"
    ]

    public static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Knippi/SearchIndex.json")
    }

    private let fileURL: URL
    private let recognizer: Recognizer
    private var entries: [String: Entry] = [:]
    private var dirty = false
    /// Raised by `removeAll`, so an update that is still reading stops instead
    /// of writing its results back into an index the user just cleared.
    private var generation = 0

    public init(fileURL: URL = SearchIndex.defaultFileURL,
                recognizer: @escaping Recognizer = SearchIndex.visionRecognizer) {
        self.fileURL = fileURL
        self.recognizer = recognizer
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = saved
        }
        Self.removeLeftovers(beside: fileURL)
    }

    /// A crash between writing and moving leaves a hidden copy of the index
    /// with all its text behind. Remove those.
    private static func removeLeftovers(beside fileURL: URL) {
        let folder = fileURL.deletingLastPathComponent()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names where name.hasPrefix(".SearchIndex-") && name.hasSuffix(".tmp") {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    // MARK: Keeping the index

    /// Makes the index match exactly the given files: forgets the ones that
    /// are not listed, reads the new and the changed. Cheap when nothing changed.
    /// Returns how many files were read.
    @discardableResult
    public func update(_ urls: [URL]) async -> Int {
        let images = urls.filter { Self.isImage($0) }
        let startedIn = generation
        let live = Set(images.map(\.path))
        let before = entries.count
        entries = entries.filter { live.contains($0.key) }
        if entries.count != before { dirty = true }

        var read = 0
        for url in images {
            if Task.isCancelled { break }
            guard let modified = Self.modificationDate(url) else { continue }
            if entries[url.path]?.modified == modified { continue }
            guard let text = await recognizer(url) else { continue }
            if generation != startedIn { return read }
            // The file may have been replaced while it was being read: the
            // text then belongs to the old file, so keep nothing and read again later.
            guard Self.modificationDate(url) == modified else { continue }
            entries[url.path] = Entry(modified: modified, text: Self.fold(text))
            dirty = true
            read += 1
            if read % 20 == 0 { save() }
        }
        save()
        return read
    }

    /// Drops one file at once, for example when it is deleted from the history.
    public func forget(_ url: URL) {
        if entries.removeValue(forKey: url.path) != nil {
            dirty = true
            save()
        }
    }

    /// Deletes everything, in memory and on disk.
    public func removeAll() {
        generation += 1
        entries = [:]
        dirty = false
        try? FileManager.default.removeItem(at: fileURL)
    }

    public var count: Int { entries.count }

    /// How many of these files still have to be read (new or changed).
    public func pendingCount(_ urls: [URL]) -> Int {
        urls.filter { Self.isImage($0) && !isCurrent($0) }.count
    }

    /// Whether this file is in the index with its current modification date.

    public func isCurrent(_ url: URL) -> Bool {
        guard let modified = Self.modificationDate(url) else { return false }
        return entries[url.path]?.modified == modified
    }

    // MARK: Searching

    /// The files that contain every word of the query, in the given order.
    /// An empty query returns all of them. Case, accents and width are ignored.
    public func search(_ query: String, in urls: [URL]) -> [URL] {
        let words = Self.words(query)
        if words.isEmpty { return urls }
        return urls.filter { url in
            guard let text = entries[url.path]?.text else { return false }
            return words.allSatisfy { text.contains($0) }
        }
    }

    // MARK: Folding

    /// The words of a search, folded the same way as what is searched.
    public static func words(_ query: String) -> [String] {
        fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// "Menú" and "MENU" become "menu".
    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    // MARK: Files

    public static func isImage(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    /// Read from the file system every time. `URL.resourceValues` keeps what it
    /// read on that URL value, so a replaced file would still look unchanged.
    private static func modificationDate(_ url: URL) -> Double? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate]
            .flatMap { $0 as? Date }?.timeIntervalSince1970
    }

    /// Written to a file that only the user can read from the start, then put
    /// in place in one step, so there is no moment with looser rights.
    private func save() {
        guard dirty else { return }
        do {
            let folder = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(entries)
            let temp = folder.appendingPathComponent(".SearchIndex-\(UUID().uuidString).tmp")
            guard FileManager.default.createFile(
                atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600])
            else { throw CocoaError(.fileWriteUnknown) }
            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temp)
            } else {
                try FileManager.default.moveItem(at: temp, to: fileURL)
            }
            dirty = false
        } catch {
            logger.error("Index not saved: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Recognizing

    /// The text in an image, read with Vision through `TextRecognizer`.
    ///
    /// The image is shrunk so that its short side is at most 1500 px and it has
    /// at most 24 million pixels, then cut into slices of at most 2400 px along
    /// its long side (120 px overlap, so no line is lost at a cut). Shrinking
    /// by the long side alone made scroll captures (1513 x 30 439 px measured)
    /// unreadable: the text came out 2 px tall.
    public static let visionRecognizer: Recognizer = { url in
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return nil }
        // Larger than any screen capture: not worth the memory, and not worth trying again.
        if width * height > 400_000_000 { return "" }

        let scale = shrinkFactor(width: width, height: height)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int((Double(max(width, height)) * scale).rounded(.up))),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        var texts: [String] = []
        for slice in slices(width: image.width, height: image.height) {
            guard let part = image.cropping(to: slice) else { return nil }
            do {
                let regions = try await TextRecognizer.recognize(image: part, detectURLs: false)
                texts.append(regions.map(\.text).joined(separator: "\n"))
            } catch {
                logger.error("Recognition failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        return texts.joined(separator: "\n")
    }

    /// How much to shrink an image of this size: 1 or less.
    static func shrinkFactor(width: Int, height: Int) -> Double {
        let short = Double(min(width, height))
        let pixels = Double(width) * Double(height)
        return min(1, 1500 / short, (24_000_000 / pixels).squareRoot())
    }

    /// The rectangles to read, in image coordinates: the whole image when the
    /// long side fits, otherwise slices along the long side.
    static func slices(width: Int, height: Int, maxSide: Int = 2400, overlap: Int = 120) -> [CGRect] {
        let longIsHeight = height >= width
        let long = longIsHeight ? height : width
        if long <= maxSide { return [CGRect(x: 0, y: 0, width: width, height: height)] }
        var result: [CGRect] = []
        var start = 0
        while start < long {
            let length = min(maxSide, long - start)
            result.append(longIsHeight
                ? CGRect(x: 0, y: start, width: width, height: length)
                : CGRect(x: start, y: 0, width: length, height: height))
            if start + length >= long { break }
            start += maxSide - overlap
        }
        return result
    }
}

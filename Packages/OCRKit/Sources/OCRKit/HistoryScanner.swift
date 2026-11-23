// Packages/OCRKit/Sources/OCRKit/HistoryScanner.swift
import Foundation

/// The screenshots in the export folder, newest first, for the history.
///
/// Subfolders count (the monthly folders setting writes into them). Hidden
/// files and symbolic links do not: a link could point outside the folder, and
/// the index would then read and keep the text of a file that was never a
/// screenshot of ours.
public enum HistoryScanner {

    public struct Item: Equatable, Hashable, Identifiable, Sendable {
        public let url: URL
        public let modified: Date
        public var id: URL { url }
    }

    /// At most `limit` image files under `folder`, the most recently changed first.
    /// Looks `maxDepth` levels deep (1 = the folder itself, 2 = its subfolders, as the monthly\n    /// folders need), so an export folder set to something large like the home folder\n    /// is not walked down to the last file every few seconds.\n    /// A folder that is missing or unreadable gives an empty list.
    public static func scan(folder: URL, limit: Int, maxDepth: Int = 2) -> [Item] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard limit > 0,
              let walker = FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }

        var items: [Item] = []
        for case let url as URL in walker {
            if walker.level >= maxDepth { walker.skipDescendants() }
            guard SearchIndex.isImage(url),
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isSymbolicLink != true,
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate
            else { continue }
            items.append(Item(url: url, modified: modified))
        }
        items.sort { $0.modified != $1.modified ? $0.modified > $1.modified : $0.url.path < $1.url.path }
        return Array(items.prefix(limit))
    }
}

// Packages/SharedKit/Sources/SharedKit/Utilities/QuickAccessDragFileStore.swift
import CoreGraphics
import Foundation

public enum QuickAccessDragFileStoreError: Error, Equatable {
    case encodingFailed
    case storageUnavailable
}

public final class QuickAccessDragFileStore {
    public typealias Encoder = (CGImage) -> Data?

    public static let defaultStaleFileAge: TimeInterval = 24 * 60 * 60

    public let directory: URL
    public let staleFileAge: TimeInterval

    private let fileManager: FileManager
    private let encoder: Encoder?
    private var cachedFileURLs: [UUID: URL] = [:]

    public init(
        directory: URL? = nil,
        staleFileAge: TimeInterval = QuickAccessDragFileStore.defaultStaleFileAge,
        fileManager: FileManager = .default,
        encoder: Encoder? = nil
    ) {
        self.directory = directory ?? fileManager.temporaryDirectory
            .appendingPathComponent("com.lifeisgoodlabs.Knippi", isDirectory: true)
            .appendingPathComponent("QuickAccessDragFiles", isDirectory: true)
        self.staleFileAge = staleFileAge
        self.fileManager = fileManager
        self.encoder = encoder
    }

    /// Store for files handed to the macOS share menu. Services such as AirDrop read the file
    /// only after the user picked them (WebKit keeps shared files for the same reason,
    /// rdar://63030288), so callers never remove these files themselves: they live in their
    /// own folder, keep their plain name, and only `pruneStaleFiles` deletes them after 24 h.
    public static func forSharing(fileManager: FileManager = .default) -> QuickAccessDragFileStore {
        let defaultDirectory = QuickAccessDragFileStore(fileManager: fileManager).directory
        return QuickAccessDragFileStore(
            directory: defaultDirectory.appendingPathComponent("Shared", isDirectory: true),
            fileManager: fileManager
        )
    }

    public func fileURL(
        for image: CGImage,
        id: UUID,
        output: ScreenshotOutputOptions = ScreenshotOutputOptions(format: .png, quality: 0.85),
        date: Date = Date(),
        sourceAppName: String? = nil,
        sourceWindowTitle: String? = nil,
        template: String? = nil
    ) throws -> URL {
        try prepareStorage()

        if let cachedURL = cachedFileURLs[id], fileManager.isReadableFile(atPath: cachedURL.path) {
            return cachedURL
        }

        guard let data = encodedData(from: image, output: output) else {
            throw QuickAccessDragFileStoreError.encodingFailed
        }

        let preferredURL = FileNaming.generateFileURL(
            in: directory,
            type: .screenshot,
            format: output.format.fileFormat,
            date: date,
            sourceAppName: sourceAppName,
            sourceWindowTitle: sourceWindowTitle,
            template: template
        )
        let fileURL = availableFileURL(for: preferredURL)

        do {
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            throw QuickAccessDragFileStoreError.storageUnavailable
        }

        cachedFileURLs[id] = fileURL
        return fileURL
    }

    @discardableResult
    public func pruneStaleFiles(referenceDate: Date = Date()) throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }

        let preservedURLs = Set(cachedFileURLs.values.map { $0.standardizedFileURL })
        let cutoff = referenceDate.addingTimeInterval(-staleFileAge)
        let fileURLs = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var removed: [URL] = []
        for fileURL in fileURLs where Self.prunableExtensions.contains(fileURL.pathExtension.lowercased()) {
            let standardizedURL = fileURL.standardizedFileURL
            guard !preservedURLs.contains(standardizedURL) else { continue }

            let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values.isRegularFile == true,
                  let modificationDate = values.contentModificationDate,
                  modificationDate < cutoff else { continue }

            try fileManager.removeItem(at: fileURL)
            removed.append(fileURL)
        }

        return removed
    }

    public func removeFile(for id: UUID) throws {
        guard let fileURL = cachedFileURLs.removeValue(forKey: id),
              fileManager.fileExists(atPath: fileURL.path) else { return }

        try fileManager.removeItem(at: fileURL)
    }

    private static let prunableExtensions: Set<String> = Set(
        ScreenshotOutputFormat.allCases.map { $0.fileFormat.rawValue }
    ).union(["jpg"])

    private func encodedData(from image: CGImage, output: ScreenshotOutputOptions) -> Data? {
        if let encoder {
            return encoder(image)
        }
        return ImageEncoders.default.encode(image, format: output.format, quality: output.quality)
    }

    private func availableFileURL(for preferredURL: URL) -> URL {
        FileNaming.availableFileURL(for: preferredURL, fileManager: fileManager)
    }

    private func prepareStorage() throws {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            _ = try pruneStaleFiles()
        } catch {
            throw QuickAccessDragFileStoreError.storageUnavailable
        }
    }
}

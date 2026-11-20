import Foundation

public enum ScreenshotSaveError: Error, Equatable, Sendable {
    /// The target folder could not be created or is not a folder.
    case folderUnavailable(URL)
    /// The image could not be encoded.
    case encodingFailed
    /// The file could not be written.
    case writeFailed(URL)

    /// The folder to name in a user-facing message, when known.
    public var folderURL: URL? {
        switch self {
        case .folderUnavailable(let url): url
        case .writeFailed(let url): url.deletingLastPathComponent()
        case .encodingFailed: nil
        }
    }
}

/// Where an editor save goes: over the auto-saved original of the same capture, or a new file.
public enum ScreenshotSaveTarget: Equatable, Sendable {
    case replace(URL)
    case new(URL)
}

/// The file actually written, and whether it replaced the auto-saved original.
public struct ScreenshotSaveOutcome: Equatable, Sendable {
    public let url: URL
    public let replacedOriginal: Bool
    /// Set when replacing the original was allowed but failed, so the edit went to a
    /// new file and the original is still on disk. Callers must tell the user.
    public let replaceError: String?

    public var replaceFailed: Bool { replaceError != nil }

    public init(url: URL, replacedOriginal: Bool, replaceError: String? = nil) {
        self.url = url
        self.replacedOriginal = replacedOriginal
        self.replaceError = replaceError
    }
}

public enum ScreenshotSaver {
    /// Decides where an editor save goes. The auto-saved `original` of the same capture is
    /// replaced only if it still exists, is writable and has the same format as `proposed`;
    /// otherwise the save is a normal new file at `proposed` (numbered if taken).
    public static func target(
        for proposed: URL,
        replacing original: URL?,
        fileManager: FileManager = .default
    ) -> ScreenshotSaveTarget {
        guard let original,
              original.pathExtension.lowercased() == proposed.pathExtension.lowercased(),
              fileManager.fileExists(atPath: original.path),
              fileManager.isWritableFile(atPath: original.path) else {
            return .new(proposed)
        }
        return .replace(original)
    }

    /// Writes `data` over the auto-saved `original` of the same capture (atomically, same
    /// name) when `target(for:replacing:)` allows it; otherwise — or if replacing fails —
    /// a normal never-overwriting save at `url`.
    /// `replaceWriter` is a test seam for the in-place write.
    public static func write(
        _ data: Data,
        to url: URL,
        replacing original: URL?,
        replaceWriter: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }
    ) -> Result<ScreenshotSaveOutcome, ScreenshotSaveError> {
        var replaceError: String?
        if case .replace(let target) = target(for: url, replacing: original) {
            do {
                try replaceWriter(data, target)
                return .success(ScreenshotSaveOutcome(url: target, replacedOriginal: true))
            } catch {
                replaceError = "\(target.path): \(error)"
            }
        }
        return write(data, to: url).map {
            ScreenshotSaveOutcome(url: $0, replacedOriginal: false, replaceError: replaceError)
        }
    }

    /// Writes `data` to `url`, creating the parent folder if needed. Never
    /// overwrites: if `url` exists, "name 2.ext", "name 3.ext", … is used.
    /// Returns the URL actually written.
    public static func write(_ data: Data, to url: URL) -> Result<URL, ScreenshotSaveError> {
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return .failure(.folderUnavailable(directory))
        }
        // `.withoutOverwriting` closes the gap between the existence check and
        // the write; if another save took the name meanwhile, take the next one.
        for _ in 0..<100 {
            let target = FileNaming.availableFileURL(for: url)
            do {
                try data.write(to: target, options: .withoutOverwriting)
                return .success(target)
            } catch CocoaError.fileWriteFileExists {
                continue
            } catch {
                return .failure(.writeFailed(target))
            }
        }
        return .failure(.writeFailed(url))
    }

    /// After a failed save the image must still be reachable: copy it unless it already is.
    public static func failureNeedsClipboardCopy(alreadyCopied: Bool) -> Bool {
        !alreadyCopied
    }
}

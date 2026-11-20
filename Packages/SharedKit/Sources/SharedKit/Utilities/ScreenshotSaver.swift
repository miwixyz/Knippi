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

public enum ScreenshotSaver {
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

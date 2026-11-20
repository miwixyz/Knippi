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
    /// Writes `data` to `url`, creating the parent folder if needed.
    public static func write(_ data: Data, to url: URL) -> Result<URL, ScreenshotSaveError> {
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return .failure(.folderUnavailable(directory))
        }
        do {
            try data.write(to: url)
            return .success(url)
        } catch {
            return .failure(.writeFailed(url))
        }
    }

    /// After a failed save the image must still be reachable: copy it unless it already is.
    public static func failureNeedsClipboardCopy(alreadyCopied: Bool) -> Bool {
        !alreadyCopied
    }
}

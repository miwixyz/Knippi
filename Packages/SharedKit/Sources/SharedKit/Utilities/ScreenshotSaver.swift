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

/// Identity of a file on disk (device, inode, creation time), read without following
/// symlinks. Another file at the same path — or a symlink — has a different identity.
public struct ScreenshotFileIdentity: Equatable, Sendable {
    public let device: Int64
    public let inode: UInt64
    public let birthSeconds: Int64
    public let birthNanoseconds: Int64

    /// Identity of the regular file at `url`, or nil if there is none (missing, symlink, folder).
    public init?(of url: URL) {
        var info = stat()
        guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        device = Int64(info.st_dev)
        inode = UInt64(info.st_ino)
        birthSeconds = Int64(info.st_birthtimespec.tv_sec)
        birthNanoseconds = Int64(info.st_birthtimespec.tv_nsec)
    }
}

/// A file Knippi wrote, with its identity at that moment. An editor save replaces it only
/// while the file at `url` still is that file.
public struct SavedScreenshotFile: Equatable, Sendable {
    public let url: URL
    public let identity: ScreenshotFileIdentity

    public init(url: URL, identity: ScreenshotFileIdentity) {
        self.url = url
        self.identity = identity
    }

    /// Tracks the file currently at `url`; nil if there is no regular file.
    public init?(url: URL) {
        guard let identity = ScreenshotFileIdentity(of: url) else { return nil }
        self.init(url: url, identity: identity)
    }
}

/// Where an editor save goes: over the auto-saved original of the same capture, or a new file.
public enum ScreenshotSaveTarget: Equatable, Sendable {
    case replace(URL)
    /// No original to replace (none tracked, gone, or another file now at its path).
    case new(URL)
    /// The original is still there but can't be replaced (`reason`); it stays next to the edit.
    case newKeepingOriginal(URL, reason: String)
}

/// The file actually written, and whether it replaced the auto-saved original.
public struct ScreenshotSaveOutcome: Equatable, Sendable {
    public let url: URL
    public let replacedOriginal: Bool
    /// Set when the original is still on disk next to the edit — replacing it wasn't
    /// possible (read-only, locked, other format) or failed. Callers must tell the user.
    public let replaceError: String?

    public var replaceFailed: Bool { replaceError != nil }
    /// The unedited original stays on disk next to the new file.
    public var originalKept: Bool { replaceError != nil }

    public init(url: URL, replacedOriginal: Bool, replaceError: String? = nil) {
        self.url = url
        self.replacedOriginal = replacedOriginal
        self.replaceError = replaceError
    }
}

public enum ScreenshotSaver {
    /// Decides where an editor save goes. The auto-saved `original` of the same capture is
    /// replaced only if the file at its path is still that file, is writable (not locked)
    /// and has the same format as `proposed`. Is it gone or another file, the save is a
    /// plain new file; is it there but not replaceable, the result says why.
    public static func target(
        for proposed: URL,
        replacing original: SavedScreenshotFile?,
        fileManager: FileManager = .default
    ) -> ScreenshotSaveTarget {
        guard let original, ScreenshotFileIdentity(of: original.url) == original.identity else {
            return .new(proposed)
        }
        let path = original.url.path
        if original.url.pathExtension.lowercased() != proposed.pathExtension.lowercased() {
            return .newKeepingOriginal(proposed, reason: "\(path): other format than the edit")
        }
        let locked = (try? fileManager.attributesOfItem(atPath: path)[.immutable] as? Bool) ?? false
        if locked || !fileManager.isWritableFile(atPath: path) {
            return .newKeepingOriginal(proposed, reason: "\(path): not writable or locked")
        }
        return .replace(original.url)
    }

    /// Writes `data` over the auto-saved `original` of the same capture (atomically, same
    /// name) when `target(for:replacing:)` allows it; otherwise — or if replacing fails —
    /// a normal never-overwriting save at `url`.
    /// `replaceWriter` is a test seam for the in-place write.
    public static func write(
        _ data: Data,
        to url: URL,
        replacing original: SavedScreenshotFile?,
        replaceWriter: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }
    ) -> Result<ScreenshotSaveOutcome, ScreenshotSaveError> {
        var replaceError: String?
        switch target(for: url, replacing: original) {
        case .replace(let target):
            do {
                try replaceWriter(data, target)
                return .success(ScreenshotSaveOutcome(url: target, replacedOriginal: true))
            } catch {
                replaceError = "\(target.path): \(error)"
            }
        case .newKeepingOriginal(_, let reason):
            replaceError = reason
        case .new:
            break
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

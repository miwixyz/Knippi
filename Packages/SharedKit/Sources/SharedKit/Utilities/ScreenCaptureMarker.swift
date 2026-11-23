import Foundation
import os

private let logger = Logger(subsystem: "dev.mwlr.knippi", category: "ScreenCaptureMarker")

/// Marks a saved screenshot as a screenshot for the system: the Spotlight attribute
/// `kMDItemIsScreenCapture`, set the way macOS and other capture tools set it.
///
/// Why: other apps find screenshots by this attribute, not by folder. Gnotchi's screenshot
/// shelf, the Finder "Screenshots" smart folder and Spotlight's `kind:screenshot` all ask for it.
/// Without it a Knippi screenshot is just an image that happens to be in a folder
/// (found 2026-11-23: Knippi did not set it, so Gnotchi never saw Knippi's captures).
///
/// A failed mark never fails the save: the file is there and usable, it just is not announced.
public enum ScreenCaptureMarker {
    /// The extended attribute macOS writes; Spotlight imports every `com.apple.metadata:` attribute.
    public static let attributeName = "com.apple.metadata:kMDItemIsScreenCapture"

    /// A binary property list holding `true`, byte for byte what macOS stores
    /// (read from a real macOS screenshot on 2026-11-23, 42 bytes).
    public static let value = Data([
        0x62, 0x70, 0x6C, 0x69, 0x73, 0x74, 0x30, 0x30, 0x09, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x09,
    ])

    /// Sets the attribute on the file itself (a symbolic link is not followed).
    /// Returns whether it worked; a failure is logged, not thrown.
    @discardableResult
    public static func mark(_ url: URL) -> Bool {
        let result = url.path.withCString { path in
            value.withUnsafeBytes { bytes in
                setxattr(path, attributeName, bytes.baseAddress, bytes.count, 0, XATTR_NOFOLLOW)
            }
        }
        if result != 0 {
            logger.error("Screenshot not marked (errno \(errno, privacy: .public)): \(url.lastPathComponent, privacy: .private)")
        }
        return result == 0
    }

    /// Whether the file carries the attribute with the value `true`.
    public static func isMarked(_ url: URL) -> Bool {
        url.path.withCString { path in
            let size = getxattr(path, attributeName, nil, 0, 0, XATTR_NOFOLLOW)
            guard size > 0 else { return false }
            var buffer = [UInt8](repeating: 0, count: size)
            let read = getxattr(path, attributeName, &buffer, size, 0, XATTR_NOFOLLOW)
            guard read == size,
                  let plist = try? PropertyListSerialization.propertyList(from: Data(buffer), format: nil) as? Bool
            else { return false }
            return plist
        }
    }
}

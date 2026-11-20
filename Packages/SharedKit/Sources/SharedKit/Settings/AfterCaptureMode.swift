import Foundation

/// What happens after a plain screenshot capture (no explicit one-off action).
public enum AfterCaptureMode: String, CaseIterable, Sendable {
    /// Show the Quick Access preview (default).
    case preview
    /// Open the annotation editor directly.
    case editor
    /// Copy to the clipboard and save to the output folder, show nothing but a toast.
    case silent
}

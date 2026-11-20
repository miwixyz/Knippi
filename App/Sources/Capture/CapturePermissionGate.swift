import AppKit
import CaptureKit
import CoreGraphics
import Foundation
import os
@preconcurrency import ScreenCaptureKit
import SharedKit

/// Which capture API may be used for a synchronous screen grab.
///
/// Without Screen Recording permission `CGDisplayCreateImage` does not fail:
/// it returns a full-size image that shows only the desktop wallpaper (no
/// windows, no menu bar). Measured 2026-11-20 on macOS 27.2. Such an image must
/// never be delivered as a capture, so the sync shortcut is only allowed when
/// the permission preflight passes; otherwise ScreenCaptureKit runs and throws
/// a real permission error (-3801) that can be shown to the user.
enum CaptureRoute: Equatable {
    case sync
    case screenCaptureKit

    static func choose(preflight: Bool, syncAvailable: Bool) -> CaptureRoute {
        preflight && syncAvailable ? .sync : .screenCaptureKit
    }
}

/// How a failed capture is reported to the user.
enum CaptureErrorPresentation: Equatable {
    case permissionMissing
    case generic(String)

    static func forError(_ error: Error) -> CaptureErrorPresentation {
        if case CaptureError.capturePermissionDenied = error {
            return .permissionMissing
        }
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain,
           nsError.code == SCStreamError.Code.userDeclined.rawValue {
            return .permissionMissing
        }
        return .generic(error.localizedDescription)
    }
}

/// Shows the Screen Recording notice. One alert at a time; System Settings
/// only opens when the user clicks the button.
@MainActor
enum CapturePermissionNotice {
    private static let logger = Logger(subsystem: "dev.mwlr.knippi", category: "capture")
    private static let requestedKey = "screenCaptureAccessRequested"
    private static var isShowing = false

    /// Test seam — replaces the real NSAlert.
    static var presenter: (() -> Void)?

    static func show() {
        logger.error("Capture blocked: Screen Recording permission missing")
        requestSystemPromptOnce()
        if let presenter {
            presenter()
            return
        }
        guard !isShowing else { return }
        isShowing = true
        defer { isShowing = false }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Screen Recording Permission Needed")
        alert.informativeText = String(localized: "Knippi needs Screen Recording permission. Open System Settings → Privacy & Security → Screen & System Audio Recording and allow Knippi.")
        alert.addButton(withTitle: String(localized: "Open Settings"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.window.level = .screenSaver + 2
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(PermissionKind.screenRecording.settingsURL)
        }
    }

    /// Registers Knippi with TCC (so it appears in the Settings list) the first
    /// time the permission is found missing. macOS shows its own prompt only
    /// while the permission is still undetermined.
    private static func requestSystemPromptOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: requestedKey) else { return }
        defaults.set(true, forKey: requestedKey)
        _ = CGRequestScreenCaptureAccess()
    }
}

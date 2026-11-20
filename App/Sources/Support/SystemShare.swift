// App/Sources/Support/SystemShare.swift
import AppKit
import SwiftUI

/// Presents the macOS share menu (AirDrop, Mail, Messages, …) for a file.
@MainActor
enum SystemShare {
    /// Keeps the delegate alive while the picker is on screen; the picker only holds it weakly.
    private static var activeDelegate: Delegate?

    /// Shows `NSSharingServicePicker` for `fileURL`, anchored below `rect` in `view`'s coordinates.
    /// `onFinish` runs once the user picked a service or dismissed the menu.
    static func present(
        fileURL: URL,
        relativeTo rect: NSRect,
        of view: NSView,
        onFinish: (@MainActor () -> Void)? = nil
    ) {
        let picker = NSSharingServicePicker(items: [fileURL])
        let delegate = Delegate(onFinish: {
            activeDelegate = nil
            onFinish?()
        })
        activeDelegate = delegate
        picker.delegate = delegate
        picker.show(relativeTo: rect, of: view, preferredEdge: .minY)
    }

    @MainActor
    private final class Delegate: NSObject, @preconcurrency NSSharingServicePickerDelegate {
        private let onFinish: @MainActor () -> Void
        init(onFinish: @escaping @MainActor () -> Void) { self.onFinish = onFinish }

        func sharingServicePicker(
            _ sharingServicePicker: NSSharingServicePicker,
            didChoose service: NSSharingService?
        ) {
            // `service` is nil when the menu was dismissed without a choice.
            onFinish()
        }
    }
}

/// Reference the SwiftUI side keeps to the NSView backing a share button.
@MainActor
final class SystemShareAnchor {
    weak var view: NSView?

    /// Presents the picker below the anchor view; false when the anchor is not in a window yet.
    @discardableResult
    func present(fileURL: URL, onFinish: (@MainActor () -> Void)? = nil) -> Bool {
        guard let view, view.window != nil else { return false }
        SystemShare.present(fileURL: fileURL, relativeTo: view.bounds, of: view, onFinish: onFinish)
        return true
    }
}

/// Invisible NSView placed behind a SwiftUI button via `.background(...)`.
struct SystemShareAnchorView: NSViewRepresentable {
    let anchor: SystemShareAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}

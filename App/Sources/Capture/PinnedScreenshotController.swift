// App/Sources/Capture/PinnedScreenshotController.swift
import AppKit
import CaptureKit

@MainActor
final class PinnedScreenshotController {
    let id = UUID()
    private let onCopy: () -> Void
    private let onSave: () -> Void
    private let onDidClose: (UUID) -> Void
    private let activatesApp: Bool

    private let contentWindow: PinnedScreenshotWindow
    private let chromeWindow: PinnedScreenshotChromeWindow

    private var isLocked = false
    /// Pointer monitors of a locked pin (see `toggleLock`); empty while unlocked.
    private var hoverMonitors: [Any] = []
    private var isClosing = false

    init(
        image: CGImage,
        anchorRect: CGRect?,
        activatesApp: Bool = true,
        onCopy: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onDidClose: @escaping (UUID) -> Void
    ) {
        self.onCopy = onCopy
        self.onSave = onSave
        self.onDidClose = onDidClose
        self.activatesApp = activatesApp

        contentWindow = PinnedScreenshotWindow(
            image: image,
            anchorRect: anchorRect,
            activatesApp: activatesApp,
            onCopy: onCopy,
            onSave: onSave,
            onDidClose: { _ in }
        )
        chromeWindow = PinnedScreenshotChromeWindow(
            frame: contentWindow.frame,
            activatesApp: activatesApp
        )

        contentWindow.onDidClose = { [weak self] _ in
            self?.closeAll(fromContentWindow: true)
        }

        contentWindow.onFrameChanged = { [weak self] frame in
            self?.chromeWindow.sync(to: frame)
        }
        contentWindow.onScaleChanged = { [weak self] percent in
            self?.chromeWindow.chromeView.showZoom(percent)
        }

        chromeWindow.chromeView.closeButton.target = self
        chromeWindow.chromeView.closeButton.action = #selector(closeOverlay)
        chromeWindow.chromeView.lockButton.target = self
        chromeWindow.chromeView.lockButton.action = #selector(toggleLock)
    }

    func show() {
        contentWindow.show()
        contentWindow.addChildWindow(chromeWindow, ordered: .above)
        if activatesApp {
            chromeWindow.orderFront(nil)
        } else {
            chromeWindow.orderFrontRegardless()
        }
    }

    var isHidden: Bool { !contentWindow.isVisible }

    /// Hides or shows the pin and its controls without closing it.
    func setHidden(_ hidden: Bool) {
        if hidden {
            contentWindow.orderOut(nil)
        } else {
            contentWindow.orderFrontRegardless()
            chromeWindow.orderFrontRegardless()
        }
    }

    func updateZoomHUD(scalePercent: Int) {
        chromeWindow.chromeView.showZoom(scalePercent)
    }

    @objc private func closeOverlay() {
        closeAll()
    }

    private func closeAll(fromContentWindow: Bool = false) {
        guard !isClosing else { return }
        isClosing = true

        stopHoverTracking()
        contentWindow.removeChildWindow(chromeWindow)
        chromeWindow.close()

        if !fromContentWindow {
            contentWindow.close()
        }

        onDidClose(id)
    }

    @objc private func toggleLock() {
        isLocked.toggle()
        chromeWindow.chromeView.isLocked = isLocked
        contentWindow.alphaValue = isLocked ? 0.72 : 1.0
        contentWindow.ignoresMouseEvents = isLocked
        contentWindow.contentView.map { ($0 as? PinnedScreenshotContentView)?.isResizable = !isLocked }

        stopHoverTracking()
        guard isLocked else { return }
        // A locked pin lets clicks through, so it gets no hover events. Watch the pointer moving
        // instead (other apps: global monitor, Knippi's own windows: local monitor), only while
        // locked. Mouse monitors need no extra permission.
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.fadeWhileHovered() }
        }) {
            hoverMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.fadeWhileHovered() }
            return event
        }) {
            hoverMonitors.append(local)
        }
        fadeWhileHovered()
    }

    private func stopHoverTracking() {
        hoverMonitors.forEach { NSEvent.removeMonitor($0) }
        hoverMonitors = []
    }

    /// A locked pin fades almost away while the pointer is over it, to show what's underneath.
    private func fadeWhileHovered() {
        let target: CGFloat = contentWindow.frame.contains(NSEvent.mouseLocation) ? 0.08 : 0.72
        guard contentWindow.alphaValue != target else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            contentWindow.animator().alphaValue = target
        }
    }

}

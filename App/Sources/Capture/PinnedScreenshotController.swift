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
    private let shadowWindow: PinnedScreenshotShadowWindow
    /// Deckkraft, die der Nutzer gewählt hat (Kapsel oder Kontextmenü).
    private var pinOpacity: Double = 1

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
        shadowWindow = PinnedScreenshotShadowWindow(
            imageFrame: contentWindow.frame,
            activatesApp: activatesApp
        )

        contentWindow.onDidClose = { [weak self] _ in
            self?.closeAll(fromContentWindow: true)
        }

        contentWindow.onFrameChanged = { [weak self] frame in
            self?.chromeWindow.sync(to: frame)
            self?.shadowWindow.sync(to: frame)
        }
        contentWindow.onScaleChanged = { [weak self] percent in
            self?.chromeWindow.chromeView.showZoom(percent)
        }
        contentWindow.onOpacityChanged = { [weak self] value in
            guard let self else { return }
            self.pinOpacity = value
            self.chromeWindow.chromeView.model.opacity = value
            self.shadowWindow.alphaValue = value
        }
        contentWindow.onHoverChanged = { [weak self] inside in
            guard let model = self?.chromeWindow.chromeView.model else { return }
            model.isPointerOverImage = inside
            model.pointerChanged()
        }

        let model = chromeWindow.chromeView.model
        model.onCopy = onCopy
        model.onSave = onSave
        model.onClose = { [weak self] in self?.closeOverlay() }
        model.onToggleLock = { [weak self] in self?.toggleLock() }
        model.onSetOpacity = { [weak self] value in self?.contentWindow.setPinOpacity(value) }
    }

    func show() {
        contentWindow.show()
        contentWindow.addChildWindow(shadowWindow, ordered: .below)
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
            shadowWindow.order(.below, relativeTo: contentWindow.windowNumber)
            chromeWindow.orderFrontRegardless()
        }
    }

    /// Nur für die Sichttest-Testkopie: zeigt die Hover-Kapsel ohne Zeiger.
    func showControlsForSichttest() {
        let model = chromeWindow.chromeView.model
        model.isPointerOverImage = true
        model.pointerChanged()
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
        contentWindow.removeChildWindow(shadowWindow)
        shadowWindow.close()

        if !fromContentWindow {
            contentWindow.close()
        }

        onDidClose(id)
    }

    @objc private func toggleLock() {
        isLocked.toggle()
        chromeWindow.chromeView.isLocked = isLocked
        contentWindow.alphaValue = isLocked ? 0.72 : 1.0
        // Gesperrt schwebt das Bild halb durchsichtig – ohne Schatten wirkt es ruhiger.
        shadowWindow.alphaValue = isLocked ? 0 : pinOpacity
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

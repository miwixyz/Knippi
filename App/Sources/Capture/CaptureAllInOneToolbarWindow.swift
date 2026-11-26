import AppKit
import CaptureKit
import Observation
import SharedKit
import SwiftUI

@MainActor
final class CaptureAllInOneToolbarWindow {
    private static let minimumSelectionSize = CGSize(width: 24, height: 24)

    private var selectionOverlayWindow: NSPanel?
    private weak var selectionOverlayView: AllInOneSelectionOverlayView?
    private var toolbarWindow: NSPanel?
    private var annotationOverlay: CaptureAllInOneAnnotationOverlay?
    private var globalEscMonitor: Any?
    private var localEscMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalSelectionMouseMonitor: Any?
    private var localSelectionMouseMonitor: Any?
    private var screenLocalSelectionRect: CGRect
    private let toolbarState: CaptureAllInOneToolbarState
    private let presets: [CapturePreset]
    private var activePreset: CapturePreset
    private let frozenImage: CGImage?
    private var lastLiveAnnotationUpdateTime: TimeInterval = 0

    let screen: NSScreen

    var onPresetChanged: ((CapturePreset) -> Void)?
    var onArea: ((CGRect) -> Void)?
    var onFullscreen: (() -> Void)?
    var onWindow: (() -> Void)?
    var onScrolling: ((CGRect) -> Void)?
    var onTimer: ((CGRect) -> Void)?
    var onOCR: ((CGRect) -> Void)?
    var onColor: (() -> Void)?
    var onRecording: ((CGRect) -> Void)?
    var onAnnotate: ((CGRect) -> Void)?
    var onCopy: ((CGRect) -> Void)?
    var onCopyRendered: ((CGImage, CGRect) -> Void)?
    var onSave: ((CGRect) -> Void)?
    var onSaveRendered: ((CGImage, CGRect) -> Void)?
    var onPin: ((CGRect) -> Void)?
    var onPinRendered: ((CGImage, CGRect) -> Void)?
    var onOCRRendered: ((CGImage, CGRect) -> Void)?
    /// Rendering the annotated image failed while annotations exist. The
    /// action is aborted instead of silently exporting the unannotated
    /// original (audit C12, 21.11.).
    var onAnnotationRenderFailed: (() -> Void)?
    var onCancel: (() -> Void)?

    init(
        selectionRect: CGRect,
        screen: NSScreen,
        presets: [CapturePreset],
        activePreset: CapturePreset,
        frozenImage: CGImage? = nil
    ) {
        let visiblePresets = presets.isEmpty ? [.freeform] : presets
        self.screenLocalSelectionRect = selectionRect.standardized
        self.presets = visiblePresets
        self.activePreset = activePreset
        self.frozenImage = frozenImage
        self.toolbarState = CaptureAllInOneToolbarState(
            selectionRect: selectionRect.standardized,
            presets: visiblePresets,
            activePreset: activePreset
        )
        self.screen = screen
    }

    func show() {
        screenLocalSelectionRect = CaptureSelectionGeometry.move(
            screenLocalSelectionRect,
            by: .zero,
            in: screenLocalBounds
        )
        updateToolbarState()

        showSelectionOverlay()
        showToolbar()
        showAnnotationOverlayIfPossible()
        installKeyboardMonitor()
    }

    func close() {
        removeKeyboardMonitor()
        annotationOverlay?.close()
        annotationOverlay = nil
        removeSelectionMouseMonitor()
        toolbarWindow?.close()
        toolbarWindow = nil
        selectionOverlayWindow?.close()
        selectionOverlayWindow = nil
        selectionOverlayView = nil
    }

    private var screenLocalBounds: CGRect {
        CGRect(origin: .zero, size: screen.frame.size)
    }

    private var globalSelectionRect: CGRect {
        CGRect(
            x: screenLocalSelectionRect.origin.x + screen.frame.origin.x,
            y: screenLocalSelectionRect.origin.y + screen.frame.origin.y,
            width: screenLocalSelectionRect.width,
            height: screenLocalSelectionRect.height
        )
    }

    private func showSelectionOverlay() {
        let panel = AllInOnePanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.onEscape = { [weak self] in self?.onCancel?() }
        panel.level = frozenImage == nil ? .screenSaver : .screenSaver + 2
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let overlayView = AllInOneSelectionOverlayView(
            frame: CGRect(origin: .zero, size: screen.frame.size),
            selectionRect: screenLocalSelectionRect,
            minSelectionSize: Self.minimumSelectionSize,
            activePreset: activePreset
        )
        overlayView.passesThroughSelectionBody = frozenImage != nil
        overlayView.squareCenterLockShortcut = AppSettings().squareCenterLockShortcut
        overlayView.onSelectionPreviewChanged = { [weak self] selectionRect in
            self?.updateSelection(selectionRect, phase: .live)
        }
        overlayView.onSelectionChanged = { [weak self] selectionRect in
            self?.updateSelection(selectionRect, phase: .final)
        }
        overlayView.onCancel = { [weak self] in
            self?.onCancel?()
        }
        panel.contentView = overlayView

        selectionOverlayView = overlayView
        selectionOverlayWindow = panel
        panel.orderFrontRegardless()
        panel.makeKey()
        installSelectionMouseMonitorIfNeeded()
    }

    private func showToolbar() {
        let panel = AllInOnePanel(
            contentRect: toolbarFrame(for: globalSelectionRect),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.onEscape = { [weak self] in self?.onCancel?() }
        panel.level = frozenImage == nil ? .screenSaver + 1 : .screenSaver + 3
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Glas-Kapseln werfen ihren eigenen Schatten; ein Fensterschatten zeichnete sonst
        // ein Rechteck um die durchsichtige Fläche.
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        panel.acceptsMouseMovedEvents = true

        let hostingView = AllInOneToolbarHostingView(rootView: CaptureAllInOneToolbarView(
            state: toolbarState,
            isSideRail: frozenImage != nil,
            onChromeStateChanged: { [weak self] in
                self?.layoutChrome(animated: true)
            },
            onArea: { [weak self] in
                guard let self else { return }
                self.onArea?(self.screenLocalSelectionRect)
            },
            onFullscreen: { [weak self] in self?.onFullscreen?() },
            onWindow: { [weak self] in self?.onWindow?() },
            onColor: { [weak self] in self?.onColor?() },
            onScrolling: { [weak self] in
                guard let self else { return }
                self.onScrolling?(self.screenLocalSelectionRect)
            },
            onTimer: { [weak self] in
                guard let self else { return }
                self.onTimer?(self.screenLocalSelectionRect)
            },
            onOCR: { [weak self] in
                guard let self else { return }
                self.performAnnotatedAction(
                    rendered: { $0.onOCRRendered?($1, $2) },
                    original: { $0.onOCR?($1) }
                )
            },
            onRecording: { [weak self] in
                guard let self else { return }
                self.onRecording?(self.screenLocalSelectionRect)
            },
            onAnnotate: { [weak self] in
                guard let self else { return }
                self.onAnnotate?(self.screenLocalSelectionRect)
            },
            onCopy: { [weak self] in self?.performCopyAction() },
            onSave: { [weak self] in self?.performSaveAction() },
            onPin: { [weak self] in self?.performPinAction() },
            onPresetSelected: { [weak self] preset in
                self?.applyPreset(preset)
            },
            onCancel: { [weak self] in self?.onCancel?() }
        ))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView

        toolbarWindow = panel
        panel.orderFrontRegardless()
    }

    private func toolbarFrame(for selectionRect: CGRect) -> CGRect {
        if frozenImage != nil {
            return sideRailFrame(for: selectionRect)
        }

        let margin: CGFloat = 12
        let gap: CGFloat = 12
        let toolbarWidth = min(max(980, selectionRect.width), screen.visibleFrame.width - margin * 2)
        let toolbarHeight: CGFloat = 78

        let minX = screen.visibleFrame.minX + margin
        let maxX = screen.visibleFrame.maxX - toolbarWidth - margin
        let x = min(max(selectionRect.midX - toolbarWidth / 2, minX), maxX)

        let belowY = selectionRect.minY - toolbarHeight - gap
        let aboveY = selectionRect.maxY + gap
        let y: CGFloat
        if belowY >= screen.visibleFrame.minY + margin {
            y = belowY
        } else if aboveY + toolbarHeight <= screen.visibleFrame.maxY - margin {
            y = aboveY
        } else {
            y = max(screen.visibleFrame.minY + margin, selectionRect.minY + margin)
        }

        return CGRect(x: x, y: y, width: toolbarWidth, height: toolbarHeight)
    }

    private func sideRailFrame(for selectionRect: CGRect) -> CGRect {
        let margin: CGFloat = 12
        let gap: CGFloat = 10
        let toolbarWidth: CGFloat = 84
        let toolbarHeight = min(toolbarState.preferredRailHeight, screen.visibleFrame.height - margin * 2)

        let preferredRightX = selectionRect.maxX + gap
        let preferredLeftX = selectionRect.minX - toolbarWidth - gap
        let x: CGFloat
        if preferredRightX + toolbarWidth <= screen.visibleFrame.maxX - margin {
            x = preferredRightX
        } else if preferredLeftX >= screen.visibleFrame.minX + margin {
            x = preferredLeftX
        } else {
            x = screen.visibleFrame.maxX - toolbarWidth - margin
        }

        let y = min(
            max(selectionRect.midY - toolbarHeight / 2, screen.visibleFrame.minY + margin),
            screen.visibleFrame.maxY - toolbarHeight - margin
        )

        return CGRect(x: x, y: y, width: toolbarWidth, height: toolbarHeight)
    }

    private enum SelectionUpdatePhase {
        case live
        case final
    }

    private func updateSelection(_ selectionRect: CGRect, phase: SelectionUpdatePhase = .final) {
        screenLocalSelectionRect = CaptureSelectionGeometry.move(
            selectionRect.standardized,
            by: .zero,
            in: screenLocalBounds
        )
        updateToolbarState()
        let isLive = phase == .live
        layoutChrome(animated: !isLive)
        if shouldRefreshAnnotationOverlay(isLive: isLive) {
            updateAnnotationOverlayIfPossible(isLive: isLive)
        }
        updateSelectionMouseHandling()
    }

    private func updateToolbarState() {
        toolbarState.width = max(1, Int(screenLocalSelectionRect.width.rounded()))
        toolbarState.height = max(1, Int(screenLocalSelectionRect.height.rounded()))
        let shouldCompact = frozenImage != nil
            && CaptureChromeLayout.startsWithCompactSideRail
        if toolbarState.isCompact != shouldCompact {
            toolbarState.isCompact = shouldCompact
            toolbarState.showsOverflow = false
        }
    }

    private func applyPreset(_ preset: CapturePreset) {
        activePreset = preset
        toolbarState.activePreset = preset
        selectionOverlayView?.setActivePreset(preset)

        let fittedRect = fittedSelectionRect(for: preset)
        screenLocalSelectionRect = fittedRect
        selectionOverlayView?.setSelectionRect(fittedRect)
        updateToolbarState()
        layoutChrome(animated: true)
        updateAnnotationOverlayIfPossible(isLive: false)
        onPresetChanged?(preset)
    }

    private func layoutChrome(animated: Bool) {
        let frame = toolbarFrame(for: globalSelectionRect)
        if animated {
            toolbarWindow?.setFrame(frame, display: true, animate: true)
        } else {
            toolbarWindow?.setFrame(frame, display: true)
        }
        annotationOverlay?.repositionToolbar(
            selectionRect: screenLocalSelectionRect,
            avoidingFrame: toolbarWindow?.frame,
            animated: animated
        )
    }

    private func showAnnotationOverlayIfPossible() {
        guard let sourceImage = croppedFrozenImage(for: screenLocalSelectionRect) else { return }
        let overlay = CaptureAllInOneAnnotationOverlay(screen: screen)
        annotationOverlay = overlay
        overlay.show(
            sourceImage: sourceImage,
            selectionRect: screenLocalSelectionRect,
            avoidingFrame: toolbarWindow?.frame
        )
    }

    private func updateAnnotationOverlayIfPossible(isLive: Bool) {
        guard let sourceImage = croppedFrozenImage(for: screenLocalSelectionRect) else { return }
        if annotationOverlay == nil {
            let overlay = CaptureAllInOneAnnotationOverlay(screen: screen)
            annotationOverlay = overlay
            overlay.show(
                sourceImage: sourceImage,
                selectionRect: screenLocalSelectionRect,
                avoidingFrame: toolbarWindow?.frame
            )
        } else {
            annotationOverlay?.update(
                sourceImage: sourceImage,
                selectionRect: screenLocalSelectionRect,
                avoidingFrame: toolbarWindow?.frame,
                isLive: isLive
            )
        }
    }

    private func shouldRefreshAnnotationOverlay(isLive: Bool) -> Bool {
        guard isLive else {
            lastLiveAnnotationUpdateTime = 0
            return true
        }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastLiveAnnotationUpdateTime >= 1.0 / 30.0 else {
            return false
        }
        lastLiveAnnotationUpdateTime = now
        return true
    }

    private func croppedFrozenImage(for selectionRect: CGRect) -> CGImage? {
        guard let frozenImage else { return nil }
        let cropRect = CaptureDisplayGeometry.frozenImageCropRect(
            screenLocalRect: selectionRect,
            screenSize: screen.frame.size,
            imageSize: CGSize(width: frozenImage.width, height: frozenImage.height)
        )
        guard !cropRect.isEmpty else { return nil }
        return frozenImage.cropping(to: cropRect)
    }

    private func fittedSelectionRect(for preset: CapturePreset) -> CGRect {
        if let fixedSize = preset.fixedPixelSize {
            return CaptureSelectionGeometry.fixedSize(
                CGSize(width: fixedSize.width, height: fixedSize.height),
                centeredAt: CGPoint(x: screenLocalSelectionRect.midX, y: screenLocalSelectionRect.midY),
                in: screenLocalBounds
            )
        }

        if let ratio = preset.ratio {
            return CaptureSelectionGeometry.fit(
                screenLocalSelectionRect,
                aspectRatio: ratio,
                in: screenLocalBounds,
                minSize: Self.minimumSelectionSize
            )
        }

        return CaptureSelectionGeometry.move(
            screenLocalSelectionRect,
            by: .zero,
            in: screenLocalBounds
        )
    }

    private func performCopyAction() {
        performAnnotatedAction(
            rendered: { $0.onCopyRendered?($1, $2) },
            original: { $0.onCopy?($1) }
        )
    }

    private func performSaveAction() {
        performAnnotatedAction(
            rendered: { $0.onSaveRendered?($1, $2) },
            original: { $0.onSave?($1) }
        )
    }

    private func performPinAction() {
        performAnnotatedAction(
            rendered: { $0.onPinRendered?($1, $2) },
            original: { $0.onPin?($1) }
        )
    }

    /// Runs an export action with the annotated render when an annotation
    /// overlay exists, otherwise with the plain selection. A failed render
    /// only falls back to the original when there is nothing to lose; with
    /// annotations present the action is aborted (audit C12, 21.11.).
    private func performAnnotatedAction(
        rendered: @escaping (CaptureAllInOneToolbarWindow, CGImage, CGRect) -> Void,
        original: @escaping (CaptureAllInOneToolbarWindow, CGRect) -> Void
    ) {
        guard let annotationOverlay else {
            original(self, screenLocalSelectionRect)
            return
        }
        annotationOverlay.renderImage(afterCommit: { [weak self] image in
            guard let self else { return }
            if let image {
                rendered(self, image, self.screenLocalSelectionRect)
            } else if annotationOverlay.annotationDocument?.objects.isEmpty == false {
                self.onAnnotationRenderFailed?()
            } else {
                original(self, self.screenLocalSelectionRect)
            }
        })
    }

    private func installKeyboardMonitor() {
        globalEscMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in self?.onCancel?() }
        }
        localEscMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.handleKeyboardEvent(event)
        }
        // The toolbar panel can be key while the selection is being dragged, so
        // route flags changes to the selection view here too. Double delivery
        // (view + monitor) is a no-op.
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.selectionOverlayView?.handleFlagsChanged(event)
            return event
        }
    }

    private func removeKeyboardMonitor() {
        if let globalEscMonitor {
            NSEvent.removeMonitor(globalEscMonitor)
            self.globalEscMonitor = nil
        }
        if let localEscMonitor {
            NSEvent.removeMonitor(localEscMonitor)
            self.localEscMonitor = nil
        }
        if let localFlagsMonitor {
            NSEvent.removeMonitor(localFlagsMonitor)
            self.localFlagsMonitor = nil
        }
    }

    private func handleKeyboardEvent(_ event: NSEvent) -> NSEvent? {
        if selectionOverlayView?.handleCenterLockKeyEvent(event) == true {
            return nil
        }
        if event.keyCode == 49, let selectionOverlayView {
            let held = event.type == .keyDown
                && annotationOverlay?.isEditingText != true
                && event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty
            guard held || selectionOverlayView.isSpaceHeld else { return event }
            selectionOverlayView.isSpaceHeld = held
            updateSelectionMouseHandling()
            return nil
        }
        guard event.type == .keyDown else { return event }
        if event.keyCode == 53 {
            onCancel?()
            return nil
        }

        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])

        if modifiers.isEmpty, event.keyCode == 36 || event.keyCode == 76 {
            guard let annotationOverlay, !annotationOverlay.isEditingText else { return event }
            performCopyAction()
            return nil
        }

        if modifiers == [.command, .shift], event.keyCode == 8 {
            if event.isInjectedCopyShortcut { return nil }
            performCopyAction()
            return nil
        }

        guard modifiers.contains(.command) else { return event }

        // Prefer annotation-object clipboard when a canvas object is selected.
        // ⌘C returns false when nothing is selected so we can fall back below.
        if annotationOverlay?.performAnnotationClipboardShortcut(with: event) == true {
            return nil
        }

        guard modifiers == .command else { return event }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c":
            if event.isInjectedCopyShortcut { return nil }
            // Fall back to copy-image-and-close when no annotation object is
            // selected. While editing text, leave ⌘C to the native text field.
            if annotationOverlay?.isEditingText == true {
                return event
            }
            performCopyAction()
            return nil
        case "s":
            performSaveAction()
            return nil
        case "p":
            performPinAction()
            return nil
        default:
            return event
        }
    }

    private func installSelectionMouseMonitorIfNeeded() {
        guard frozenImage != nil else { return }

        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
        globalSelectionMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            Task { @MainActor in self?.updateSelectionMouseHandling() }
        }
        localSelectionMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.updateSelectionMouseHandling()
            return event
        }
        updateSelectionMouseHandling()
    }

    private func removeSelectionMouseMonitor() {
        if let globalSelectionMouseMonitor {
            NSEvent.removeMonitor(globalSelectionMouseMonitor)
            self.globalSelectionMouseMonitor = nil
        }
        if let localSelectionMouseMonitor {
            NSEvent.removeMonitor(localSelectionMouseMonitor)
            self.localSelectionMouseMonitor = nil
        }
    }

    private func updateSelectionMouseHandling() {
        guard frozenImage != nil,
              let selectionOverlayWindow,
              let selectionOverlayView else {
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        let screenLocalPoint = CGPoint(
            x: mouseLocation.x - screen.frame.minX,
            y: mouseLocation.y - screen.frame.minY
        )
        selectionOverlayWindow.ignoresMouseEvents = !selectionOverlayView.wantsMouseEvents(at: screenLocalPoint)
    }
}

private final class AllInOnePanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 53 else {
            super.keyDown(with: event)
            return
        }

        onEscape?()
    }
}

private final class AllInOneToolbarHostingView<Content: View>: NSHostingView<Content> {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
        super.mouseMoved(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.arrow.set()
        super.mouseEntered(with: event)
    }
}

@MainActor
@Observable
private final class CaptureAllInOneToolbarState {
    var width: Int
    var height: Int
    let presets: [CapturePreset]
    var activePreset: CapturePreset
    var isCompact = false
    var showsOverflow = false

    /// Höhe der senkrechten Leiste aus zwei Glas-Inseln (Aufnahmearten + Vorlage, Aktionen).
    var preferredRailHeight: CGFloat {
        typealias L = CaptureAllInOneToolbarView
        func island(_ heights: [CGFloat]) -> CGFloat {
            2 * L.railIslandPadding + heights.reduce(0, +) + CGFloat(max(0, heights.count - 1)) * L.railRowGap
        }
        var height = 2 * L.railOuterPadding
        if !isCompact || showsOverflow {
            var modes = Array(repeating: L.railRowHeight, count: 6)
            if FeatureFlags.scrollingCapture { modes.append(L.railRowHeight) }
            if FeatureFlags.screenRecording { modes.append(L.railRowHeight) }
            modes.append(L.railPresetHeight)
            height += island(modes) + L.railIslandGap
        }
        height += island(Array(repeating: L.railRowHeight, count: isCompact ? 5 : 4))
        return height
    }

    init(selectionRect: CGRect, presets: [CapturePreset], activePreset: CapturePreset) {
        self.width = max(1, Int(selectionRect.width.rounded()))
        self.height = max(1, Int(selectionRect.height.rounded()))
        self.presets = presets
        self.activePreset = activePreset
    }
}

private struct CaptureAllInOneToolbarView: View {
    private enum ModeAction: Hashable, CaseIterable {
        case area, fullscreen, window, scrolling, timer, ocr, color, recording
    }

    private enum UtilityAction: Hashable {
        case annotate, copy, save, pin, cancel, overflow
    }

    let state: CaptureAllInOneToolbarState
    let isSideRail: Bool
    let onChromeStateChanged: () -> Void
    let onArea: () -> Void
    let onFullscreen: () -> Void
    let onWindow: () -> Void
    let onColor: () -> Void
    let onScrolling: () -> Void
    let onTimer: () -> Void
    let onOCR: () -> Void
    let onRecording: () -> Void
    let onAnnotate: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void
    let onPin: () -> Void
    let onPresetSelected: (CapturePreset) -> Void
    let onCancel: () -> Void

    @State private var hoveredMode: ModeAction?
    @State private var hoveredUtility: UtilityAction?
    @State private var appeared = false
    @Namespace private var hoverPill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if isSideRail {
                sideRail
            } else {
                horizontalBar
            }
        }
        // Gleitende Akzent-Pille folgt dem Zeiger von Knopf zu Knopf.
        .familyAnimation(FamilyTheme.Motion.select, value: hoveredMode)
        .familyAnimation(FamilyTheme.Motion.select, value: hoveredUtility)
        .captureAppear(appeared, reduceMotion: reduceMotion)
        .onAppear {
            if let forced = CaptureSurfacesDebug.hoveredModeIndex, ModeAction.allCases.indices.contains(forced) {
                hoveredMode = ModeAction.allCases[forced]
            }
            withAnimation(reduceMotion ? FamilyTheme.Motion.reduced : FamilyTheme.Motion.appear) { appeared = true }
        }
        .onHover { hovering in
            if hovering {
                NSCursor.arrow.set()
            }
        }
    }

    // Glas-Umbau Phase 3: schwebende Liquid-Glass-Kapseln wie die Editor-Leiste statt eines
    // dunklen Streifens. Links die Aufnahmearten, rechts Maße/Vorlage und die Aktionen.
    private var horizontalBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 2) {
                    modeButton(.area, icon: "viewfinder", title: "Area", action: onArea)
                    modeButton(.fullscreen, icon: "display", title: "Fullscreen", action: onFullscreen)
                    modeButton(.window, icon: "macwindow", title: "Window", action: onWindow)
                    if FeatureFlags.scrollingCapture {
                        modeButton(.scrolling, icon: "arrow.down.to.line.compact", title: "Scrolling", action: onScrolling)
                    }
                    modeButton(.timer, icon: "timer", title: "Timer", action: onTimer)
                    modeButton(.ocr, textIcon: "Aa", title: "OCR", action: onOCR)
                    modeButton(.color, icon: "eyedropper", title: "Color", action: onColor)
                    if FeatureFlags.screenRecording {
                        modeButton(.recording, icon: "video", title: "Recording", action: onRecording)
                    }
                }
                .captureGlassPill(readable: true)

                HStack(spacing: 4) {
                    dimensionPill
                    presetMenu
                }
                .captureGlassPill(readable: true)

                HStack(spacing: 4) {
                    iconButton("doc.on.doc", kind: .copy, help: "Copy Image and Close", isPrimary: true, action: onCopy)
                    iconButton("square.and.arrow.down", kind: .save, help: "Save selected area", action: onSave)
                    iconButton("pin", kind: .pin, help: "Pin selected area", action: onPin)
                    iconButton("xmark", kind: .cancel, help: "Cancel", action: onCancel)
                }
                .captureGlassPill(readable: true)
            }
            .fixedSize()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sideRail: some View {
        GlassEffectContainer(spacing: Self.railIslandGap) {
            VStack(spacing: Self.railIslandGap) {
                if !state.isCompact || state.showsOverflow {
                    VStack(spacing: Self.railRowGap) {
                        railActionButton(.area, icon: "viewfinder", title: "Area", label: String(localized: "Area"), action: onArea)
                        railActionButton(.fullscreen, icon: "display", title: "Fullscreen", label: String(localized: "Full"), action: onFullscreen)
                        railActionButton(.window, icon: "macwindow", title: "Window", label: String(localized: "Window"), action: onWindow)
                        if FeatureFlags.scrollingCapture {
                            railActionButton(.scrolling, icon: "arrow.down.to.line.compact", title: "Scrolling", label: String(localized: "Scroll"), action: onScrolling)
                        }
                        railActionButton(.timer, icon: "timer", title: "Timer", label: String(localized: "Timer"), action: onTimer)
                        railActionButton(.ocr, textIcon: "Aa", title: "OCR", label: String(localized: "OCR"), action: onOCR)
                        railActionButton(.color, icon: "eyedropper", title: "Color", label: String(localized: "Color"), action: onColor)
                        if FeatureFlags.screenRecording {
                            railActionButton(.recording, icon: "video", title: "Recording", label: String(localized: "Record"), action: onRecording)
                        }
                        railPresetMenu
                    }
                    .railIsland()
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
                }

                VStack(spacing: Self.railRowGap) {
                    railIconButton("doc.on.doc", kind: .copy, help: "Copy Image and Close", label: String(localized: "Copy"), isPrimary: true, action: onCopy)
                    railIconButton("square.and.arrow.down", kind: .save, help: "Save selected area", label: String(localized: "Save"), action: onSave)
                    railIconButton("pin", kind: .pin, help: "Pin selected area", label: String(localized: "Pin"), action: onPin)
                    railIconButton("xmark", kind: .cancel, help: "Cancel", label: String(localized: "Close"), action: onCancel)
                    if state.isCompact {
                        railIconButton(
                            state.showsOverflow ? "chevron.up" : "ellipsis",
                            kind: .overflow,
                            help: state.showsOverflow ? "Hide actions" : "More actions",
                            label: state.showsOverflow ? String(localized: "Less") : String(localized: "More"),
                            action: toggleOverflow
                        )
                    }
                }
                .railIsland()
            }
        }
        .padding(Self.railOuterPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .familyAnimation(FamilyTheme.Motion.select, value: state.showsOverflow)
    }

    // Maße der senkrechten Leiste – `CaptureAllInOneToolbarState.preferredRailHeight` rechnet damit.
    nonisolated static let railRowHeight: CGFloat = 38
    nonisolated static let railPresetHeight: CGFloat = 40
    nonisolated static let railRowGap: CGFloat = 4
    nonisolated static let railIslandPadding: CGFloat = 6
    nonisolated static let railIslandGap: CGFloat = 8
    nonisolated static let railOuterPadding: CGFloat = 4

    /// Akzent-Pille hinter dem Knopf unter dem Zeiger; eine einzige, sie gleitet weiter.
    @ViewBuilder
    private func hoverPillBackground(isHovered: Bool) -> some View {
        if isHovered {
            CaptureAccentPill()
                .matchedGeometryEffect(id: "hoverPill", in: hoverPill)
        }
    }

    private var presetMenu: some View {
        Menu {
            ForEach(state.presets) { preset in
                Button {
                    onPresetSelected(preset)
                } label: {
                    if preset == state.activePreset {
                        Label {
                            Text(localizedPresetDisplayName(preset))
                        } icon: {
                            Image(systemName: "checkmark")
                        }
                    } else {
                        Text(localizedPresetDisplayName(preset))
                    }
                }
            }
        } label: {
            // Ein einziger Text: ein Menü-Etikett aus Text + Bild stellt das Bild sonst nach vorn.
            Text("\(presetLabel)  \(Image(systemName: "chevron.down"))")
                .font(FamilyTheme.font(12, weight: .semibold))
                .foregroundStyle(FamilyTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        // Menü-Etiketten zeichnen keine eigene Fläche – Größe und Hover liegen außen.
        .frame(width: 74, height: 44)
        .captureHoverLift()
        .help("Capture preset")
    }

    private var railPresetMenu: some View {
        Menu {
            ForEach(state.presets) { preset in
                Button {
                    onPresetSelected(preset)
                } label: {
                    if preset == state.activePreset {
                        Label(localizedPresetDisplayName(preset), systemImage: "checkmark")
                    } else {
                        Text(localizedPresetDisplayName(preset))
                    }
                }
            }
        } label: {
            Text("\(railPresetLabel) \(Image(systemName: "chevron.down"))")
                .font(FamilyTheme.font(11, weight: .semibold))
                .foregroundStyle(FamilyTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .padding(.horizontal, 7)
        .frame(width: 60, height: Self.railPresetHeight)
        .background(Capsule().fill(FamilyTheme.textPrimary.opacity(0.07)))
        .captureHoverLift()
        .help(localizedPresetDisplayName(state.activePreset))
    }

    private var presetLabel: String {
        switch state.activePreset {
        case .freeform:
            return String(localized: "Free")
        case .aspectRatio(let width, let height, _):
            return "\(width):\(height)"
        case .fixedSize(let width, let height, let name):
            return name ?? "\(width)x\(height)"
        }
    }

    private var railPresetLabel: String {
        switch state.activePreset {
        case .freeform:
            return String(localized: "Free")
        case .aspectRatio(let width, let height, _):
            return "\(width):\(height)"
        case .fixedSize(let width, let height, let name):
            if let name, name.count <= 6 {
                return localizedPresetName(name)
            }
            return "\(width)x\(height)"
        }
    }

    private func localizedPresetDisplayName(_ preset: CapturePreset) -> String {
        switch preset {
        case .freeform:
            return String(localized: "Free")
        case .aspectRatio(let width, let height, let name):
            let ratio = "\(width):\(height)"
            if let name {
                return "\(ratio) (\(localizedPresetName(name)))"
            }
            return ratio
        case .fixedSize(let width, let height, let name):
            let size = "\(width) x \(height)"
            if let name {
                return "\(size) (\(localizedPresetName(name)))"
            }
            return size
        }
    }

    private func localizedPresetName(_ name: String) -> String {
        switch name {
        case "Square":
            return String(localized: "Square")
        default:
            return name
        }
    }

    private var dimensionPill: some View {
        Text(verbatim: "\(state.width) × \(state.height)")
        .font(.system(size: 14, weight: .semibold).monospacedDigit())
        .foregroundStyle(FamilyTheme.textPrimary)
        .contentTransition(.numericText())
        .familyAnimation(.snappy(duration: 0.18), value: state.width &* 100_003 &+ state.height)
        .lineLimit(1)
        .minimumScaleFactor(0.82)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 12)
        .frame(minWidth: 116, minHeight: 44)
        .background(Capsule().fill(FamilyTheme.textPrimary.opacity(0.07)))
        .help("Selected area size")
    }

    private func modeButton(
        _ kind: ModeAction,
        icon: String? = nil,
        textIcon: String? = nil,
        title: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        let isHovered = hoveredMode == kind
        return Button(action: action) {
            VStack(spacing: 3) {
                Group {
                    if let textIcon {
                        Text(verbatim: textIcon)
                            .font(FamilyTheme.font(14, weight: .bold))
                    } else if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .frame(height: 19)

                Text(title)
                    .font(FamilyTheme.font(10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(isHovered ? Color.white : FamilyTheme.textPrimary)
            .frame(width: 64, height: 44)
            .background { hoverPillBackground(isHovered: isHovered) }
            .contentShape(Capsule())
            .scaleEffect(isHovered && !reduceMotion ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { hoveredMode = kind } else if hoveredMode == kind { hoveredMode = nil }
        }
        .help(title)
        .accessibilityLabel(Text(title))
    }

    private func railActionButton(
        _ kind: ModeAction,
        icon: String? = nil,
        textIcon: String? = nil,
        title: LocalizedStringKey,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        let isHovered = hoveredMode == kind
        return Button(action: action) {
            VStack(spacing: isHovered ? 1 : 0) {
                Group {
                    if let textIcon {
                        Text(verbatim: textIcon)
                            .font(FamilyTheme.font(14, weight: .bold))
                    } else if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                .frame(height: isHovered ? 17 : Self.railRowHeight)

                if isHovered {
                    Text(label)
                        .font(FamilyTheme.font(8.5, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                        .transition(.opacity)
                }
            }
            .foregroundStyle(isHovered ? Color.white : FamilyTheme.textPrimary)
            .frame(width: 60, height: Self.railRowHeight)
            .background { hoverPillBackground(isHovered: isHovered) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { hoveredMode = kind } else if hoveredMode == kind { hoveredMode = nil }
        }
        .help(title)
        .accessibilityLabel(Text(title))
    }

    /// Aktionsknopf der waagerechten Leiste: rund, Glas-neutral; Kopieren ist der Hauptknopf
    /// (Akzent, wie „Sichern“ im Editor). Zeiger darauf: gleitende Akzent-Pille plus Tastenkürzel.
    private func iconButton(
        _ systemName: String,
        kind: UtilityAction,
        help: LocalizedStringKey,
        isPrimary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let isHovered = hoveredUtility == kind
        return Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isPrimary || isHovered ? Color.white : FamilyTheme.textPrimary)
                .frame(width: isPrimary ? 56 : 44, height: 44)
                .background {
                    if isPrimary { CaptureAccentPill(glow: isHovered) }
                    else { hoverPillBackground(isHovered: isHovered) }
                }
                .contentShape(Capsule())
                .scaleEffect(isHovered && !reduceMotion ? 1.05 : 1)
                .overlay(alignment: .top) {
                    if isHovered, let shortcut = utilityShortcut(for: kind) {
                        UtilityShortcutBadge(text: shortcut)
                            .offset(y: -9)
                            .transition(.opacity.combined(with: .offset(y: 3)))
                    }
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { hoveredUtility = kind } else if hoveredUtility == kind { hoveredUtility = nil }
        }
        .help(utilityHelp(for: kind, fallback: help))
        .accessibilityLabel(Text(help))
    }

    private func railIconButton(
        _ systemName: String,
        kind: UtilityAction,
        help: LocalizedStringKey,
        label: String,
        isPrimary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let isHovered = hoveredUtility == kind
        return Button(action: action) {
            VStack(spacing: isHovered ? 1 : 0) {
                Image(systemName: systemName)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(height: isHovered ? 17 : Self.railRowHeight)

                if isHovered {
                    Text(label)
                        .font(FamilyTheme.font(8.5, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                        .transition(.opacity)
                }
            }
            .foregroundStyle(isPrimary || isHovered ? Color.white : FamilyTheme.textPrimary)
            .frame(width: 60, height: Self.railRowHeight)
            .background {
                if isPrimary { CaptureAccentPill(glow: isHovered) }
                else { hoverPillBackground(isHovered: isHovered) }
            }
            .contentShape(Capsule())
            .overlay(alignment: .topTrailing) {
                if isHovered, let shortcut = utilityShortcut(for: kind) {
                    UtilityShortcutBadge(text: shortcut)
                        .offset(x: 6, y: -6)
                        .transition(.opacity)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { hoveredUtility = kind } else if hoveredUtility == kind { hoveredUtility = nil }
        }
        .help(utilityHelp(for: kind, fallback: help))
        .accessibilityLabel(Text(label))
    }

    private func utilityShortcut(for kind: UtilityAction) -> String? {
        switch kind {
        case .copy:
            return "⌘C"
        case .save:
            return "⌘S"
        case .pin:
            return "⌘P"
        case .cancel:
            return "Esc"
        case .annotate, .overflow:
            return nil
        }
    }

    /// Shortcut string used inside the hover tooltip. Copy advertises every
    /// binding that maps to copy-and-close — ⌘C (falls back when no annotation
    /// object is selected), Return, and ⌘⇧C — so users can discover the
    /// alternatives without having to guess (issue #237).
    private func utilityHelpShortcut(for kind: UtilityAction) -> String? {
        switch kind {
        case .copy:
            return "⌘C · ⏎ · ⌘⇧C"
        case .save, .pin, .cancel, .annotate, .overflow:
            return utilityShortcut(for: kind)
        }
    }

    private func utilityHelp(for kind: UtilityAction, fallback: LocalizedStringKey) -> Text {
        guard let shortcut = utilityHelpShortcut(for: kind) else {
            return Text(fallback)
        }

        switch kind {
        case .copy:
            return Text(String(localized: "Copy selected area (\(shortcut))"))
        case .save:
            return Text(String(localized: "Save selected area (\(shortcut))"))
        case .pin:
            return Text(String(localized: "Pin selected area (\(shortcut))"))
        case .cancel:
            return Text(String(localized: "Cancel (\(shortcut))"))
        case .annotate, .overflow:
            return Text(fallback)
        }
    }

    private func toggleOverflow() {
        guard state.isCompact else { return }
        state.showsOverflow.toggle()
        onChromeStateChanged()
    }
}

private struct UtilityShortcutBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 8.5, weight: .bold, design: .rounded))
            .foregroundStyle(FamilyTheme.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .frame(height: 15)
            // Feste Fläche, kein Glas auf Glas.
            .background(Capsule().fill(FamilyTheme.card))
            .overlay(Capsule().stroke(FamilyTheme.cardStroke, lineWidth: 0.6))
            .shadow(color: FamilyTheme.Floating.shadowColor, radius: 3, y: 1)
            .allowsHitTesting(false)
    }
}

/// Messhilfe (nur Testkopie, gesetzt von `SichttestHooks`): zeigt die Hover-Optik ohne Zeiger.
@MainActor
enum CaptureSurfacesDebug {
    /// Index der Aufnahmeart (Reihenfolge wie in der Leiste), die als „überfahren“ erscheint.
    static var hoveredModeIndex: Int?
}

private extension View {
    /// Senkrechte Glas-Insel der Seitenleiste.
    func railIsland() -> some View {
        padding(CaptureAllInOneToolbarView.railIslandPadding)
            .familyLiquidGlass(in: RoundedRectangle(cornerRadius: 25, style: .continuous),
                               tint: FamilyTheme.glassReadableTint)
    }
}

/// Internal rather than file-private so interaction tests can drive its
/// mouse/flags handling directly.
final class AllInOneSelectionOverlayView: NSView {
    var onSelectionPreviewChanged: ((CGRect) -> Void)?
    var onSelectionChanged: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    var passesThroughSelectionBody = false {
        didSet { window?.invalidateCursorRects(for: self) }
    }

    private enum DragOperation {
        case none
        case move(startRect: CGRect, startPoint: CGPoint)
        case resize(handle: CaptureSelectionResizeHandle, startRect: CGRect)
        case create(startPoint: CGPoint)
    }

    private var selectionRect: CGRect {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
            updateAccessibilityValue(postNotification: true)
        }
    }
    private let minSelectionSize: CGSize
    private var activePreset: CapturePreset
    private let hitSlop: CGFloat = 26
    /// Resize hot-zone reach while annotating (`passesThroughSelectionBody`).
    /// The inner reach stays thin so a drag starting near—but inside—the edge
    /// begins an annotation instead of a resize; it still covers the 3.5pt
    /// inner radius of the drawn handle dots so clicking a visible handle
    /// always resizes. The outer reach stays generous because nothing outside
    /// the selection competes for those points.
    private let annotationInnerHitSlop: CGFloat = 4
    private let annotationOuterHitSlop: CGFloat = 12
    private var dragOperation: DragOperation = .none
    /// Holding Space lets a drag inside the selection move it, even while annotating.
    var isSpaceHeld = false {
        didSet {
            guard isSpaceHeld != oldValue else { return }
            window?.invalidateCursorRects(for: self)
            if let window {
                updateCursor(for: convert(window.mouseLocationOutsideOfEventStream, from: nil))
            }
        }
    }
    private var trackingArea: NSTrackingArea?
    /// Whether Shift is currently held, locking the drag to a 1:1 square.
    private var squareLock = false
    /// Whether the configurable extra key (default C) is held.
    private var centerLockKeyHeld = false
    /// Extra key that, with Shift, grows a create-drag from the click center.
    var squareCenterLockShortcut = SquareCenterLockShortcut.default
    /// Last pointer location during a drag, so a live Shift toggle can recompute.
    private var lastDragPoint: CGPoint = .zero

    init(
        frame: CGRect,
        selectionRect: CGRect,
        minSelectionSize: CGSize,
        activePreset: CapturePreset
    ) {
        self.selectionRect = selectionRect.standardized
        self.minSelectionSize = minSelectionSize
        self.activePreset = activePreset
        super.init(frame: frame)
        _ = chrome.install(in: self)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Selection size")
        updateAccessibilityValue(postNotification: false)
    }

    /// Maßanzeige als Glas-Kapsel (Phase 3); Abdunklung und Rahmen bleiben gezeichnet.
    private let chrome = CaptureOverlayChromeModel()

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if passesThroughSelectionBody,
           !wantsMouseEvents(at: point) {
            return nil
        }

        return super.hitTest(point)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    func setSelectionRect(_ selectionRect: CGRect) {
        self.selectionRect = selectionRect.standardized
    }

    private func updateAccessibilityValue(postNotification: Bool) {
        setAccessibilityValue(CaptureSelectionChromeLayout.dimensionText(for: selectionRect.size))
        if postNotification {
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
    }

    func setActivePreset(_ preset: CapturePreset) {
        activePreset = preset
        window?.invalidateCursorRects(for: self)
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea

        super.updateTrackingAreas()
    }

    override func resetCursorRects() {
        super.resetCursorRects()

        let rect = selectionRect.standardized
        guard rect.width > 0, rect.height > 0 else { return }

        if activePreset.isFixedSize {
            addCursorRect(rect, cursor: .openHand)
            return
        }

        // Match `hitTarget(at:)`: while annotating, the resize zones stay thin
        // inside the selection so they don't overlap the annotation area.
        let innerSlop = passesThroughSelectionBody ? annotationInnerHitSlop : hitSlop
        let outerSlop = passesThroughSelectionBody ? annotationOuterHitSlop : hitSlop
        let bandWidth = innerSlop + outerSlop
        let horizontalEdgeWidth = max(0, rect.width - innerSlop * 2)
        let verticalEdgeHeight = max(0, rect.height - innerSlop * 2)

        addCursorRect(
            CGRect(x: rect.minX - outerSlop, y: rect.maxY - innerSlop, width: bandWidth, height: bandWidth),
            cursor: AllInOneResizeCursor.topLeft
        )
        addCursorRect(
            CGRect(x: rect.maxX - innerSlop, y: rect.maxY - innerSlop, width: bandWidth, height: bandWidth),
            cursor: AllInOneResizeCursor.topRight
        )
        addCursorRect(
            CGRect(x: rect.maxX - innerSlop, y: rect.minY - outerSlop, width: bandWidth, height: bandWidth),
            cursor: AllInOneResizeCursor.bottomRight
        )
        addCursorRect(
            CGRect(x: rect.minX - outerSlop, y: rect.minY - outerSlop, width: bandWidth, height: bandWidth),
            cursor: AllInOneResizeCursor.bottomLeft
        )

        if horizontalEdgeWidth > 0 {
            addCursorRect(
                CGRect(x: rect.minX + innerSlop, y: rect.maxY - innerSlop, width: horizontalEdgeWidth, height: bandWidth),
                cursor: AllInOneResizeCursor.vertical
            )
            addCursorRect(
                CGRect(x: rect.minX + innerSlop, y: rect.minY - outerSlop, width: horizontalEdgeWidth, height: bandWidth),
                cursor: AllInOneResizeCursor.vertical
            )
        }

        if verticalEdgeHeight > 0 {
            addCursorRect(
                CGRect(x: rect.minX - outerSlop, y: rect.minY + innerSlop, width: bandWidth, height: verticalEdgeHeight),
                cursor: AllInOneResizeCursor.horizontal
            )
            addCursorRect(
                CGRect(x: rect.maxX - innerSlop, y: rect.minY + innerSlop, width: bandWidth, height: verticalEdgeHeight),
                cursor: AllInOneResizeCursor.horizontal
            )
        }

        if !passesThroughSelectionBody || isSpaceHeld {
            let bodyRect = rect.insetBy(dx: innerSlop, dy: innerSlop)
            if bodyRect.width > 0, bodyRect.height > 0 {
                addCursorRect(bodyRect, cursor: .openHand)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)

        let point = convert(event.locationInWindow, from: nil)
        // Seed the pointer and Shift state before any early return (including
        // the fixed-size move path) so a Shift press that lands before the first
        // mouseDragged recomputes from this press point instead of `.zero` or the
        // previous drag's endpoint.
        lastDragPoint = point
        squareLock = event.modifierFlags.contains(.shift)
        centerLockKeyHeld = isCenterLockKeyPressed(alongside: event)

        if let fixedSize = activePreset.fixedPixelSize {
            if hitTarget(at: point) != nil {
                dragOperation = .move(startRect: selectionRect, startPoint: point)
                NSCursor.closedHand.set()
                return
            }

            let fixedRect = CaptureSelectionGeometry.fixedSize(
                CGSize(width: fixedSize.width, height: fixedSize.height),
                centeredAt: point,
                in: bounds
            )
            selectionRect = fixedRect
            dragOperation = .move(startRect: fixedRect, startPoint: point)
            onSelectionPreviewChanged?(selectionRect)
            NSCursor.closedHand.set()
            return
        }

        switch hitTarget(at: point) {
        case .resize(let handle):
            dragOperation = .resize(handle: handle, startRect: selectionRect)
            cursor(for: .resize(handle), at: point).set()
        case .move:
            dragOperation = .move(startRect: selectionRect, startPoint: point)
            NSCursor.closedHand.set()
        case nil:
            dragOperation = .create(startPoint: point)
            NSCursor.crosshair.set()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        lastDragPoint = point
        squareLock = event.modifierFlags.contains(.shift)
        updateSelectionForDrag(to: point)
    }

    override func flagsChanged(with event: NSEvent) {
        handleFlagsChanged(event)
        super.flagsChanged(with: event)
    }

    /// Holding or releasing Shift mid-drag re-runs the current drag against the
    /// last pointer location so the square lock engages/releases live. Shared
    /// entry for the view's `flagsChanged` and the window's local flags monitor,
    /// so the toggle lands even when this view is not first responder.
    func handleFlagsChanged(_ event: NSEvent) {
        let nextSquareLock = event.modifierFlags.contains(.shift)
        guard nextSquareLock != squareLock else { return }
        squareLock = nextSquareLock
        if case .none = dragOperation { return }
        updateSelectionForDrag(to: lastDragPoint)
    }

    /// Shared entry for key-down/up from the view and the window's local
    /// monitor. Returns `true` when the extra key was handled and should not
    /// propagate (so ⌘⇧C can still copy).
    @discardableResult
    func handleCenterLockKeyEvent(_ event: NSEvent) -> Bool {
        guard event.keyCode == squareCenterLockShortcut.keyCode, !event.isARepeat else {
            return false
        }

        if event.type == .keyUp {
            centerLockKeyHeld = false
            if case .create = dragOperation {
                updateSelectionForDrag(to: lastDragPoint)
            }
            return event.modifierFlags.contains(.shift) || isCreateDrag
        }

        if !event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
            return false
        }

        let shouldConsume = event.modifierFlags.contains(.shift) || isCreateDrag
        guard shouldConsume else { return false }

        centerLockKeyHeld = true
        if case .create = dragOperation {
            updateSelectionForDrag(to: lastDragPoint)
        }
        return true
    }

    private var isCreateDrag: Bool {
        if case .create = dragOperation { return true }
        return false
    }

    private func isCenterLockKeyPressed(alongside event: NSEvent) -> Bool {
        event.modifierFlags.intersection([.command, .option, .control]).isEmpty
            && squareCenterLockShortcut.isHardwareKeyPressed
    }

    private var isCenterLocked: Bool {
        squareLock && centerLockKeyHeld
    }

    /// Applies the active drag operation for a pointer location, honoring the
    /// resolved aspect ratio (Shift locks to 1:1, otherwise the preset ratio).
    private func updateSelectionForDrag(to point: CGPoint) {
        let ratio = CaptureSelectionGeometry.selectionAspectRatio(
            presetRatio: activePreset.isFixedSize ? nil : activePreset.ratio,
            squareLock: squareLock
        )

        switch dragOperation {
        case .none:
            return
        case let .move(startRect, startPoint):
            selectionRect = CaptureSelectionGeometry.move(
                startRect,
                by: CGVector(dx: point.x - startPoint.x, dy: point.y - startPoint.y),
                in: bounds
            )
        case let .resize(handle, startRect):
            if let ratio {
                selectionRect = CaptureSelectionGeometry.resize(
                    startRect,
                    handle: handle,
                    to: point,
                    in: bounds,
                    minSize: minSelectionSize,
                    aspectRatio: ratio
                )
            } else {
                selectionRect = CaptureSelectionGeometry.resize(
                    startRect,
                    handle: handle,
                    to: point,
                    in: bounds,
                    minSize: minSelectionSize
                )
            }
        case let .create(startPoint):
            if let ratio {
                selectionRect = CaptureSelectionGeometry.rect(
                    from: startPoint,
                    to: point,
                    in: bounds,
                    minSize: minSelectionSize,
                    aspectRatio: ratio,
                    centered: isCenterLocked
                )
            } else {
                selectionRect = CaptureSelectionGeometry.rect(
                    from: startPoint,
                    to: point,
                    in: bounds,
                    minSize: minSelectionSize
                )
            }
        }

        onSelectionPreviewChanged?(selectionRect)
    }

    override func mouseUp(with event: NSEvent) {
        guard case .none = dragOperation else {
            dragOperation = .none
            onSelectionChanged?(selectionRect)
            updateCursor(for: convert(event.locationInWindow, from: nil))
            return
        }
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(for: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func keyDown(with event: NSEvent) {
        if handleCenterLockKeyEvent(event) {
            return
        }
        guard event.keyCode == 53 else {
            super.keyDown(with: event)
            return
        }

        onCancel?()
    }

    override func keyUp(with event: NSEvent) {
        if handleCenterLockKeyEvent(event) {
            return
        }
        super.keyUp(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let rect = selectionRect.standardized

        context.saveGState()
        context.setFillColor(NSColor.black.withAlphaComponent(0.32).cgColor)
        context.fill(bounds)
        context.setBlendMode(.clear)
        context.fill(rect)
        context.restoreGState()

        drawSelectionBorder(in: context, rect: rect)
        drawDimensionHUD(in: context, selectionRect: rect)
        drawSelectionHandles(in: context, rect: rect)
    }

    private func updateCursor(for point: CGPoint) {
        guard wantsMouseEvents(at: point) else { return }

        if activePreset.isFixedSize {
            if selectionRect.contains(point) {
                NSCursor.openHand.set()
            } else {
                NSCursor.arrow.set()
            }
            return
        }

        cursor(
            for: hitTarget(at: point),
            at: point,
        ).set()
    }

    /// Hit test used by mouse handling, cursor feedback, and event pass-through.
    /// While annotating (`passesThroughSelectionBody`), the resize hot zone
    /// reaches only a few points inside the selection so near-edge drags can
    /// start an annotation; during initial selection the full `hitSlop` applies.
    private func hitTarget(at point: CGPoint) -> CaptureSelectionHitTarget? {
        if passesThroughSelectionBody {
            return CaptureSelectionGeometry.hitTarget(
                at: point,
                selectionRect: selectionRect,
                innerSlop: annotationInnerHitSlop,
                outerSlop: annotationOuterHitSlop
            )
        }
        return CaptureSelectionGeometry.hitTarget(
            at: point,
            selectionRect: selectionRect,
            hitSlop: hitSlop
        )
    }

    func wantsMouseEvents(at point: CGPoint) -> Bool {
        guard passesThroughSelectionBody else { return true }
        // Keep capturing for the whole gesture once a drag starts: the window's
        // ignoresMouseEvents is re-evaluated on every event, so without this a
        // pointer that strays from the edge mid-resize (min-size clamping,
        // aspect ratio, fast movement) would flip the window to click-through
        // and the drag would lose its mouseUp.
        if case .none = dragOperation {} else { return true }

        switch hitTarget(at: point) {
        case .resize:
            return true
        case .move:
            return isSpaceHeld
        case nil:
            return true
        }
    }

    private func cursor(for target: CaptureSelectionHitTarget?, at point: CGPoint) -> NSCursor {
        switch target {
        case .move:
            return .openHand
        case .resize(.left), .resize(.right):
            return AllInOneResizeCursor.horizontal
        case .resize(.top), .resize(.bottom):
            return AllInOneResizeCursor.vertical
        case .resize(.topLeft):
            return AllInOneResizeCursor.topLeft
        case .resize(.topRight):
            return AllInOneResizeCursor.topRight
        case .resize(.bottomRight):
            return AllInOneResizeCursor.bottomRight
        case .resize(.bottomLeft):
            return AllInOneResizeCursor.bottomLeft
        case nil:
            return .arrow
        }
    }

    private func drawSelectionBorder(in context: CGContext, rect: CGRect) {
        context.saveGState()
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        context.setLineWidth(3)
        context.stroke(rect)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1.5)
        context.stroke(rect)
        context.restoreGState()
    }

    private func drawSelectionHandles(in context: CGContext, rect: CGRect) {
        let handles = CaptureSelectionChromeLayout.visibleHandles(
            for: rect.size,
            isFixedSize: activePreset.isFixedSize
        )
        for handle in handles {
            let center = point(for: handle, in: rect)
            let handleRect = CGRect(x: center.x - 3.5, y: center.y - 3.5, width: 7, height: 7)

            context.saveGState()
            context.setShadow(
                offset: .zero,
                blur: 4,
                color: NSColor.black.withAlphaComponent(0.55).cgColor
            )
            context.setFillColor(NSColor.white.cgColor)
            context.setStrokeColor(NSColor.black.withAlphaComponent(0.65).cgColor)
            context.setLineWidth(1)
            context.addEllipse(in: handleRect)
            context.drawPath(using: .fillStroke)
            context.restoreGState()
        }
    }

    private func point(for handle: CaptureSelectionResizeHandle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft:
            return CGPoint(x: rect.minX, y: rect.maxY)
        case .top:
            return CGPoint(x: rect.midX, y: rect.maxY)
        case .topRight:
            return CGPoint(x: rect.maxX, y: rect.maxY)
        case .right:
            return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight:
            return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottom:
            return CGPoint(x: rect.midX, y: rect.minY)
        case .bottomLeft:
            return CGPoint(x: rect.minX, y: rect.minY)
        case .left:
            return CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    private func drawDimensionHUD(in context: CGContext, selectionRect: CGRect) {
        let text = CaptureSelectionChromeLayout.dimensionText(for: selectionRect.size)
        // Feste Breite für bis zu vier Stellen je Maß, damit die Kapsel beim Ziehen ruhig bleibt.
        let hudSize = CaptureOverlayChromeModel.capsuleSize(
            for: text.count < 11 ? "8888 × 8888" : text, horizontalPadding: 10, height: 24)
        let origin = CaptureSelectionChromeLayout.dimensionHUDOrigin(
            selectionRect: selectionRect,
            hudSize: hudSize,
            in: bounds
        )
        chrome.set([.init(id: "dimension", text: text, style: .metric, frame: CGRect(origin: origin, size: hudSize))],
                   viewHeight: bounds.height)
    }
}

@MainActor
private enum AllInOneResizeCursor {
    static let vertical = makeCursor(axis: CGVector(dx: 0, dy: 1))
    static let horizontal = makeCursor(axis: CGVector(dx: 1, dy: 0))
    static let topLeft = makeCursor(axis: CGVector(dx: -1, dy: 1))
    static let topRight = makeCursor(axis: CGVector(dx: 1, dy: 1))
    static let bottomRight = makeCursor(axis: CGVector(dx: 1, dy: -1))
    static let bottomLeft = makeCursor(axis: CGVector(dx: -1, dy: -1))

    private static func makeCursor(axis: CGVector) -> NSCursor {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        drawCursorTriangles(
            center: CGPoint(x: size.width / 2, y: size.height / 2),
            axis: axis,
            color: NSColor.black.withAlphaComponent(0.70),
            lineWidth: 2.8
        )
        drawCursorTriangles(
            center: CGPoint(x: size.width / 2, y: size.height / 2),
            axis: axis,
            color: .white,
            lineWidth: 1.25
        )

        image.unlockFocus()
        return NSCursor(image: image, hotSpot: CGPoint(x: size.width / 2, y: size.height / 2))
    }

    private static func drawCursorTriangles(
        center: CGPoint,
        axis: CGVector,
        color: NSColor,
        lineWidth: CGFloat
    ) {
        let length = max(1, hypot(axis.dx, axis.dy))
        let ux = axis.dx / length
        let uy = axis.dy / length
        let px = -uy
        let py = ux
        let tipOffset: CGFloat = 6.2
        let baseOffset: CGFloat = 2.2
        let halfBase: CGFloat = 3.1
        let forward = CGPoint(x: center.x + ux * tipOffset, y: center.y + uy * tipOffset)
        let forwardBase = CGPoint(x: center.x + ux * baseOffset, y: center.y + uy * baseOffset)
        let backward = CGPoint(x: center.x - ux * tipOffset, y: center.y - uy * tipOffset)
        let backwardBase = CGPoint(x: center.x - ux * baseOffset, y: center.y - uy * baseOffset)

        color.setStroke()

        let path = NSBezierPath()
        path.lineJoinStyle = .round
        path.lineWidth = lineWidth

        path.move(to: forward)
        path.line(to: CGPoint(x: forwardBase.x + px * halfBase, y: forwardBase.y + py * halfBase))
        path.move(to: forward)
        path.line(to: CGPoint(x: forwardBase.x - px * halfBase, y: forwardBase.y - py * halfBase))
        path.move(to: backward)
        path.line(to: CGPoint(x: backwardBase.x + px * halfBase, y: backwardBase.y + py * halfBase))
        path.move(to: backward)
        path.line(to: CGPoint(x: backwardBase.x - px * halfBase, y: backwardBase.y - py * halfBase))
        path.stroke()
    }
}

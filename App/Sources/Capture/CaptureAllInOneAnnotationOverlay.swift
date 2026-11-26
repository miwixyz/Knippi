import AppKit
import AnnotationKit
import CaptureKit
import OCRKit
import SwiftUI

@MainActor
final class CaptureAllInOneAnnotationOverlay {
    private let screen: NSScreen
    private var canvasWindow: NSPanel?
    private var toolbarWindow: NSPanel?
    private var session: AllInOneAnnotationSession?
    private var currentSelectionRect: CGRect?

    init(screen: NSScreen) {
        self.screen = screen
    }

    func show(sourceImage: CGImage, selectionRect: CGRect, avoidingFrame: CGRect?) {
        let session = AllInOneAnnotationSession(
            sourceImage: sourceImage,
            displayScale: displayScale(for: sourceImage, selectionRect: selectionRect)
        )
        session.onRequestCanvasFocus = { [weak self] in
            self?.focusCanvas()
        }
        session.onRequestToolbarLayout = { [weak self] in
            self?.repositionToolbar(selectionRect: selectionRect, avoidingFrame: avoidingFrame, animated: true)
        }
        session.availableWidth = selectionRect.width
        self.session = session
        currentSelectionRect = selectionRect

        showCanvas(session: session, selectionRect: selectionRect)
        showToolbar(session: session, selectionRect: selectionRect, avoidingFrame: avoidingFrame)
    }

    func update(sourceImage: CGImage, selectionRect: CGRect, avoidingFrame: CGRect?, isLive: Bool = false) {
        let previousSelectionRect = currentSelectionRect
        if session == nil {
            let newSession = AllInOneAnnotationSession(
                sourceImage: sourceImage,
                displayScale: displayScale(for: sourceImage, selectionRect: selectionRect)
            )
            newSession.onRequestCanvasFocus = { [weak self] in
                self?.focusCanvas()
            }
            newSession.onRequestToolbarLayout = { [weak self] in
                self?.repositionToolbar(selectionRect: selectionRect, avoidingFrame: avoidingFrame, animated: true)
            }
            session = newSession
        }

        guard let session else { return }
        let objectOffset = objectOffset(
            from: previousSelectionRect,
            to: selectionRect,
            sourceImage: session.sourceImage
        )
        session.replaceSourceImage(
            sourceImage,
            displayScale: displayScale(for: sourceImage, selectionRect: selectionRect),
            objectOffset: objectOffset
        )
        let wasCompact = session.usesCompactToolbar
        session.availableWidth = selectionRect.width
        if wasCompact != session.usesCompactToolbar {
            session.showsOverflow = false
        }
        session.onRequestToolbarLayout = { [weak self] in
            self?.repositionToolbar(selectionRect: selectionRect, avoidingFrame: avoidingFrame, animated: true)
        }
        canvasWindow?.setFrame(canvasFrame(for: selectionRect), display: true)
        toolbarWindow?.setFrame(toolbarFrame(for: selectionRect, avoidingFrame: avoidingFrame), display: !isLive)
        currentSelectionRect = selectionRect
    }

    func close() {
        toolbarWindow?.close()
        toolbarWindow = nil
        canvasWindow?.close()
        canvasWindow = nil
        session = nil
        currentSelectionRect = nil
    }

    func renderImage(afterCommit completion: @escaping (CGImage?) -> Void) {
        guard let session else {
            completion(nil)
            return
        }
        session.renderImage(afterCommit: completion)
    }

    var isEditingText: Bool {
        session?.isEditingText ?? false
    }

    var annotationDocument: AnnotationDocument? {
        session?.document
    }

    func performAnnotationClipboardShortcut(with event: NSEvent) -> Bool {
        canvasWindow?.contentView?.layoutSubtreeIfNeeded()
        return canvasWindow?.routeAnnotationClipboardShortcutToCanvas(event) ?? false
    }

    private func showCanvas(session: AllInOneAnnotationSession, selectionRect: CGRect) {
        let panel = AllInOneAnnotationPanel(
            contentRect: canvasFrame(for: selectionRect),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver + 1
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        panel.contentView = AllInOneCanvasHostingView(rootView: AllInOneAnnotationCanvasView(
            session: session
        ))
        canvasWindow = panel
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func showToolbar(session: AllInOneAnnotationSession, selectionRect: CGRect, avoidingFrame: CGRect?) {
        let panel = AllInOneAnnotationPanel(
            contentRect: toolbarFrame(for: selectionRect, avoidingFrame: avoidingFrame),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver + 3
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Schwebende Glas-Kapseln werfen ihren Schatten selbst (kein Fensterrechteck).
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let hostingView = AllInOneAnnotationToolbarHostingView(rootView: AllInOneAnnotationToolbarView(session: session))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
        toolbarWindow = panel
        panel.orderFrontRegardless()
    }

    func repositionToolbar(selectionRect: CGRect, avoidingFrame: CGRect?, animated: Bool) {
        let frame = toolbarFrame(for: selectionRect, avoidingFrame: avoidingFrame)
        if animated {
            toolbarWindow?.setFrame(frame, display: true, animate: true)
        } else {
            toolbarWindow?.setFrame(frame, display: true)
        }
    }

    private func focusCanvas() {
        guard let canvasWindow else { return }
        canvasWindow.makeKey()
        if let canvas = canvasWindow.contentView?.firstSubview(of: AnnotationCanvasNSView.self) {
            canvasWindow.makeFirstResponder(canvas)
        }
    }

    private func canvasFrame(for selectionRect: CGRect) -> CGRect {
        let inset: CGFloat = 2
        let rect = selectionRect.insetBy(dx: inset, dy: inset)
        return CGRect(
            x: screen.frame.minX + rect.minX,
            y: screen.frame.minY + rect.minY,
            width: max(1, rect.width),
            height: max(1, rect.height)
        )
    }

    private func toolbarFrame(for selectionRect: CGRect, avoidingFrame: CGRect?) -> CGRect {
        let margin: CGFloat = 12
        let gap: CGFloat = 10
        let globalRect = CGRect(
            x: screen.frame.minX + selectionRect.minX,
            y: screen.frame.minY + selectionRect.minY,
            width: selectionRect.width,
            height: selectionRect.height
        )
        let session = session
        let density = session?.toolbarDensity ?? CaptureChromeLayout.annotationDensity(for: globalRect.width)
        let usesCompact = density != .regular
        let usesMini = density == .mini
        let showsOverflow = session?.showsOverflow ?? false
        let height = CaptureChromeLayout.annotationToolbarHeight(
            density: density,
            showsOverflow: showsOverflow
        )
        let width: CGFloat
        let maxToolbarWidth = screen.visibleFrame.width - margin * 2
        if usesCompact {
            if usesMini && !showsOverflow {
                width = min(300, maxToolbarWidth)
            } else if showsOverflow {
                width = min(840, maxToolbarWidth)
            } else {
                width = min(max(480, globalRect.width), min(840, maxToolbarWidth))
            }
        } else {
            // Glas-Kapseln mit Editor-Knopfgrößen brauchen etwas mehr Breite als der alte Streifen;
            // das Fenster ist durchsichtig, nur die Kapseln sind sichtbar.
            width = min(max(1_120, globalRect.width), min(1_120, maxToolbarWidth))
        }

        func clampedX(width: CGFloat) -> CGFloat {
            let minX = screen.visibleFrame.minX + margin
            let maxX = screen.visibleFrame.maxX - width - margin
            return min(max(globalRect.midX - width / 2, minX), maxX)
        }

        let belowY = globalRect.minY - height - gap
        let aboveY = globalRect.maxY + gap

        var candidates: [CGRect] = []
        if belowY >= screen.visibleFrame.minY + margin {
            candidates.append(CGRect(x: clampedX(width: width), y: belowY, width: width, height: height))
        }
        if aboveY + height <= screen.visibleFrame.maxY - margin {
            candidates.append(CGRect(x: clampedX(width: width), y: aboveY, width: width, height: height))
        }
        candidates.append(CGRect(
            x: clampedX(width: width),
            y: max(screen.visibleFrame.minY + margin, min(globalRect.minY + margin, screen.visibleFrame.maxY - height - margin)),
            width: width,
            height: height
        ))

        guard let avoidingFrame else {
            return candidates[0]
        }

        let inflatedAvoidance = avoidingFrame.insetBy(dx: -8, dy: -8)
        for candidate in candidates {
            let adjusted = toolbarFrame(candidate, avoiding: inflatedAvoidance, margin: margin, gap: gap)
            if !adjusted.intersects(inflatedAvoidance) {
                return adjusted
            }
        }

        return toolbarFrame(candidates[0], avoiding: inflatedAvoidance, margin: margin, gap: gap)
    }

    private func toolbarFrame(_ frame: CGRect, avoiding avoidance: CGRect, margin: CGFloat, gap: CGFloat) -> CGRect {
        guard frame.maxY > avoidance.minY && frame.minY < avoidance.maxY else {
            return frame
        }

        let visible = screen.visibleFrame
        let leftWidth = avoidance.minX - gap - (visible.minX + margin)
        let rightWidth = (visible.maxX - margin) - (avoidance.maxX + gap)

        if frame.midX <= avoidance.midX, leftWidth >= frame.width {
            return CGRect(x: avoidance.minX - gap - frame.width, y: frame.minY, width: frame.width, height: frame.height)
        }
        if rightWidth >= frame.width {
            return CGRect(x: avoidance.maxX + gap, y: frame.minY, width: frame.width, height: frame.height)
        }
        if leftWidth >= frame.width {
            return CGRect(x: avoidance.minX - gap - frame.width, y: frame.minY, width: frame.width, height: frame.height)
        }

        return frame
    }

    private func displayScale(for image: CGImage, selectionRect: CGRect) -> CGFloat {
        CaptureDisplayGeometry.displayScale(
            imageSize: CGSize(width: image.width, height: image.height),
            screenRect: selectionRect
        ) ?? 1
    }

    private func objectOffset(from oldRect: CGRect?, to newRect: CGRect, sourceImage: CGImage) -> CGSize {
        guard let oldRect else { return .zero }
        let scale = displayScale(for: sourceImage, selectionRect: oldRect)
        return CGSize(
            width: (oldRect.minX - newRect.minX) * scale,
            height: (newRect.maxY - oldRect.maxY) * scale
        )
    }
}

private final class AllInOneAnnotationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class AllInOneCanvasHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        if let canvas = firstSubview(of: AnnotationCanvasNSView.self) {
            window?.makeFirstResponder(canvas)
        }
        super.mouseDown(with: event)
    }
}

private final class AllInOneAnnotationToolbarHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool {
        get { false }
        set { }
    }
}

@MainActor
final class AllInOneAnnotationSession: ObservableObject {
    @Published var sourceImage: CGImage
    @Published var displayScale: CGFloat
    @Published var currentTool: AnnotationTool
    @Published var currentColor: AnnotationColor
    @Published var filled: Bool
    @Published var textFillEnabled: Bool
    @Published var textOutlineEnabled: Bool
    @Published var textStrokeEnabled: Bool
    @Published var lineWidth: CGFloat
    @Published var textFontSize: CGFloat
    @Published var strokePattern: StrokePattern
    @Published var redactionMode: RedactionMode
    @Published var isEditingText = false
    @Published var refreshTrigger = 0
    @Published var commitEditingTrigger = 0
    @Published var textRegions: [CGRect] = []
    @Published var availableWidth: CGFloat = 0
    @Published var showsOverflow = false

    let document: AnnotationDocument
    var onRequestCanvasFocus: (() -> Void)?
    var onRequestToolbarLayout: (() -> Void)?

    private var savedLineWidth: Double {
        get { UserDefaults.standard.object(forKey: "annotationShapeWidth") as? Double ?? 3 }
        set { UserDefaults.standard.set(newValue, forKey: "annotationShapeWidth") }
    }

    init(sourceImage: CGImage, displayScale: CGFloat) {
        self.sourceImage = sourceImage
        self.displayScale = displayScale
        self.document = AnnotationDocument(imageSize: CGSize(width: sourceImage.width, height: sourceImage.height))
        self.currentTool = Self.storedTool()
        self.currentColor = Self.storedColor()
        self.filled = UserDefaults.standard.bool(forKey: "annotationFilled")
        self.textFillEnabled = UserDefaults.standard.bool(forKey: "annotationTextFillEnabled")
        self.textOutlineEnabled = UserDefaults.standard.bool(forKey: "annotationTextOutlineEnabled")
        self.textStrokeEnabled = Self.storedTextStrokeEnabled()
        self.lineWidth = Self.storedWidth(for: Self.storedTool())
        self.textFontSize = Self.storedTextFontSize()
        self.strokePattern = Self.storedStrokePattern()
        self.redactionMode = Self.storedRedactionMode()

        Task { [weak self] in
            guard let self else { return }
            if let regions = try? await OCRProcessFallback.recognize(
                image: sourceImage,
                level: .fast,
                detectURLs: false
            ) {
                self.textRegions = regions.map(\.boundingBox)
            }
        }
    }

    var currentStyle: AnnotationKit.StrokeStyle {
        AnnotationKit.StrokeStyle(
            color: currentColor,
            lineWidth: lineWidth,
            opacity: currentTool == .highlighter ? 0.35 : 1.0,
            filled: filled,
            pattern: strokePattern,
            arrowHead: ArrowHeadStyle(rawValue: UserDefaults.standard.string(forKey: "annotationArrowHead") ?? "") ?? .standard
        )
    }

    var isFontSizeMode: Bool {
        currentTool == .text || isEditingText
    }

    /// The toolbar slider edits the font size while text is in play, and the tool's width otherwise.
    var sliderValue: CGFloat {
        isFontSizeMode ? textFontSize : lineWidth
    }

    func setSliderValue(_ value: CGFloat) {
        if isFontSizeMode {
            textFontSize = value
            persistWidth(value, for: .text)
        } else {
            lineWidth = value
            persistWidth(value, for: currentTool)
            updateSelectedStyle("lineWidth")
        }
    }

    var textFillColor: AnnotationColor? {
        textFillEnabled ? .black : nil
    }

    var textOutlineColor: AnnotationColor? {
        textOutlineEnabled ? .white : nil
    }

    var textGlyphStrokeColor: AnnotationColor? {
        textStrokeEnabled ? .white : nil
    }

    var toolbarDensity: CaptureChromeDensity {
        CaptureChromeLayout.annotationDensity(for: availableWidth)
    }

    var usesCompactToolbar: Bool {
        toolbarDensity != .regular
    }

    var usesMiniToolbar: Bool {
        toolbarDensity == .mini
    }

    func replaceSourceImage(_ image: CGImage, displayScale: CGFloat, objectOffset: CGSize = .zero) {
        sourceImage = image
        self.displayScale = displayScale
        document.updateImageSizePreservingObjects(
            size: CGSize(width: image.width, height: image.height),
            objectOffset: objectOffset
        )
        refreshTrigger += 1
    }

    func switchTool(_ newTool: AnnotationTool) {
        document.clearSelection()
        if currentTool != .text {
            persistWidth(lineWidth, for: currentTool)
        }
        currentTool = newTool
        lineWidth = Self.storedWidth(for: newTool)
        UserDefaults.standard.set(newTool.rawValue, forKey: "annotationLastTool")
        onRequestCanvasFocus?()
    }

    func toggleOverflow() {
        guard usesCompactToolbar else { return }
        showsOverflow.toggle()
        onRequestToolbarLayout?()
    }

    /// `property` groups repeated changes (slider drags) into one undo step (audit A9).
    /// No default: each control names its own property, otherwise colour, fill and
    /// pattern changes on one object merged into a single undo step (audit, 21.11.).
    func updateSelectedStyle(_ property: String) {
        if let obj = document.selectedObject {
            document.beginStyleChange(for: obj.id, property: property)
            if let pixelate = obj as? PixelateObject {
                // Never weaken a secure redaction; the slider is the block size only with the
                // pixelate tool active (audit A1, same as the editor).
                pixelate.restyle(
                    blockSize: currentTool == .pixelate ? lineWidth : pixelate.blockSize,
                    mode: redactionMode
                )
                pixelate.style = currentStyle
            } else if let counter = obj as? CounterObject {
                counter.radius = lineWidth
                counter.style = AnnotationKit.StrokeStyle(
                    color: currentColor,
                    lineWidth: lineWidth,
                    filled: filled
                )
            } else if let text = obj as? TextObject {
                text.fillColor = textFillColor
                text.outlineColor = textOutlineColor
                text.glyphStrokeColor = textGlyphStrokeColor
                text.style = currentStyle
            } else {
                obj.style = currentStyle
            }
            refreshTrigger += 1
        }
    }

    private func renderedOutputImage() -> CGImage? {
        return AnnotationRenderer.render(sourceImage: sourceImage, objects: document.objects)
    }

    func renderImage(afterCommit completion: @escaping (CGImage?) -> Void) {
        commitEditingTrigger += 1
        DispatchQueue.main.async { [weak self] in
            completion(self?.renderedOutputImage())
        }
    }

    func markChanged() {
        refreshTrigger += 1
    }

    func persistWidth(_ width: CGFloat, for tool: AnnotationTool) {
        switch tool {
        case .pixelate:
            UserDefaults.standard.set(Double(width), forKey: "annotationBlockSize")
        case .counter:
            UserDefaults.standard.set(Double(width), forKey: "annotationCounterSize")
        case .highlighter:
            UserDefaults.standard.set(Double(width), forKey: "annotationHighlighterWidth")
        case .text:
            UserDefaults.standard.set(Double(width), forKey: "annotationTextFontSize")
        default:
            savedLineWidth = Double(width)
        }
    }

    private static func storedTool() -> AnnotationTool {
        if let raw = UserDefaults.standard.string(forKey: "annotationLastTool"),
           let tool = AnnotationTool(rawValue: raw) {
            return tool
        }
        return .arrow
    }

    private static func storedColor() -> AnnotationColor {
        if let raw = UserDefaults.standard.string(forKey: "annotationLastColor"),
           let color = AnnotationColor(rawValue: raw) {
            return color
        }
        return .red
    }

    private static func storedStrokePattern() -> StrokePattern {
        if let raw = UserDefaults.standard.string(forKey: "annotationStrokePattern"),
           let pattern = StrokePattern(rawValue: raw) {
            return pattern
        }
        return .solid
    }

    private static func storedRedactionMode() -> RedactionMode {
        // Neue Installation (kein gespeicherter Wert): schwarzer Balken.
        guard let value = UserDefaults.standard.object(forKey: "annotationRedactionMode") as? Int else { return .solid }
        return RedactionMode(rawValue: value) ?? .solid
    }

    private static func storedTextStrokeEnabled() -> Bool {
        UserDefaults.standard.object(forKey: "annotationTextStrokeEnabled") as? Bool ?? true
    }

    private static func storedTextFontSize() -> CGFloat {
        CGFloat(UserDefaults.standard.object(forKey: "annotationTextFontSize") as? Double ?? 48)
    }

    private static func storedWidth(for tool: AnnotationTool) -> CGFloat {
        switch tool {
        case .pixelate:
            return CGFloat(UserDefaults.standard.object(forKey: "annotationBlockSize") as? Double ?? 12)
        case .counter:
            return CGFloat(UserDefaults.standard.object(forKey: "annotationCounterSize") as? Double ?? 20)
        case .highlighter:
            return CGFloat(UserDefaults.standard.object(forKey: "annotationHighlighterWidth") as? Double ?? 20)
        case .text:
            return storedTextFontSize()
        default:
            return CGFloat(UserDefaults.standard.object(forKey: "annotationShapeWidth") as? Double ?? 3)
        }
    }
}

private struct AllInOneAnnotationCanvasView: View {
    @ObservedObject var session: AllInOneAnnotationSession

    var body: some View {
        AnnotationCanvasView(
            document: session.document,
            sourceImage: session.sourceImage,
            currentTool: session.currentTool,
            currentStyle: session.currentStyle,
            redactionMode: session.redactionMode,
            textFontSize: session.textFontSize,
            textFillColor: session.textFillColor,
            textOutlineColor: session.textOutlineColor,
            textGlyphStrokeColor: session.textGlyphStrokeColor,
            zoomScale: session.displayScale,
            refreshTrigger: session.refreshTrigger,
            textRegions: session.textRegions,
            commitEditingTrigger: session.commitEditingTrigger,
            onDocumentChanged: { session.markChanged() },
            onSwitchToSelect: {
                session.document.clearSelection()
                session.switchTool(.select)
            },
            onTextEditingStarted: { fontSize, hasFill, hasOutline, hasStroke in
                session.isEditingText = true
                session.textFillEnabled = hasFill
                session.textOutlineEnabled = hasOutline
                session.textStrokeEnabled = hasStroke
                if session.textFontSize != fontSize {
                    session.textFontSize = fontSize
                }
            },
            onTextEditingEnded: {
                session.isEditingText = false
                session.persistWidth(session.textFontSize, for: .text)
            }
        )
        .background(Color.clear)
    }
}

private struct AllInOneAnnotationToolbarView: View {
    private enum TextEffectAction: Hashable {
        case fill, outline, trace
    }

    @ObservedObject var session: AllInOneAnnotationSession
    @State private var showsTextStylePopover = false

    private var isFontSizeMode: Bool {
        session.isFontSizeMode
    }

    private var hasActiveTextEffect: Bool {
        session.textFillEnabled || session.textOutlineEnabled || session.textStrokeEnabled
    }

    var body: some View {
        Group {
            if session.usesMiniToolbar && !session.showsOverflow {
                miniToolbar
            } else {
                adaptiveToolbar
            }
        }
        .annotationToolShortcuts(
            currentTool: Binding(
                get: { session.currentTool },
                set: { session.switchTool($0) }
            ),
            isEnabled: !session.isEditingText
        )
        .onChange(of: isFontSizeMode) { _, isTextMode in
            if !isTextMode {
                showsTextStylePopover = false
            }
        }
    }

    // Glas-Umbau Phase 3: dieselbe Sprache wie die Editor-Leiste – schwebende Glas-Kapseln je
    // Gruppe, Werkzeugknöpfe 30 × 26 pt, eine Akzent-Pille gleitet zum aktiven Werkzeug.
    private var adaptiveToolbar: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    toolRow(primaryTools).captureGlassPill(readable: true)

                    HStack(spacing: 8) {
                        if !session.usesCompactToolbar {
                            colorControls
                            divider
                            primaryControls
                        } else {
                            compactStatus
                        }

                        if isFontSizeMode && session.usesCompactToolbar {
                            textStyleButton
                        }

                        if session.usesCompactToolbar {
                            iconButton(
                                systemName: session.showsOverflow ? "chevron.up" : "ellipsis",
                                help: session.showsOverflow ? "Hide tools" : "More tools",
                                isActive: session.showsOverflow,
                                action: { session.toggleOverflow() }
                            )
                        }
                    }
                    .captureGlassPill(readable: true)

                    if !session.usesCompactToolbar {
                        undoRedoControls.captureGlassPill(readable: true)
                    }
                }

                if session.usesCompactToolbar && session.showsOverflow {
                    HStack(spacing: 10) {
                        toolRow(overflowTools).captureGlassPill(readable: true)
                        HStack(spacing: 8) {
                            colorControls
                            divider
                            primaryControls
                        }
                        .captureGlassPill(readable: true)
                        undoRedoControls.captureGlassPill(readable: true)
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: -10)).combined(with: .scale(scale: 0.96, anchor: .top)),
                        removal: .opacity.combined(with: .offset(y: -6))))
                }
            }
            .fixedSize()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .familyAnimation(FamilyTheme.Motion.select, value: session.showsOverflow)
        .familyAnimation(FamilyTheme.Motion.select, value: session.currentTool)
    }

    private var miniToolbar: some View {
        HStack(spacing: 8) {
            currentToolGlyph
                .foregroundStyle(.white)
                .frame(width: CaptureGlass.toolButton.width, height: CaptureGlass.toolButton.height)
                .background(CaptureAccentPill())

            Circle()
                .fill(Color(cgColor: session.currentColor.cgColor))
                .frame(width: 17, height: 17)
                .overlay(Circle().stroke(Color.black.opacity(0.24), lineWidth: 0.5))
                .overlay(Circle().stroke(FamilyTheme.accent.opacity(0.55), lineWidth: 1.5).padding(-2))

            Text(compactValueLabel)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(FamilyTheme.textPrimary)
                .contentTransition(.numericText())
                .frame(minWidth: 34)

            if isFontSizeMode {
                textStyleButton
            }

            iconButton(
                systemName: "ellipsis",
                help: "More tools",
                action: { session.toggleOverflow() }
            )
        }
        .captureGlassPill(readable: true)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var colorControls: some View {
        AnnotationColorControls(
            currentColor: Binding(
                get: { session.currentColor },
                set: {
                    session.currentColor = $0
                    UserDefaults.standard.set($0.rawValue, forKey: "annotationLastColor")
                    session.updateSelectedStyle("color")
                }
            ),
            swatchSize: 17
        )
    }

    private var primaryTools: [AnnotationTool] {
        session.usesCompactToolbar
            ? [.select, .arrow, .line, .rectangle, .text, .freehand]
            : AnnotationTool.allCases
    }

    private var overflowTools: [AnnotationTool] {
        [.ellipse, .pixelate, .counter, .highlighter, .spotlight]
    }

    private var compactStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(cgColor: session.currentColor.cgColor))
                .frame(width: 17, height: 17)
                .overlay(Circle().stroke(Color.black.opacity(0.24), lineWidth: 0.5))
                .overlay(Circle().stroke(FamilyTheme.accent.opacity(0.55), lineWidth: 1.5).padding(-2))

            Text(compactValueLabel)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(FamilyTheme.textPrimary)
                .contentTransition(.numericText())
                .frame(minWidth: 36)
        }
        .padding(.leading, 4)
    }

    private var primaryControls: some View {
        HStack(spacing: 7) {
            if !(session.currentTool == .pixelate && (session.redactionMode == .solid || session.redactionMode == .erase)) {
                Slider(value: Binding(
                    get: { session.sliderValue },
                    set: { session.setSliderValue($0) }
                ), in: sliderRange, step: sliderStep)
                .frame(width: 92)
                .help(sliderHelp)
            }

            if session.currentTool == .pixelate {
                redactionModeControl
            }

            if session.currentTool == .arrow || session.currentTool == .line {
                strokePatternControl
            }

            if isFontSizeMode
                && CaptureChromeLayout.showsInlineTextEffects(for: session.toolbarDensity) {
                textEffectsInlineControls
            }

            if session.currentTool != .counter
                && session.currentTool != .arrow
                && session.currentTool != .line
                && session.currentTool != .highlighter
                && session.currentTool != .pixelate
                && !isFontSizeMode {
                iconButton(
                    systemName: session.filled ? "square.fill" : "square",
                    help: "Fill Shape",
                    isActive: session.filled,
                    action: {
                        session.filled.toggle()
                        UserDefaults.standard.set(session.filled, forKey: "annotationFilled")
                        session.updateSelectedStyle("filled")
                    }
                )
            }
        }
    }

    private var textEffectsInlineControls: some View {
        HStack(spacing: 4) {
            textEffectIconButton(
                .fill,
                systemName: "square.fill",
                label: String(localized: "Fill"),
                help: "Text Fill",
                isActive: session.textFillEnabled,
                defaultsKey: "annotationTextFillEnabled"
            ) {
                session.textFillEnabled.toggle()
                return session.textFillEnabled
            }
            textEffectIconButton(
                .outline,
                systemName: "square",
                label: String(localized: "Box"),
                help: "Text Box Outline",
                isActive: session.textOutlineEnabled,
                defaultsKey: "annotationTextOutlineEnabled"
            ) {
                session.textOutlineEnabled.toggle()
                return session.textOutlineEnabled
            }
            textEffectGlyphButton(
                .trace,
                glyph: "Aa",
                label: String(localized: "Trace"),
                help: "Text Trace",
                isActive: session.textStrokeEnabled,
                defaultsKey: "annotationTextStrokeEnabled"
            ) {
                session.textStrokeEnabled.toggle()
                return session.textStrokeEnabled
            }
        }
    }

    private var textStyleButton: some View {
        Button {
            showsTextStylePopover.toggle()
        } label: {
            Image(systemName: "textformat")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(hasActiveTextEffect ? FamilyTheme.accent : FamilyTheme.textPrimary.opacity(0.85))
                .frame(width: 32, height: CaptureGlass.toolButton.height)
                .background(Capsule().fill(buttonBackground(isActive: hasActiveTextEffect, isEnabled: true)))
                .captureHoverLift()
        }
        .buttonStyle(.plain)
        .help("Text Style")
        .accessibilityLabel(Text("Text Style"))
        .accessibilityValue(Text(hasActiveTextEffect ? "On" : "Off"))
        .popover(isPresented: $showsTextStylePopover, arrowEdge: .top) {
            textStylePopover
        }
    }

    private var textStylePopover: some View {
        HStack(spacing: 6) {
            textStylePopoverButton(
                systemName: "rectangle.fill",
                label: "Background",
                isActive: session.textFillEnabled,
                defaultsKey: "annotationTextFillEnabled"
            ) {
                session.textFillEnabled.toggle()
                return session.textFillEnabled
            }
            textStylePopoverButton(
                systemName: "rectangle",
                label: "Box",
                isActive: session.textOutlineEnabled,
                defaultsKey: "annotationTextOutlineEnabled"
            ) {
                session.textOutlineEnabled.toggle()
                return session.textOutlineEnabled
            }
            textStylePopoverButton(
                systemName: "textformat",
                label: "Stroke",
                isActive: session.textStrokeEnabled,
                defaultsKey: "annotationTextStrokeEnabled"
            ) {
                session.textStrokeEnabled.toggle()
                return session.textStrokeEnabled
            }
        }
        .padding(10)
    }

    private func textStylePopoverButton(
        systemName: String,
        label: LocalizedStringKey,
        isActive: Bool,
        defaultsKey: String,
        toggle: @escaping () -> Bool
    ) -> some View {
        Button {
            let newValue = toggle()
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
            session.updateSelectedStyle(defaultsKey)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .semibold))

                Text(label)
                    .font(FamilyTheme.font(10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isActive ? Color.white : FamilyTheme.textPrimary)
            .frame(width: 72, height: 48)
            .background {
                if isActive {
                    CaptureAccentPill(shape: RoundedRectangle(cornerRadius: 12, style: .continuous), glow: false)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(FamilyTheme.textPrimary.opacity(0.06))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityValue(Text(isActive ? "On" : "Off"))
    }

    private func textEffectIconButton(
        _ kind: TextEffectAction,
        systemName: String,
        label: String,
        help: LocalizedStringKey,
        isActive: Bool,
        defaultsKey: String,
        toggle: @escaping () -> Bool
    ) -> some View {
        Button {
            let newValue = toggle()
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
            session.updateSelectedStyle(defaultsKey)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isActive ? FamilyTheme.accent : FamilyTheme.textPrimary.opacity(0.85))
                .frame(width: CaptureGlass.toolButton.width, height: CaptureGlass.toolButton.height)
                .background(Capsule().fill(buttonBackground(isActive: isActive, isEnabled: true)))
                .captureHoverLift(isEnabled: !isActive)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(isActive ? "On" : "Off"))
    }

    private func textEffectGlyphButton(
        _ kind: TextEffectAction,
        glyph: String,
        label: String,
        help: LocalizedStringKey,
        isActive: Bool,
        defaultsKey: String,
        toggle: @escaping () -> Bool
    ) -> some View {
        Button {
            let newValue = toggle()
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
            session.updateSelectedStyle(defaultsKey)
        } label: {
            Text(verbatim: glyph)
                .font(FamilyTheme.font(12, weight: .semibold))
                .foregroundStyle(isActive ? FamilyTheme.accent : FamilyTheme.textPrimary.opacity(0.85))
                .frame(width: CaptureGlass.toolButton.width, height: CaptureGlass.toolButton.height)
                .background(Capsule().fill(buttonBackground(isActive: isActive, isEnabled: true)))
                .captureHoverLift(isEnabled: !isActive)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(isActive ? "On" : "Off"))
    }

    private var undoRedoControls: some View {
        HStack(spacing: 4) {
            iconButton(
                systemName: "arrow.uturn.backward",
                help: "Undo",
                isEnabled: session.document.canUndo,
                action: {
                    session.document.undo()
                    session.markChanged()
                }
            )

            iconButton(
                systemName: "arrow.uturn.forward",
                help: "Redo",
                isEnabled: session.document.canRedo,
                action: {
                    session.document.redo()
                    session.markChanged()
                }
            )
        }
    }

    private func toolRow(_ tools: [AnnotationTool]) -> some View {
        HStack(spacing: CaptureGlass.toolSpacing) {
            ForEach(tools, id: \.self) { tool in
                toolButton(tool)
            }
        }
        // Eine Akzent-Pille hinter der Reihe, die beim Werkzeugwechsel hinübergleitet (wie im Editor).
        .background(alignment: .leading) {
            if let index = tools.firstIndex(of: session.currentTool) {
                CaptureAccentPill()
                    .frame(width: CaptureGlass.toolButton.width, height: CaptureGlass.toolButton.height)
                    .offset(x: CGFloat(index) * (CaptureGlass.toolButton.width + CaptureGlass.toolSpacing))
                    .familyAnimation(FamilyTheme.Motion.select, value: index)
            }
        }
    }

    private var currentToolGlyph: some View {
        Group {
            if session.currentTool == .text {
                Text(verbatim: "Aa")
                    .font(FamilyTheme.font(13, weight: .semibold))
            } else {
                Image(systemName: iconName(for: session.currentTool))
                    .font(.system(size: 14, weight: .medium))
            }
        }
    }

    private var compactValueLabel: String {
        if session.currentTool == .pixelate {
            return "\(Int(session.lineWidth))px"
        }
        if isFontSizeMode {
            return "\(Int(session.textFontSize))pt"
        }
        return "\(Int(session.lineWidth))px"
    }

    private var divider: some View {
        Capsule()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 16)
    }

    private var sliderRange: ClosedRange<CGFloat> {
        if isFontSizeMode { return 12...120 }
        switch session.currentTool {
        case .pixelate: return 4...48
        case .counter: return 12...40
        case .highlighter: return 10...100
        default: return 1...40
        }
    }

    private var sliderStep: CGFloat {
        switch session.currentTool {
        case .pixelate, .highlighter: return 2
        default: return 1
        }
    }

    private var sliderHelp: String {
        if isFontSizeMode { return "\(String(localized: "Font Size")): \(Int(session.textFontSize))" }
        switch session.currentTool {
        case .pixelate: return "\(String(localized: "Block Size")): \(Int(session.lineWidth))"
        case .counter: return "\(String(localized: "Counter Size")): \(Int(session.lineWidth))"
        case .highlighter: return "\(String(localized: "Highlighter Width")): \(Int(session.lineWidth))"
        default: return "\(String(localized: "Line Width")): \(Int(session.lineWidth))"
        }
    }

    private var redactionModeControl: some View {
        HStack(spacing: 2) {
            ForEach(RedactionMode.allCases, id: \.self) { mode in
                Button {
                    session.redactionMode = mode
                    UserDefaults.standard.set(mode.rawValue, forKey: "annotationRedactionMode")
                    session.updateSelectedStyle("redactionMode")
                } label: {
                    Text(mode.localizedLabel)
                        .font(FamilyTheme.font(11, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(session.redactionMode == mode ? Color.white : FamilyTheme.textPrimary)
                        .frame(width: 48, height: 22)
                        .background { optionBackground(isActive: session.redactionMode == mode) }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(mode == .solid || mode == .erase ? mode.localizedLabel : "\(mode.localizedLabel) – \(redactionConfidentialHint)")
                .accessibilityLabel(mode.localizedLabel)
                .accessibilityAddTraits(session.redactionMode == mode ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(optionGroupBackground))
        .familyAnimation(FamilyTheme.Motion.select, value: session.redactionMode)
        .help("Redaction Mode")
    }

    private var redactionConfidentialHint: String {
        String(localized: "Not for confidential data – use the black bar.")
    }

    private var strokePatternControl: some View {
        HStack(spacing: 2) {
            ForEach(StrokePattern.allCases, id: \.self) { pattern in
                Button {
                    session.strokePattern = pattern
                    UserDefaults.standard.set(pattern.rawValue, forKey: "annotationStrokePattern")
                    session.updateSelectedStyle("pattern")
                } label: {
                    StrokePatternGlyph(pattern: pattern)
                        .foregroundStyle(session.strokePattern == pattern ? Color.white : FamilyTheme.textPrimary)
                        .frame(width: 30, height: 22)
                        .background { optionBackground(isActive: session.strokePattern == pattern) }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(Text(pattern.rawValue.capitalized))
                .accessibilityAddTraits(session.strokePattern == pattern ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(optionGroupBackground))
        .familyAnimation(FamilyTheme.Motion.select, value: session.strokePattern)
        .help("Stroke Pattern")
    }

    private var optionGroupBackground: Color {
        FamilyTheme.textPrimary.opacity(0.07)
    }

    @ViewBuilder
    private func optionBackground(isActive: Bool) -> some View {
        if isActive {
            CaptureAccentPill(glow: false)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func toolButton(_ tool: AnnotationTool) -> some View {
        let isActive = session.currentTool == tool
        Button(action: { session.switchTool(tool) }) {
            Group {
                if tool == .text {
                    Text(verbatim: "Aa")
                        .font(FamilyTheme.font(13, weight: .semibold))
                } else {
                    Image(systemName: iconName(for: tool))
                        .font(.system(size: 14, weight: .medium))
                }
            }
            // Auf der Akzent-Pille weiß (accentFill ist für Weiß gerechnet).
            .foregroundStyle(isActive ? Color.white : FamilyTheme.textPrimary.opacity(0.85))
            .frame(width: CaptureGlass.toolButton.width, height: CaptureGlass.toolButton.height)
            .captureHoverLift(isEnabled: !isActive)
        }
        .buttonStyle(.plain)
        .help(tool.localizedShortcutHelpTitle)
        .accessibilityLabel(Text(toolHoverLabel(for: tool)))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func iconButton(
        systemName: String,
        help: LocalizedStringKey,
        isActive: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isActive ? FamilyTheme.accent : FamilyTheme.textPrimary.opacity(0.85))
                .frame(width: 32, height: CaptureGlass.toolButton.height)
                .background(Capsule().fill(buttonBackground(isActive: isActive, isEnabled: isEnabled)))
                .captureHoverLift(isEnabled: isEnabled && !isActive)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .help(help)
    }

    /// Zustand „an“ wie im Editor: leiser Akzentgrund, Symbol im Akzent.
    private func buttonBackground(isActive: Bool, isEnabled: Bool) -> Color {
        isActive && isEnabled ? FamilyTheme.accent.opacity(0.18) : Color.clear
    }

    private func iconName(for tool: AnnotationTool) -> String {
        switch tool {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .freehand: return "pencil.tip"
        case .pixelate: return "eye.slash.fill"
        case .counter: return "number.circle.fill"
        case .highlighter: return "highlighter"
        case .spotlight: return "flashlight.on.fill"
        }
    }

    private func toolHoverLabel(for tool: AnnotationTool) -> String {
        switch tool {
        case .select: return String(localized: "Select")
        case .arrow: return String(localized: "Arrow")
        case .line: return String(localized: "Line")
        case .rectangle: return String(localized: "Rect")
        case .ellipse: return String(localized: "Oval")
        case .text: return String(localized: "Text")
        case .freehand: return String(localized: "Draw")
        case .pixelate: return String(localized: "Pixel")
        case .counter: return String(localized: "Count")
        case .highlighter: return String(localized: "Mark")
        case .spotlight: return String(localized: "Spotlight")
        }
    }
}

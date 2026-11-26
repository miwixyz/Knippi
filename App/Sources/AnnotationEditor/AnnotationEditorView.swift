// App/Sources/AnnotationEditor/AnnotationEditorView.swift
import AppKit
import SwiftUI
import AnnotationKit
import CaptureKit
import OCRKit
import SharedKit

struct AnnotationEditorView: View {
    let initialSourceImage: CGImage
    let document: AnnotationDocument
    let sourceAppName: String?
    let sourceWindowTitle: String?
    let captureDate: Date
    let screenshotOutput: ScreenshotOutputOptions
    let screenshotFilenameTemplate: String
    /// Starts "Find Sensitive Data" as soon as the canvas appears (Quick Access action).
    let findsSensitiveDataOnOpen: Bool
    let onSave: (CGImage) -> Void
    let onSaveAs: (CGImage) -> Void
    let onCopy: (CGImage) -> Void
    let onPin: (CGImage) -> Void
    let onDragStarted: () -> Void
    let onDragEnded: () -> Void
    let onCancel: () -> Void

    /// The working image shown in the canvas. Starts equal to
    /// `initialSourceImage` and is swapped if a crop commit includes a
    /// rotate or flip. Annotations live in this image's coordinate space.
    @State private var sourceImage: CGImage

    init(
        sourceImage: CGImage,
        document: AnnotationDocument,
        sourceAppName: String?,
        sourceWindowTitle: String?,
        captureDate: Date,
        screenshotOutput: ScreenshotOutputOptions,
        screenshotFilenameTemplate: String,
        findsSensitiveDataOnOpen: Bool = false,
        onSave: @escaping (CGImage) -> Void,
        onSaveAs: @escaping (CGImage) -> Void,
        onCopy: @escaping (CGImage) -> Void,
        onPin: @escaping (CGImage) -> Void,
        onDragStarted: @escaping () -> Void,
        onDragEnded: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialSourceImage = sourceImage
        self.document = document
        self.sourceAppName = sourceAppName
        self.sourceWindowTitle = sourceWindowTitle
        self.captureDate = captureDate
        self.screenshotOutput = screenshotOutput
        self.screenshotFilenameTemplate = screenshotFilenameTemplate
        self.findsSensitiveDataOnOpen = findsSensitiveDataOnOpen
        self.onSave = onSave
        self.onSaveAs = onSaveAs
        self.onCopy = onCopy
        self.onPin = onPin
        self.onDragStarted = onDragStarted
        self.onDragEnded = onDragEnded
        self.onCancel = onCancel
        self._sourceImage = State(initialValue: sourceImage)
    }

    // MARK: - Persisted tool preferences (issue #75)
    // Tool / color / filled / per-tool sizes survive across editor sessions
    // via UserDefaults. `lineWidth` itself is session-local because its
    // meaning changes with the active tool; it is synced on every change into
    // the correct per-tool store below.
    @AppStorage("annotationLastTool") private var currentTool: AnnotationTool = .arrow
    @AppStorage("annotationLastColor") private var currentColor: AnnotationColor = .red
    @AppStorage("annotationFilled") private var filled: Bool = false
    @AppStorage("annotationShapeWidth") private var savedLineWidth: Double = 3
    @AppStorage("annotationBlockSize") private var savedBlockSize: Double = 12
    @AppStorage("annotationCounterSize") private var savedCounterSize: Double = 20
    @AppStorage("annotationHighlighterWidth") private var savedHighlighterWidth: Double = 20
    @AppStorage("annotationRedactionMode") private var redactionMode: RedactionMode = .solid
    @AppStorage("annotationStrokePattern") private var savedStrokePattern: StrokePattern = .solid
    @AppStorage("annotationArrowHead") private var arrowHead: ArrowHeadStyle = .standard
    @AppStorage("annotationTextFillEnabled") private var textFillEnabled: Bool = false
    @AppStorage("annotationTextOutlineEnabled") private var textOutlineEnabled: Bool = false
    @AppStorage("annotationTextStrokeEnabled") private var textStrokeEnabled: Bool = true
    /// Preserved font size for the Text tool. Swapped in/out of `lineWidth`
    /// as the user toggles tools — same pattern as savedBlockSize etc.
    @AppStorage("annotationTextFontSize") private var savedTextFontSize: Double = 48
    @AppStorage("annotationStylePresets") private var presetsData = Data()
    /// Width to load when a preset switches tools, instead of that tool's last width.
    @State private var pendingPresetWidth: CGFloat?

    @State private var lineWidth: CGFloat = 3
    @State private var strokePattern: StrokePattern = .solid
    /// True while an inline text editor is active. Lets the toolbar show
    /// the font-size slider even when the tool is `.select` (happens when
    /// re-editing via double-click).
    @State private var isEditingText = false
    @State private var beautifySettings = BeautifySettings.saved()
    @State private var showBeautifyPanel = false
    /// Höhe der oberen Werkzeugzeile (ohne Zweitreihe) bzw. der ganzen schwebenden Kopfzone
    /// samt Hintergrund-Panel: daraus folgt, wie weit das Bild unter den Glas-Kapseln beginnt.
    @State private var toolbarRowHeight: CGFloat = 34
    @State private var chromeStackHeight: CGFloat = 0
    /// Size of the canvas area, so the zoom can be refitted when the picture or
    /// the space for it changes (background panel, format, margin).
    @State private var canvasAreaSize: CGSize = .zero
    /// True while the zoom shows the whole picture; zooming by hand turns it off.
    @State private var isZoomFitted = true
    @State private var beautifyBackgroundPreview: CGImage?
    @State private var beautifyBackgroundPreviewURL: URL?
    @State private var refreshTrigger = 0
    @State private var zoomScale: CGFloat = 1.0
    @State private var isCropMode = false
    @State private var outputSize: CGSize?
    @State private var commitEditingTrigger = 0
    @State private var dragFileStore = QuickAccessDragFileStore()
    @State private var shareFileStore = QuickAccessDragFileStore.forSharing()
    @State private var dragFileID = UUID()
    @State private var dragRenderCache: DragRenderCache?
    /// Cached text line bounding boxes for smart highlighter snapping.
    @State private var textRegions: [CGRect] = []
    @State private var sensitiveSuggestions = SensitiveSuggestionsModel()
    /// Leaving crop mode rebuilds the canvas and fires its onAppear again; the one-time
    /// work (sensitive-data scan, text recognition, slider init) must not repeat, or
    /// the scan doubles redactions and brings back dismissed suggestions (audit A15, 21.11.).
    @State private var didRunInitialAppear = false

    private struct DragRenderCache {
        let renderedImage: CGImage
        let previewImage: NSImage
        var fileURL: URL?
    }

    /// The image, grown to hold annotations drawn past its edges. A crop turns growing off.
    private var canvasRect: CGRect {
        let imageSize = CGSize(width: sourceImage.width, height: sourceImage.height)
        guard document.cropRect == nil else { return CGRect(origin: .zero, size: imageSize) }
        return AnnotationRenderer.canvasRect(imageSize: imageSize, objects: document.objects)
    }

    /// Visible image width after applying any committed crop. The canvas view
    /// is still rendered at full image size but clipped+offset to show only
    /// this region, so annotations stay in full-image coordinates while layout
    /// and Save output reflect the crop.
    private var effectiveImageWidth: CGFloat {
        document.cropRect?.width ?? canvasRect.width
    }

    private var effectiveImageHeight: CGFloat {
        document.cropRect?.height ?? canvasRect.height
    }

    private var cropOffsetX: CGFloat {
        -(document.cropRect?.minX ?? 0) * zoomScale
    }

    private var cropOffsetY: CGFloat {
        -(document.cropRect?.minY ?? 0) * zoomScale
    }

    private var beautifyCanvasSize: CGSize {
        beautifySettings.canvasSize(for: CGSize(width: effectiveImageWidth, height: effectiveImageHeight))
    }

    private var previewContentWidth: CGFloat {
        beautifySettings.isEnabled ? beautifyCanvasSize.width : effectiveImageWidth
    }

    private var previewContentHeight: CGFloat {
        beautifySettings.isEnabled ? beautifyCanvasSize.height : effectiveImageHeight
    }

    private var previewInsets: (horizontal: CGFloat, vertical: CGFloat) {
        guard beautifySettings.isEnabled else { return (0, 0) }
        let insets = beautifySettings.canvasInsets(for: CGSize(width: effectiveImageWidth, height: effectiveImageHeight))
        return (insets.horizontal * zoomScale, insets.vertical * zoomScale)
    }

    private var previewWidth: CGFloat {
        previewContentWidth * zoomScale
    }

    private var previewHeight: CGFloat {
        previewContentHeight * zoomScale
    }

    private var currentStyle: AnnotationKit.StrokeStyle {
        AnnotationKit.StrokeStyle(
            color: currentColor,
            lineWidth: lineWidth,
            opacity: currentTool == .highlighter ? 0.35 : 1.0,
            filled: filled,
            pattern: strokePattern,
            arrowHead: arrowHead
        )
    }

    /// Font size currently pushed to the canvas. When the slider is in
    /// font-size mode (text tool active OR mid-edit), the live slider value
    /// wins so dragging it updates the editor in real time. Otherwise we
    /// fall back to the preserved value from the last text session.
    private var effectiveTextFontSize: CGFloat {
        (currentTool == .text || isEditingText) ? lineWidth : CGFloat(savedTextFontSize)
    }

    private var textFillColor: AnnotationColor? {
        textFillEnabled ? .black : nil
    }

    private var textOutlineColor: AnnotationColor? {
        textOutlineEnabled ? .white : nil
    }

    private var textGlyphStrokeColor: AnnotationColor? {
        textStrokeEnabled ? .white : nil
    }

    /// Preserved width for the given tool. Bridges between the `Double`
    /// UserDefaults stores and the canvas's `CGFloat` slider value.
    private func savedWidth(for tool: AnnotationTool) -> CGFloat {
        switch tool {
        case .pixelate: return CGFloat(savedBlockSize)
        case .counter: return CGFloat(savedCounterSize)
        case .highlighter: return CGFloat(savedHighlighterWidth)
        case .text: return CGFloat(savedTextFontSize)
        default: return CGFloat(savedLineWidth)
        }
    }

    /// Persist the current slider value into the store that owns the given
    /// tool. Called on every slider change so a dragged-then-closed editor
    /// still saves the user's choice.
    private func persistWidth(_ width: CGFloat, for tool: AnnotationTool) {
        switch tool {
        // The select tool owns no width: its slider shows the selected object's
        // value (a text's font size, too), which must not become the shape width.
        case .select: return
        case .pixelate: savedBlockSize = Double(width)
        case .counter: savedCounterSize = Double(width)
        case .highlighter: savedHighlighterWidth = Double(width)
        case .text: savedTextFontSize = Double(width)
        default: savedLineWidth = Double(width)
        }
    }

    /// Live preview of the Beautify background. For solid, just a filled Rect.
    /// For liquid glass, a blurred & saturation-boosted copy of the screenshot
    /// scaled to fill the background area — mirrors what `BeautifyRenderer`
    /// produces on export. Blur radius is scaled by `zoomScale` so that the
    /// perceived amount of blur matches the fixed 120-image-pixel blur used
    /// by the renderer at any zoom level.
    @ViewBuilder
    private var beautifyBackground: some View {
        switch beautifySettings.backgroundStyle {
        case .solid:
            Rectangle()
                .fill(beautifySettings.backgroundColor)
        case .liquidGlass:
            Image(decorative: sourceImage, scale: 1.0)
                .resizable()
                .scaledToFill()
                .saturation(1.9)
                .blur(radius: max(8, 120 * zoomScale), opaque: true)
                .overlay(Color.white.opacity(0.03))
                .clipped()
        case .gradient(let gradient):
            if let tile = BeautifyGradients.image(gradient, width: 640, height: max(1, Int(640 * previewContentHeight / max(1, previewContentWidth)))) {
                Image(decorative: tile, scale: 1.0)
                    .resizable()
            }
        case .image:
            if let picture = beautifyBackgroundPreview {
                Image(decorative: picture, scale: 1.0)
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else {
                Rectangle()
                    .fill(beautifySettings.backgroundColor)
            }
        case .none:
            Color.clear
        }
    }

    /// Downsampled copy of the custom background picture for the live
    /// preview; reloaded only when the chosen file changes.
    private func reloadBeautifyBackgroundPreview() {
        guard case .image(let url) = beautifySettings.backgroundStyle else {
            beautifyBackgroundPreview = nil
            beautifyBackgroundPreviewURL = nil
            return
        }
        guard url != beautifyBackgroundPreviewURL else { return }
        beautifyBackgroundPreviewURL = url
        beautifyBackgroundPreview = BeautifyRenderer.loadImage(at: url, maxPixelSize: 1600)
        if beautifyBackgroundPreview == nil {
            Self.showBeautifyWarning(BeautifyRenderer.missingBackgroundImageWarning)
        }
    }

    var body: some View {
        Group {
            if isCropMode {
                cropEditor
            } else {
                editorContent
            }
        }
        .background(escapeKeyHandler)
        .background(saveAsKeyHandler)
        .onDisappear { invalidateDragCache() }
    }

    /// A zero-size button is the same key-equivalent mechanism the toolbar's
    /// Close button used to use, so Esc keeps working without focus. Unlike
    /// that button, this one never closes the editor — see
    /// `AnnotationEscapePolicy` for the full precedence.
    private var escapeKeyHandler: some View {
        Button(action: handleEscape) { EmptyView() }
            .buttonStyle(.plain)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
            .keyboardShortcut(.escape, modifiers: [])
    }

    private var saveAsKeyHandler: some View {
        Button(action: saveAs) { EmptyView() }
            .buttonStyle(.plain)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
            .keyboardShortcut("s", modifiers: [.command, .shift])
    }

    private func handleEscape() {
        // While text is being edited, Esc first commits it; the next Esc dismisses the
        // suggestions. Before, it threw the suggestions away mid-edit (audit A16, 21.11.).
        if sensitiveSuggestions.isShowing, !isEditingText {
            sensitiveSuggestions.cancel()
            return
        }
        switch AnnotationEscapePolicy.action(
            isEditingText: isEditingText,
            isCropMode: isCropMode,
            currentTool: currentTool,
            hasSelection: document.selectedObjectID != nil
        ) {
        case .commitTextEditing:
            commitEditingTrigger += 1
        case .exitCropMode:
            isCropMode = false
        case .switchToSelectTool:
            switchToSelectTool()
        case .clearSelection:
            document.clearSelection()
            refreshTrigger += 1
        case .none:
            break
        }
    }

    private var cropEditor: some View {
        CropEditorView(
            sourceImage: sourceImage,
            initialCropRect: document.cropRect,
            initialOutputSize: outputSize,
            canTransformImage: document.objects.isEmpty,
            onCancel: { isCropMode = false },
            onCommit: commitCrop
        )
    }

    /// Glas-Umbau Phase 2: Die Arbeitsfläche füllt das ganze Fenster (Titelleiste unsichtbar), darunter
    /// der lebende Hintergrund. Das Bild liegt als feste Karte darauf; Werkzeuge, Aktionen und Zoom
    /// schweben als Liquid-Glass-Kapseln darüber.
    private var editorContent: some View {
        ZStack(alignment: .top) {
            canvasArea
                .padding(.top, canvasTopInset)
                .padding(.bottom, Self.canvasBottomInset)
                .mask(canvasEdgeFade)

            VStack(spacing: 10) {
                toolbar
                if showBeautifyPanel {
                    BeautifyPanel(settings: beautifySettingsBinding)
                        .frame(maxWidth: 760)
                        .familyTintedGlass(in: RoundedRectangle(cornerRadius: FamilyTheme.Radius.tile, style: .continuous))
                        .padding(.horizontal, 16)
                        .transition(.opacity.combined(with: .offset(y: -10)))
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { chromeStackHeight = $0 }
            .familyAnimation(FamilyTheme.Motion.appear, value: showBeautifyPanel)

            zoomPill
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 12)
        }
        .background(EditorAmbience().ignoresSafeArea())
        .ignoresSafeArea()
        .annotationToolShortcuts(currentTool: $currentTool, isEnabled: !isEditingText)
    }

    /// Bild beginnt unter der oberen Kapselzeile (Zweitreihe für Text/Schwärzen schwebt über dem
    /// Bild), mit offenem Hintergrund-Panel unter dem ganzen Kopf.
    private var canvasTopInset: CGFloat {
        showBeautifyPanel ? chromeStackHeight + 8 : AnnotationToolbar.topPadding + toolbarRowHeight + 6
    }

    private static let canvasBottomInset: CGFloat = 52

    /// Weicher Auslauf oben und unten, damit ein vergrößertes Bild nicht hart an einer
    /// unsichtbaren Kante endet.
    private var canvasEdgeFade: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 14)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 14)
        }
    }

    private var toolbar: some View {
        AnnotationToolbar(
            currentTool: $currentTool,
            currentColor: $currentColor,
            lineWidth: $lineWidth,
            strokePattern: $strokePattern,
            arrowHead: $arrowHead,
            filled: $filled,
            textFillEnabled: $textFillEnabled,
            textOutlineEnabled: $textOutlineEnabled,
            textStrokeEnabled: $textStrokeEnabled,
            redactionMode: $redactionMode,
            showBeautifyPanel: $showBeautifyPanel,
            isEditingText: isEditingText,
            canUndo: document.canUndo,
            canRedo: document.canRedo,
            onUndo: { document.undo(); handleDocumentChanged() },
            onRedo: { document.redo(); handleDocumentChanged() },
            onSave: { save() },
            onCopy: { copy() },
            onPin: { pin() },
            onShare: { share(from: $0) },
            dragThumbnail: dragFallbackImage,
            onPrepareDrag: prepareDragFile,
            onDragFileURL: dragFileURL,
            onDragPreviewImage: dragPreviewImage,
            onDragStarted: onDragStarted,
            onDragEnded: onDragEnded,
            isDragDisabled: isEditingText || sensitiveSuggestions.isScanning,
            isExportBlocked: sensitiveSuggestions.isScanning,
            onCancel: onCancel,
            onCrop: startCrop,
            isFindingSensitiveData: sensitiveSuggestions.isScanning,
            onFindSensitiveData: findSensitiveData,
            presets: presets,
            onApplyPreset: applyPreset,
            onSavePreset: saveCurrentStyleAsPreset,
            onRemovePreset: removePreset,
            onMainRowHeight: { toolbarRowHeight = $0 }
        )
    }

    private var canvasArea: some View {
        GeometryReader { geo in
            ZoomableScrollContainer(
                zoomScale: $zoomScale,
                contentSize: CGSize(width: previewWidth, height: previewHeight)
            ) {
                previewCanvas
            }
            .overlay(alignment: .top) {
                if sensitiveSuggestions.isShowing {
                    SensitiveSuggestionsBar(model: sensitiveSuggestions, onPixelateAll: pixelateSensitiveData)
                        .padding(.top, FamilyTheme.Space.m)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: sensitiveSuggestions.isShowing)
            // A drag file rendered before the suggestions appeared would skip them.
            .onChange(of: sensitiveSuggestions.isShowing) { wasShowing, isShowing in
                if Self.suggestionsChangeInvalidatesDragCache(wasShowing: wasShowing, isShowing: isShowing) {
                    invalidateDragCache()
                }
            }
            .onAppear {
                handleCanvasAppear(size: geo.size)
                if beautifySettings.isEnabled { reloadBeautifyBackgroundPreview() }
            }
            .onChange(of: currentTool, handleToolChange)
            .onChange(of: currentColor) { _, _ in updateSelectedStyle("color") }
            .onChange(of: lineWidth, handleLineWidthChange)
            .onChange(of: strokePattern, handleStrokePatternChange)
            .onChange(of: arrowHead) { _, _ in updateSelectedStyle("arrowHead") }
            .onChange(of: filled) { _, _ in updateSelectedStyle("filled") }
            .onChange(of: textFillEnabled) { _, _ in updateSelectedStyle("textFill") }
            .onChange(of: textOutlineEnabled) { _, _ in updateSelectedStyle("textOutline") }
            .onChange(of: textStrokeEnabled) { _, _ in updateSelectedStyle("textStroke") }
            .onChange(of: redactionMode) { _, _ in updateSelectedStyle("redactionMode") }
            .onChange(of: geo.size, handleCanvasSizeChange)
            .onChange(of: CGSize(width: previewContentWidth, height: previewContentHeight)) { _, _ in
                handlePreviewContentSizeChange()
            }
            // Pinch, scroll or buttons: still showing the whole picture?
            .onChange(of: zoomScale) { _, newScale in
                guard canvasAreaSize.width > 0 else { return }
                isZoomFitted = abs(newScale - fitScale(for: canvasAreaSize)) < 0.001
            }
        }
    }

    private var previewCanvas: some View {
        ZStack {
            if beautifySettings.isEnabled {
                beautifyBackground
                    .frame(width: previewWidth, height: previewHeight)
            }

            annotationCanvas
        }
        .frame(
            width: beautifySettings.isEnabled ? previewWidth : effectiveImageWidth * zoomScale,
            height: beautifySettings.isEnabled ? previewHeight : effectiveImageHeight * zoomScale
        )
        // Same rounded outer corners as `BeautifyRenderer` on export, so the
        // preview shows what gets copied or saved (Michael, 21.11.).
        // Only with a visible background: without it nothing may be clipped
        // (selection handles can reach past the image edge).
        .modifier(OuterCornerClip(radius: previewOuterCornerRadius))
        // Mit Hintergrund ist die ganze Vorschau die Karte: weicher Familien-Schatten darunter.
        .shadow(color: Color(light: 0x1E2846, dark: 0x000000).opacity(previewOuterCornerRadius > 0 || beautifySettings.isEnabled ? 0.20 : 0),
                radius: 18, y: 8)
    }

    private struct OuterCornerClip: ViewModifier {
        let radius: CGFloat
        func body(content: Content) -> some View {
            if radius > 0 {
                content.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            } else {
                content
            }
        }
    }

    private var previewOuterCornerRadius: CGFloat {
        guard beautifySettings.isEnabled, beautifySettings.backgroundStyle != .none else { return 0 }
        return min(beautifySettings.outerCornerRadius * zoomScale, min(previewWidth, previewHeight) / 2)
    }

    private var annotationCanvas: some View {
        AnnotationCanvasView(
            document: document,
            sourceImage: sourceImage,
            currentTool: currentTool,
            currentStyle: currentStyle,
            redactionMode: redactionMode,
            textFontSize: effectiveTextFontSize,
            textFillColor: textFillColor,
            textOutlineColor: textOutlineColor,
            textGlyphStrokeColor: textGlyphStrokeColor,
            zoomScale: zoomScale,
            canvasOrigin: canvasRect.origin,
            showsBackgroundBehind: beautifySettings.isEnabled && beautifySettings.backgroundStyle != .none,
            refreshTrigger: refreshTrigger,
            textRegions: textRegions,
            commitEditingTrigger: commitEditingTrigger,
            onDocumentChanged: handleDocumentChanged,
            onSwitchToSelect: switchToSelectTool,
            onTextEditingStarted: handleTextEditingStarted,
            onTextEditingEnded: handleTextEditingEnded
        )
        .frame(width: canvasRect.width * zoomScale, height: canvasRect.height * zoomScale)
        .overlay(alignment: .topLeading) {
            if sensitiveSuggestions.isShowing {
                SensitiveSuggestionsOverlay(
                    model: sensitiveSuggestions,
                    zoomScale: zoomScale,
                    canvasOrigin: canvasRect.origin
                )
            }
        }
        .offset(x: cropOffsetX, y: cropOffsetY)
        .frame(
            width: effectiveImageWidth * zoomScale,
            height: effectiveImageHeight * zoomScale,
            alignment: .topLeading
        )
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: canvasCornerRadius, style: .continuous))
        .shadow(color: canvasShadowColor, radius: canvasShadowRadius, y: canvasShadowOffsetY)
        .padding(.horizontal, previewInsets.horizontal)
        .padding(.vertical, previewInsets.vertical)
    }

    /// Zoom als kleine Glas-Pille unten mittig (statt Statuszeile). Tastenkürzel bleiben:
    /// ⌘− / ⌘= / ⌘+ / ⌘0.
    private var zoomPill: some View {
        HStack(spacing: 2) {
            Button(action: zoomOut) {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 24)
                    .contentShape(Capsule())
            }
            .keyboardShortcut("-", modifiers: .command)
            .help(Text("Zoom Out"))
            .accessibilityLabel(Text("Zoom Out"))

            Text(verbatim: "\(Int((zoomScale * 100).rounded())) %")
                .font(FamilyTheme.font(11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(FamilyTheme.textPrimary)
                .frame(minWidth: 44)
                .contentTransition(.numericText())

            Button(action: zoomIn) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 24)
                    .contentShape(Capsule())
            }
            .keyboardShortcut("=", modifiers: .command)
            .help(Text("Zoom In"))
            .accessibilityLabel(Text("Zoom In"))
            // ⌘+ as well: on German keyboards "+" is its own key, and the menus
            // of other apps advertise ⌘+ for zooming in.
            .background {
                Button(action: zoomIn) { EmptyView() }
                    .keyboardShortcut("+", modifiers: .command)
                    .buttonStyle(.plain)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
            }

            Capsule().fill(FamilyTheme.textPrimary.opacity(0.14)).frame(width: 1, height: 14)
                .padding(.horizontal, 4)

            Button(action: refitToCurrentWindow) {
                Text("Fit")
                    .font(FamilyTheme.font(11, weight: .semibold))
                    .foregroundStyle(isZoomFitted ? FamilyTheme.accent : FamilyTheme.textPrimary)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .contentShape(Capsule())
            }
            .keyboardShortcut("0", modifiers: .command)
        }
        .buttonStyle(.plain)
        .foregroundStyle(FamilyTheme.textPrimary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .familyLiquidGlass(in: Capsule(), tint: FamilyTheme.glassLightTint)
        .familyAnimation(FamilyTheme.Motion.hover, value: zoomScale)
    }

    /// Ohne Hintergrund liegt das Bild als feste Karte auf der Arbeitsfläche: leicht gerundete
    /// Ecken (nur Ansicht, der Export bleibt eckig) und weicher Familien-Schatten.
    private static let plainCardRadius: CGFloat = 6

    private var canvasCornerRadius: CGFloat {
        beautifySettings.isEnabled ? beautifySettings.clampedCornerRadius * zoomScale : Self.plainCardRadius
    }

    private var canvasShadowColor: Color {
        if beautifySettings.isEnabled {
            return .black.opacity(beautifySettings.shadowEnabled ? 0.25 : 0)
        }
        return Color(light: 0x1E2846, dark: 0x000000).opacity(0.22)
    }

    private var canvasShadowRadius: CGFloat {
        beautifySettings.isEnabled ? beautifySettings.clampedShadowRadius * zoomScale : 18
    }

    private var canvasShadowOffsetY: CGFloat {
        if beautifySettings.isEnabled {
            return beautifySettings.shadowEnabled ? 6 * zoomScale : 0
        }
        return 8
    }

    private var beautifySettingsBinding: Binding<BeautifySettings> {
        Binding(
            get: { beautifySettings },
            set: { newValue in
                beautifySettings = newValue
                newValue.saveStyle()
                reloadBeautifyBackgroundPreview()
                invalidateDragCache()
            }
        )
    }

    private var dragFallbackImage: NSImage {
        NSImage(cgImage: sourceImage, size: NSSize(width: sourceImage.width, height: sourceImage.height))
    }

    private func commitCrop(newImage: CGImage?, newRect: CGRect?, newOutputSize: CGSize?) {
        if let newImage {
            sourceImage = newImage
            // One call, history dropped: undo must never pair the old crop with the
            // rotated image (audit A8, 21.11.).
            document.replaceImage(size: CGSize(width: newImage.width, height: newImage.height), cropRect: newRect)
            // Boxes from before the rotate/flip point at the wrong places (audit A15, 21.11.).
            textRegions = []
            recognizeTextRegions()
        } else {
            document.setCropRect(newRect)
        }
        outputSize = newOutputSize
        isCropMode = false
        invalidateDragCache()
    }

    private func startCrop() {
        let screen = NSApp.keyWindow?.screen
        let mayCrop = Self.beginCrop(
            document: document,
            suggestions: sensitiveSuggestions,
            onSuggestionsApplied: {
                handleDocumentChanged()
                SensitiveSuggestionsToast.showSuggestionsApplied(screen: screen)
            },
            onBlockedWhileScanning: { SensitiveSuggestionsToast.showStillScanning(screen: screen) }
        )
        if mayCrop { isCropMode = true }
    }

    /// Crop goes through the same gate as export: blocked while scanning,
    /// pending suggestions are pixelated first instead of being discarded.
    static func beginCrop(
        document: AnnotationDocument,
        suggestions: SensitiveSuggestionsModel,
        onSuggestionsApplied: () -> Void = {},
        onBlockedWhileScanning: () -> Void = {}
    ) -> Bool {
        switch suggestions.prepareForExport(document) {
        case .blockedWhileScanning:
            onBlockedWhileScanning()
            return false
        case .ready(let applied):
            if applied { onSuggestionsApplied() }
            return true
        }
    }

    /// Only suggestions appearing make a cached drag/share render stale. When
    /// they disappear because an export just applied them, the file written
    /// for that share/drag must survive.
    static func suggestionsChangeInvalidatesDragCache(wasShowing: Bool, isShowing: Bool) -> Bool {
        !wasShowing && isShowing
    }

    private func findSensitiveData() {
        commitEditingTrigger += 1
        sensitiveSuggestions.scan(image: sourceImage, screen: NSApp.keyWindow?.screen)
    }

    private func pixelateSensitiveData() {
        if sensitiveSuggestions.applyPendingRedactions(to: document) {
            handleDocumentChanged()
        }
    }

    private func handleCanvasAppear(size: CGSize) {
        canvasAreaSize = size
        fitToWindow(availableSize: size)
        guard !didRunInitialAppear else { return }
        didRunInitialAppear = true
        lineWidth = savedWidth(for: currentTool)
        strokePattern = savedStrokePattern
        if findsSensitiveDataOnOpen, !sensitiveSuggestions.isShowing {
            findSensitiveData()
        }
        recognizeTextRegions()
    }

    /// Text line boxes for highlighter snapping, in `sourceImage` coordinates.
    private func recognizeTextRegions() {
        let image = sourceImage
        Task {
            if let regions = try? await OCRProcessFallback.recognize(
                image: image, level: .fast, detectURLs: false
            ), image === sourceImage {
                textRegions = regions.map(\.boundingBox)
            }
        }
    }

    private func handleToolChange(oldTool: AnnotationTool, newTool: AnnotationTool) {
        document.clearSelection()
        persistWidth(lineWidth, for: oldTool)
        lineWidth = pendingPresetWidth ?? savedWidth(for: newTool)
        pendingPresetWidth = nil
    }

    private var presets: [AnnotationStylePreset] { AnnotationStylePreset.decodeList(presetsData) }

    private func saveCurrentStyleAsPreset() {
        let preset = AnnotationStylePreset(
            tool: currentTool.rawValue, color: currentColor, lineWidth: Double(lineWidth), filled: filled,
            pattern: strokePattern, arrowHead: arrowHead,
            textFill: textFillEnabled, textOutline: textOutlineEnabled, textStroke: textStrokeEnabled
        )
        let others = presets.filter { var p = $0; p.id = preset.id; return p != preset }
        presetsData = AnnotationStylePreset.encodeList(others + [preset])
    }

    private func applyPreset(_ preset: AnnotationStylePreset) {
        // Switching tools deselects anyway; doing it first keeps a selection from being half restyled.
        if preset.annotationTool != currentTool { document.clearSelection() }
        currentColor = preset.color
        filled = preset.filled
        strokePattern = preset.pattern
        arrowHead = preset.arrowHead
        textFillEnabled = preset.textFill
        textOutlineEnabled = preset.textOutline
        textStrokeEnabled = preset.textStroke
        if preset.annotationTool == currentTool {
            lineWidth = CGFloat(preset.lineWidth)
            // A preset restyles the selection as a whole, in one undo step; the
            // per-control onChange calls that follow then change nothing.
            updateSelectedStyle(SelectedObjectRestyle.allProperties)
        } else {
            pendingPresetWidth = CGFloat(preset.lineWidth)
            currentTool = preset.annotationTool
        }
    }

    private func removePreset(_ preset: AnnotationStylePreset) {
        presetsData = AnnotationStylePreset.encodeList(presets.filter { $0.id != preset.id })
    }

    private func handleLineWidthChange(oldValue: CGFloat, newValue: CGFloat) {
        updateSelectedStyle("lineWidth")
        // While a text is edited the slider is its font size; that is saved
        // once when editing ends, not as the tool's width.
        guard !isEditingText else { return }
        persistWidth(newValue, for: currentTool)
    }

    private func handleStrokePatternChange(oldValue: StrokePattern, newValue: StrokePattern) {
        savedStrokePattern = newValue
        updateSelectedStyle("pattern")
    }

    /// The canvas area changed (window resized, background panel opened or closed):
    /// keep showing the whole picture unless the user zoomed by hand.
    private func handleCanvasSizeChange(oldSize: CGSize, newSize: CGSize) {
        canvasAreaSize = newSize
        refitIfFitted()
    }

    /// The picture changed size (background on/off, format, margin, shadow): before,
    /// the zoom stayed put and the picture ran out of the window (Michael, 21.11.:
    /// "keine richtige Vorschau").
    private func handlePreviewContentSizeChange() {
        refitIfFitted()
    }

    private func refitIfFitted() {
        guard isZoomFitted, canvasAreaSize.width > 0, canvasAreaSize.height > 0 else { return }
        zoomScale = fitScale(for: canvasAreaSize)
    }

    private func handleDocumentChanged() {
        refreshTrigger += 1
        invalidateDragCache()
    }

    private func switchToSelectTool() {
        document.clearSelection()
        currentTool = .select
    }

    private func handleTextEditingStarted(
        fontSize: CGFloat,
        hasFill: Bool,
        hasOutline: Bool,
        hasStroke: Bool
    ) {
        isEditingText = true
        textFillEnabled = hasFill
        textOutlineEnabled = hasOutline
        textStrokeEnabled = hasStroke
        if lineWidth != fontSize {
            lineWidth = fontSize
        }
    }

    private func handleTextEditingEnded() {
        isEditingText = false
        savedTextFontSize = Double(lineWidth)
        invalidateDragCache()
    }

    /// "Einpassen": the measured canvas area, not the window minus a fixed toolbar
    /// height, which ignored the background panel.
    private func refitToCurrentWindow() {
        guard canvasAreaSize.width > 0, canvasAreaSize.height > 0 else { return }
        fitToWindow(availableSize: canvasAreaSize)
    }

    private func fitScale(for size: CGSize) -> CGFloat {
        guard previewContentWidth > 0, previewContentHeight > 0 else { return 1 }
        // Luft rund um die Bildkarte, damit ihr Schatten und der Hintergrund sichtbar bleiben.
        let viewportPadding: CGFloat = 56
        let scaleX = (size.width - viewportPadding) / previewContentWidth
        let scaleY = (size.height - viewportPadding) / previewContentHeight
        return min(scaleX, scaleY, 1.0) // Never zoom above 100%
    }

    private func fitToWindow(availableSize: CGSize) {
        zoomScale = fitScale(for: availableSize)
        isZoomFitted = true
    }

    private func zoomIn() {
        zoomScale = CanvasZoom.clampScale(zoomScale * 1.25, min: 0.1, max: 4.0)
        isZoomFitted = false
    }

    private func zoomOut() {
        zoomScale = CanvasZoom.clampScale(zoomScale / 1.25, min: 0.1, max: 4.0)
        isZoomFitted = false
    }

    /// Update the selected object's style when color/lineWidth/filled changes.
    /// `property` names the control, so a slider drag books one undo step (audit A9, 21.11.).
    private func updateSelectedStyle(_ property: String) {
        if let obj = document.selectedObject {
            let before = AnnotationStyleState(of: obj)
            let bookedStep = document.beginStyleChange(for: obj.id, property: property)
            defer {
                // A preset sets up to 8 controls; `applyPreset` applies them all at once, the
                // onChange calls change nothing. Dropping those empty steps makes a preset one undo
                // step, and a no-op restyle (secure pixelation, text editing start) none
                // (audit undo granularity, 21.11.).
                if bookedStep, AnnotationStyleState(of: obj) == before {
                    document.discardUnchangedStep()
                }
            }
            SelectedObjectRestyle.apply(
                property,
                to: obj,
                controls: currentStyle,
                currentTool: currentTool,
                redactionMode: redactionMode,
                textFill: textFillColor,
                textOutline: textOutlineColor,
                textStroke: textGlyphStrokeColor
            )
            refreshTrigger += 1
            invalidateDragCache()
        }
    }

    /// Every export (save, save as, copy, Return, pin, drag) renders through here.
    private func renderedOutputImage() -> CGImage? {
        Self.renderForExport(
            sourceImage: sourceImage,
            document: document,
            suggestions: sensitiveSuggestions,
            beautifySettings: beautifySettings,
            outputSize: outputSize,
            onSuggestionsApplied: {
                handleDocumentChanged()
                SensitiveSuggestionsToast.showSuggestionsApplied(screen: NSApp.keyWindow?.screen)
            },
            onBlockedWhileScanning: {
                SensitiveSuggestionsToast.showStillScanning(screen: NSApp.keyWindow?.screen)
            },
            onWarning: Self.showBeautifyWarning
        )
    }

    static func showBeautifyWarning(_ message: String) {
        SensitiveSuggestionsToast.show(
            message,
            icon: "exclamationmark.triangle.fill",
            color: .systemOrange,
            screen: NSApp.keyWindow?.screen,
            duration: 3
        )
    }

    /// The single export entry. While a sensitive-data scan runs it returns nil
    /// (and calls `onBlockedWhileScanning`); pending suggestions are pixelated
    /// first ("over-redact, never leak"), exactly like Pixelate All.
    static func renderForExport(
        sourceImage: CGImage,
        document: AnnotationDocument,
        suggestions: SensitiveSuggestionsModel,
        beautifySettings: BeautifySettings,
        outputSize: CGSize?,
        onSuggestionsApplied: () -> Void = {},
        onBlockedWhileScanning: () -> Void = {},
        onWarning: (String) -> Void
    ) -> CGImage? {
        switch suggestions.prepareForExport(document) {
        case .blockedWhileScanning:
            onBlockedWhileScanning()
            return nil
        case .ready(let applied):
            if applied { onSuggestionsApplied() }
        }
        guard let annotated = AnnotationRenderer.render(
            sourceImage: sourceImage,
            objects: document.objects,
            cropRect: document.cropRect,
            expandsCanvas: true
        ) else {
            return nil
        }
        // The crop's output size applies to the cropped image, before the background is drawn
        // around it. Resizing the beautified canvas instead squeezed formats like 16:9 into the
        // crop's aspect ratio. Without beautify the result is unchanged.
        var sized = annotated
        if let size = outputSize {
            let width = max(1, Int(size.width.rounded()))
            let height = max(1, Int(size.height.rounded()))
            if width != annotated.width || height != annotated.height {
                // Say so instead of silently exporting at the original size (audit A5, 21.11.).
                if let resized = ImageUtilities.resized(annotated, width: width, height: height) {
                    sized = resized
                } else {
                    onWarning(String(localized: "Could not resize the image. It was exported at its original size."))
                }
            }
        }
        guard let beautified = BeautifyRenderer.render(image: sized, settings: beautifySettings) else {
            return nil
        }
        if let warning = beautified.warning { onWarning(warning) }
        return beautified.image
    }

    private func dragFileURL() -> URL? {
        guard !isEditingText, !sensitiveSuggestions.isScanning else {
            return nil
        }
        if let fileURL = dragRenderCache?.fileURL,
           FileManager.default.isReadableFile(atPath: fileURL.path) {
            return fileURL
        }
        guard var cache = dragRenderCache ?? makeDragRenderCache() else {
            return nil
        }

        do {
            let fileURL = try dragFileStore.fileURL(
                for: cache.renderedImage,
                id: dragFileID,
                output: screenshotOutput,
                date: captureDate,
                sourceAppName: sourceAppName,
                sourceWindowTitle: sourceWindowTitle,
                template: screenshotFilenameTemplate
            )
            cache.fileURL = fileURL
            dragRenderCache = cache
            return fileURL
        } catch {
            return nil
        }
    }

    private func dragPreviewImage() -> NSImage? {
        guard !isEditingText, !sensitiveSuggestions.isScanning else { return nil }
        return (dragRenderCache ?? makeDragRenderCache())?.previewImage
    }

    /// Runs when the pointer enters the drag button. With suggestions showing it must not
    /// render: rendering applies them, so merely passing over the button pixelated them.
    /// The drag itself still applies them (`dragFileURL`) (audit A11, 21.11.).
    private func prepareDragFile() {
        guard !sensitiveSuggestions.isShowing else { return }
        _ = dragFileURL()
    }

    private func makeDragRenderCache() -> DragRenderCache? {
        guard let rendered = renderedOutputImage() else { return nil }
        let previewImage = NSImage(cgImage: rendered, size: NSSize(width: rendered.width, height: rendered.height))
        let cache = DragRenderCache(renderedImage: rendered, previewImage: previewImage)
        dragRenderCache = cache
        return cache
    }

    private func invalidateDragCache() {
        try? dragFileStore.removeFile(for: dragFileID)
        dragFileID = UUID()
        dragRenderCache = nil
    }

    private func save() {
        if NSEvent.modifierFlags.contains(.option) {
            saveAs()
            return
        }
        commitEditingTrigger += 1
        DispatchQueue.main.async {
            if let rendered = renderedOutputImage() {
                onSave(rendered)
            } else {
                showRenderFailure()
            }
        }
    }

    private func saveAs() {
        guard !isCropMode else { return }
        commitEditingTrigger += 1
        DispatchQueue.main.async {
            if let rendered = renderedOutputImage() {
                onSaveAs(rendered)
            } else {
                showRenderFailure()
            }
        }
    }

    private func copy() {
        commitEditingTrigger += 1
        DispatchQueue.main.async {
            if let rendered = renderedOutputImage() {
                onCopy(rendered)
            } else {
                showRenderFailure()
            }
        }
    }

    /// Renders through `renderForExport` (applies pending sensitive-data suggestions),
    /// writes its own file via the share store (never removed when the editor closes or
    /// changes; pruned after 24 h) and opens the share menu.
    private func share(from anchor: SystemShareAnchor) {
        commitEditingTrigger += 1
        DispatchQueue.main.async {
            guard !sensitiveSuggestions.isScanning else {
                SensitiveSuggestionsToast.showStillScanning(screen: NSApp.keyWindow?.screen)
                return
            }
            // Never reuse a cached render: suggestions may have arrived since it was made.
            invalidateDragCache()
            guard let rendered = renderedOutputImage(),
                  let fileURL = try? shareFileStore.fileURL(
                    for: rendered,
                    id: UUID(),
                    output: screenshotOutput,
                    date: captureDate,
                    sourceAppName: sourceAppName,
                    sourceWindowTitle: sourceWindowTitle,
                    template: screenshotFilenameTemplate
                  ),
                  anchor.present(fileURL: fileURL) else {
                SensitiveSuggestionsToast.show(
                    String(localized: "Could not prepare the image for sharing"),
                    icon: "exclamationmark.triangle.fill",
                    color: .systemOrange,
                    screen: NSApp.keyWindow?.screen,
                    duration: 3
                )
                return
            }
        }
    }

    private func pin() {
        commitEditingTrigger += 1
        DispatchQueue.main.async {
            if let rendered = renderedOutputImage() {
                onPin(rendered)
            } else {
                showRenderFailure()
            }
        }
    }

    /// A failed render used to make Save/Copy/Pin do nothing at all (audit A6, 21.11.).
    /// While a scan runs, `renderForExport` has already said so.
    private func showRenderFailure() {
        guard !sensitiveSuggestions.isScanning else { return }
        Self.showBeautifyWarning(String(localized: "Could not prepare the image"))
    }
}

/// Carries one toolbar control over to the selected object. Before, every change wrote the
/// whole toolbar style: a colour change also reset the selection's width or radius (and a
/// highlighter's transparency when another tool was active). Shared by both editors.
@MainActor
enum SelectedObjectRestyle {
    /// Applies every control at once, as a preset does.
    static let allProperties = "all"

    static func apply(
        _ property: String,
        to obj: any AnnotationObject,
        controls: AnnotationKit.StrokeStyle,
        currentTool: AnnotationTool,
        redactionMode: RedactionMode,
        textFill: AnnotationColor?,
        textOutline: AnnotationColor?,
        textStroke: AnnotationColor?
    ) {
        guard property != allProperties else {
            applyAll(to: obj, controls: controls, currentTool: currentTool, redactionMode: redactionMode,
                     textFill: textFill, textOutline: textOutline, textStroke: textStroke)
            return
        }
        var style = obj.style
        switch property {
        case "color": style.color = controls.color
        case "lineWidth": style.lineWidth = controls.lineWidth
        case "filled": style.filled = controls.filled
        // Counters draw neither patterns nor arrow heads.
        case "pattern" where !(obj is CounterObject): style.pattern = controls.pattern
        case "arrowHead" where !(obj is CounterObject): style.arrowHead = controls.arrowHead
        default: break
        }
        if let pixelate = obj as? PixelateObject {
            // The slider only means "block size" while the pixelate tool is active;
            // otherwise it is the line width (audit A1).
            if property == "lineWidth", currentTool == .pixelate {
                pixelate.restyle(blockSize: controls.lineWidth, mode: pixelate.mode)
            } else if property == "redactionMode" {
                pixelate.restyle(blockSize: pixelate.blockSize, mode: redactionMode)
            }
        } else if let counter = obj as? CounterObject {
            if property == "lineWidth" { counter.radius = controls.lineWidth }
        } else if let text = obj as? TextObject {
            switch property {
            case "textFill": text.fillColor = textFill
            case "textOutline": text.outlineColor = textOutline
            case "textStroke": text.glyphStrokeColor = textStroke
            default: break
            }
        }
        obj.style = style
    }

    /// The former behaviour: the whole toolbar style.
    private static func applyAll(
        to obj: any AnnotationObject,
        controls: AnnotationKit.StrokeStyle,
        currentTool: AnnotationTool,
        redactionMode: RedactionMode,
        textFill: AnnotationColor?,
        textOutline: AnnotationColor?,
        textStroke: AnnotationColor?
    ) {
        if let pixelate = obj as? PixelateObject {
            pixelate.restyle(
                blockSize: currentTool == .pixelate ? controls.lineWidth : pixelate.blockSize,
                mode: redactionMode
            )
            pixelate.style = controls
        } else if let counter = obj as? CounterObject {
            counter.radius = controls.lineWidth
            counter.style = AnnotationKit.StrokeStyle(
                color: controls.color, lineWidth: controls.lineWidth, filled: controls.filled
            )
        } else if let text = obj as? TextObject {
            text.fillColor = textFill
            text.outlineColor = textOutline
            text.glyphStrokeColor = textStroke
            text.style = controls
        } else {
            obj.style = controls
        }
    }
}

/// Hintergrund des Editors: lebender Mesh-Verlauf mit stärkerem Glühen plus zwei weiche
/// Akzent-Lichter in den Ecken, damit das Leuchten auch neben dem Bild sichtbar bleibt
/// (die Mitte deckt die Bildkarte meist ab). Bei „Transparenz reduzieren“/„Kontrast erhöhen“
/// zeichnet AmbientBackdrop selbst den festen Verlauf, die Lichter entfallen.
private struct EditorAmbience: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AmbientBackdrop(glow: 1.6)
            if !reduceTransparency && contrast != .increased {
                let strength = colorScheme == .dark ? 0.34 : 0.26
                Ellipse()
                    .fill(FamilyTheme.accent.opacity(strength))
                    .frame(width: 520, height: 360)
                    .blur(radius: 110)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .offset(x: -160, y: -120)
                Ellipse()
                    .fill(FamilyTheme.iris.opacity(strength * 0.9))
                    .frame(width: 560, height: 380)
                    .blur(radius: 120)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .offset(x: 160, y: 140)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

// App/Sources/AnnotationEditor/AnnotationToolbar.swift
import AppKit
import SwiftUI
import AnnotationKit

struct AnnotationToolbar: View {
    @State private var shareAnchor = SystemShareAnchor()
    @Binding var currentTool: AnnotationTool
    @Binding var currentColor: AnnotationColor
    @Binding var lineWidth: CGFloat
    @Binding var strokePattern: StrokePattern
    @Binding var arrowHead: ArrowHeadStyle
    @Binding var filled: Bool
    @Binding var textFillEnabled: Bool
    @Binding var textOutlineEnabled: Bool
    @Binding var textStrokeEnabled: Bool
    @Binding var redactionMode: RedactionMode
    @Binding var showBeautifyPanel: Bool
    /// True when an inline text edit is active (either via the text tool or
    /// by double-clicking an existing TextObject in select mode). When set,
    /// the size slider behaves as a Font Size control regardless of the
    /// currently selected tool — so users can keep tuning size while typing.
    var isEditingText: Bool = false
    let canUndo: Bool
    let canRedo: Bool
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onSave: () -> Void
    let onCopy: () -> Void
    let onPin: () -> Void
    /// Renders the edited image and opens the macOS share menu anchored to `anchor`.
    var onShare: (SystemShareAnchor) -> Void = { _ in }
    let dragThumbnail: NSImage
    let onPrepareDrag: () -> Void
    let onDragFileURL: () -> URL?
    let onDragPreviewImage: () -> NSImage?
    let onDragStarted: () -> Void
    let onDragEnded: () -> Void
    let isDragDisabled: Bool
    /// A sensitive-data scan is running: Copy, Pin, Share, Save and Crop look
    /// disabled and only explain why (the editor shows a toast, never exports).
    var isExportBlocked: Bool = false
    let onCancel: () -> Void
    let onCrop: () -> Void
    var isFindingSensitiveData: Bool = false
    var onFindSensitiveData: () -> Void = {}
    var presets: [AnnotationStylePreset] = []
    var onApplyPreset: (AnnotationStylePreset) -> Void = { _ in }
    var onSavePreset: () -> Void = {}
    var onRemovePreset: (AnnotationStylePreset) -> Void = { _ in }

    /// The size slider serves multiple tools: in text / editing mode it means
    /// font size; for other tools it retains its existing role.
    private var isFontSizeMode: Bool {
        currentTool == .text || isEditingText
    }

    /// How much of the editing area is shown inline. The toolbar picks the widest
    /// level that fits (`ViewThatFits`); collapsed groups move into popovers.
    private enum Density: CaseIterable { case full, compactColors, compactStyle, minimal }

    @State private var showColorPopover = false
    @State private var showStylePopover = false
    @State private var toolbarWidth: CGFloat = 0

    /// The five base colours that stay visible when the colour row collapses.
    private static let baseColors: [AnnotationColor] = [.red, .orange, .yellow, .green, .blue]

    var body: some View {
        // macOS 26: schwebende Liquid-Glass-Kapseln über der Arbeitsfläche. Ein Container,
        // damit benachbarte Kapseln wie ein Glas wirken (gemeinsame Lichtbrechung).
        GlassEffectContainer(spacing: 10) {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                // Only the editing area adapts. Undo, Background and the actions stay
                // pinned so Save/Copy/Close never slide out of reach (issue #236).
                // No keyboard shortcuts live inside the adaptive part: ViewThatFits
                // keeps its unused variants around, and a shortcut there could fire twice.
                ViewThatFits(in: .horizontal) {
                    editingArea(.full)
                    editingArea(.compactColors)
                    editingArea(.compactStyle)
                    editingArea(.minimal)
                    // Narrow windows (~900 pt): tools on top, colour/style/crop below.
                    twoRowEditingArea
                    // Last resort on very narrow windows: the two rows scroll.
                    ScrollView(.horizontal, showsIndicators: false) { twoRowEditingArea }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    undoGroup.toolbarGlassPill()
                    // Pinned like the actions: in a narrow editor the scrolling row hid
                    // them without any hint (Michael, 21.11.: "wo kann ich den Hintergrund ändern?").
                    HStack(spacing: 2) {
                        findSensitiveButton
                        beautifyGroup
                    }
                    .toolbarGlassPill()
                    actionGroup.toolbarGlassPill()
                }
                .fixedSize()
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { toolbarWidth = $0 }

            if isFontSizeMode {
                textEffectsGroup
                    .fixedSize()
                    .toolbarGlassPill()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if currentTool == .pixelate {
                redactionModeGroup
                    .fixedSize()
                    .toolbarGlassPill()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        }
        .familyAnimation(FamilyTheme.Motion.select, value: currentTool)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .onHover { hovering in
            if hovering {
                NSCursor.arrow.set()
            }
        }
        .onChange(of: currentTool) { _, _ in
            NSCursor.arrow.set()
        }
    }

    // MARK: - Adaptive editing area

    @ViewBuilder
    private func editingArea(_ density: Density) -> some View {
        HStack(spacing: 10) {
            toolGroup.toolbarGlassPill()
            HStack(spacing: 8) {
            switch density {
            case .full:
                colorGroup
                toolbarDivider
                strokeGroup
            case .compactColors:
                compactColorGroup(showsBaseColors: true)
                toolbarDivider
                strokeGroup
            case .compactStyle:
                compactColorGroup(showsBaseColors: true)
                toolbarDivider
                styleButton
            case .minimal:
                compactColorGroup(showsBaseColors: false)
                toolbarDivider
                styleButton
            }
            presetsMenu
            toolbarDivider
            cropGroup
            }
            .toolbarGlassPill()
        }
        .fixedSize()
    }

    private var twoRowEditingArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            toolGroup.toolbarGlassPill()
            HStack(spacing: 8) {
                compactColorGroup(showsBaseColors: true)
                toolbarDivider
                styleButton
                presetsMenu
                toolbarDivider
                cropGroup
            }
            .toolbarGlassPill()
        }
        .fixedSize()
    }

    /// Current colour, optionally the five base colours, and a button that opens
    /// the full colour controls (all colours, custom colour, eyedropper, HEX).
    private func compactColorGroup(showsBaseColors: Bool) -> some View {
        HStack(spacing: 3) {
            if showsBaseColors {
                ForEach(Self.baseColors, id: \.self) { color in
                    Button(action: { currentColor = color }) {
                        Circle()
                            .fill(Color(cgColor: color.cgColor))
                            .frame(width: 19, height: 19)
                            .overlay(Circle().stroke(currentColor == color ? FamilyTheme.accent : Color.clear, lineWidth: 2))
                            .overlay(Circle().stroke(Color.black.opacity(0.24), lineWidth: 0.5))
                            .padding(2)
                            .background(Circle().fill(currentColor == color ? FamilyTheme.accent.opacity(0.12) : Color.clear))
                    }
                    .buttonStyle(.plain)
                    .help(Text(color.displayName))
                    .accessibilityLabel(Text(color.displayName))
                    .accessibilityAddTraits(currentColor == color ? .isSelected : [])
                }
            }
            Button(action: { showColorPopover.toggle() }) {
                HStack(spacing: 2) {
                    Circle()
                        .fill(Color(nsColor: currentColor.nsColor))
                        .frame(width: 19, height: 19)
                        .overlay(Circle().stroke(Color.black.opacity(0.28), lineWidth: 0.5))
                        .overlay(Circle().stroke(FamilyTheme.accent.opacity(0.55), lineWidth: 1.5).padding(-2))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(toolbarIconForeground(isActive: showColorPopover))
                }
                .padding(.horizontal, 6)
                .frame(height: 26)
                .background(toolbarButtonBackground(isActive: showColorPopover), in: Capsule())
                .toolbarHover()
            }
            .buttonStyle(.plain)
            .help(String(localized: "More Colors"))
            .accessibilityLabel(Text(String(localized: "More Colors")))
            .popover(isPresented: $showColorPopover, arrowEdge: .bottom) {
                colorGroup
                    .padding(FamilyTheme.Space.m)
            }
        }
    }

    /// Line width, stroke pattern, arrow heads and fill in one popover.
    private var styleButton: some View {
        Button(action: { showStylePopover.toggle() }) {
            Label(String(localized: "Style"), systemImage: "slider.horizontal.3")
                .labelStyle(.titleAndIcon)
                .font(FamilyTheme.font(12, weight: .medium))
                .foregroundStyle(toolbarIconForeground(isActive: showStylePopover))
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(toolbarButtonBackground(isActive: showStylePopover), in: Capsule())
                .toolbarHover()
        }
        .buttonStyle(.plain)
        .disabled(currentTool == .pixelate && (redactionMode == .solid || redactionMode == .erase))
        .help(String(localized: "Line width, line style and arrow heads"))
        .popover(isPresented: $showStylePopover, arrowEdge: .bottom) {
            strokeGroup
                .padding(FamilyTheme.Space.m)
        }
    }

    /// Reihenfolge der Werkzeugknöpfe: bestimmt, wohin die Akzent-Pille gleitet.
    private static let toolOrder: [AnnotationTool] = [
        .select, .arrow, .line, .rectangle, .ellipse, .text, .freehand, .pixelate, .counter, .highlighter, .spotlight,
    ]
    private static let toolButtonSize = CGSize(width: 30, height: 26)
    private static let toolSpacing: CGFloat = 4

    private var toolGroup: some View {
        HStack(spacing: Self.toolSpacing) {
            toolButton(.select, icon: "cursorarrow")
            toolButton(.arrow, icon: "arrow.up.right")
            toolButton(.line, icon: "line.diagonal")
            toolButton(.rectangle, icon: "rectangle")
            toolButton(.ellipse, icon: "circle")
            textToolButton
            toolButton(.freehand, icon: "pencil.tip")
            toolButton(.pixelate, icon: "eye.slash.fill")
            toolButton(.counter, icon: "number.circle.fill")
            toolButton(.highlighter, icon: "highlighter")
            toolButton(.spotlight, icon: "flashlight.on.fill")
        }
        // Eine einzige Akzent-Pille hinter der Reihe, die beim Werkzeugwechsel hinübergleitet.
        // Bewusst Versatz statt matchedGeometryEffect: ViewThatFits hält mehrere Varianten der
        // Leiste gleichzeitig, dieselbe Geometrie-ID gäbe es dann mehrfach.
        .background(alignment: .leading) {
            if let index = Self.toolOrder.firstIndex(of: currentTool) {
                Capsule()
                    .fill(FamilyTheme.accentFill)
                    .shadow(color: FamilyTheme.accentFill.opacity(0.35), radius: 4, y: 1)
                    .frame(width: Self.toolButtonSize.width, height: Self.toolButtonSize.height)
                    .offset(x: CGFloat(index) * (Self.toolButtonSize.width + Self.toolSpacing))
                    .familyAnimation(FamilyTheme.Motion.select, value: index)
                    .accessibilityHidden(true)
            }
        }
    }

    private func toolButton(_ tool: AnnotationTool, icon: String) -> some View {
        Button(action: { currentTool = tool }) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(toolIconForeground(isActive: currentTool == tool))
                .frame(width: Self.toolButtonSize.width, height: Self.toolButtonSize.height)
                .toolbarHover(isEnabled: currentTool != tool)
        }
        .buttonStyle(.plain)
        .help(tool.localizedShortcutHelpTitle)
        .accessibilityLabel(Text(tool.localizedToolName))
        .accessibilityAddTraits(currentTool == tool ? .isSelected : [])
    }

    /// Text-tool button. Rendered as a literal "Aa" glyph rather than the
    /// SF Symbol `textformat`, because Apple localizes that symbol's
    /// appearance per language (en: "Aa", zh: "格式", ja: "書式", …) and
    /// we want a consistent look across all locales — the iconic "Aa"
    /// shorthand is the industry convention for a text tool.
    ///
    /// `Text(verbatim:)` prevents SwiftUI from treating "Aa" as a
    /// LocalizedStringKey lookup.
    private var textToolButton: some View {
        Button(action: { currentTool = .text }) {
            Text(verbatim: "Aa")
                .font(FamilyTheme.font(13, weight: .semibold))
                .foregroundStyle(toolIconForeground(isActive: currentTool == .text))
                .frame(width: Self.toolButtonSize.width, height: Self.toolButtonSize.height)
                .toolbarHover(isEnabled: currentTool != .text)
        }
        .buttonStyle(.plain)
        .help(AnnotationTool.text.localizedShortcutHelpTitle)
        .accessibilityLabel(Text(AnnotationTool.text.localizedToolName))
        .accessibilityAddTraits(currentTool == .text ? .isSelected : [])
    }

    private var colorGroup: some View {
        AnnotationColorControls(currentColor: $currentColor)
    }

    /// Second row for the pixelate tool, like the text effects for the text tool.
    /// In the main row the German labels ("Schwarzer Balken") didn't fit: first they
    /// covered the colour field, then the pinned buttons cut them off (Michael, 21.11.).
    private var redactionModeGroup: some View {
        HStack(spacing: 8) {
            Picker("", selection: $redactionMode) {
                ForEach(RedactionMode.allCases, id: \.self) { mode in
                    Text(mode.localizedLabel).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help(redactionMode == .solid || redactionMode == .erase
                  ? String(localized: "Redaction Mode")
                  : String(localized: "Not for confidential data – use the black bar."))
            Spacer(minLength: 0)
        }
    }

    private var strokeGroup: some View {
        HStack(spacing: 8) {
            if isFontSizeMode {
                // Text tool or mid-edit: slider becomes a font-size control.
                Slider(value: $lineWidth, in: 12...120, step: 1)
                    .frame(width: 80)
                    .help("Font Size: \(Int(lineWidth))")
            } else if currentTool == .pixelate {
                // The mode picker sits in its own row below (`redactionModeGroup`).
                if redactionMode != .solid && redactionMode != .erase {
                    Slider(value: $lineWidth, in: 4...48, step: 2)
                        .frame(width: 80)
                        .help("Block Size: \(Int(lineWidth))")
                }
            } else if currentTool == .counter {
                Slider(value: $lineWidth, in: 12...40, step: 1)
                    .frame(width: 80)
                    .help("Counter Size: \(Int(lineWidth))")
            } else if currentTool == .highlighter {
                Slider(value: $lineWidth, in: 10...100, step: 2)
                    .frame(width: 80)
                    .help("Highlighter Width: \(Int(lineWidth))")
            } else {
                Slider(value: $lineWidth, in: 1...40, step: 1)
                    .frame(width: 80)
                    .help("Line Width: \(Int(lineWidth))")
            }
            if currentTool == .arrow || currentTool == .line {
                Picker("", selection: $strokePattern) {
                    ForEach(StrokePattern.allCases, id: \.self) { pattern in
                        StrokePatternGlyph(pattern: pattern)
                            .tag(pattern)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 104)
                .help("Stroke Pattern")
            }
            if currentTool == .arrow {
                Picker("", selection: $arrowHead) {
                    ForEach(ArrowHeadStyle.allCases, id: \.self) { style in
                        ArrowHeadGlyph(style: style)
                            .tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 136)
                .help("Arrow Style")
            }
            // Fill toggle is meaningless for counter / highlighter / text.
            if currentTool != .counter
                && currentTool != .arrow
                && currentTool != .line
                && currentTool != .highlighter
                && !isFontSizeMode {
                Toggle(isOn: $filled) {
                    Image(systemName: filled ? "square.fill" : "square")
                        .font(.system(size: 12))
                }
                .toggleStyle(.button)
                .help("Fill Shape")
            }
        }
    }

    private var textEffectsGroup: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                textEffectToggle("Fill", isOn: $textFillEnabled, help: "Text Fill")
                textEffectToggle("Outline", isOn: $textOutlineEnabled, help: "Text Box Outline")
                textEffectToggle("Trace", isOn: $textStrokeEnabled, help: "Text Trace")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func textEffectToggle(
        _ title: LocalizedStringKey,
        isOn: Binding<Bool>,
        help: LocalizedStringKey
    ) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(FamilyTheme.font(11, weight: .semibold))
                .frame(minWidth: 46, minHeight: 20)
        }
        .toggleStyle(.button)
        .controlSize(.small)
        .help(help)
    }

    private var presetsMenu: some View {
        Menu {
            ForEach(presets) { preset in
                Button { onApplyPreset(preset) } label: {
                    Label { Text(preset.title) } icon: { Image(nsImage: preset.swatch) }
                        .labelStyle(.titleAndIcon)
                }
            }
            if !presets.isEmpty { Divider() }
            Button("Save Current Style", action: onSavePreset)
            if !presets.isEmpty {
                Menu("Remove") {
                    ForEach(presets) { preset in
                        Button(preset.title) { onRemovePreset(preset) }
                    }
                }
            }
        } label: {
            Image(systemName: "bookmark")
                .font(.system(size: 13, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Style Presets")
        .accessibilityLabel(Text("Style Presets"))
        .disabled(isEditingText)
    }

    private var cropGroup: some View {
        Button(action: onCrop) {
            Image(systemName: "crop")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(toolbarIconForeground(isActive: false))
                .frame(width: 30, height: 26)
                .toolbarHover()
        }
        .buttonStyle(.plain)
        .opacity(isExportBlocked ? 0.45 : 1)
        .help(isExportBlocked ? "Still looking for sensitive data …" : "Crop")
        .accessibilityLabel(Text("Crop"))
        .disabled(isEditingText)
    }

    private var findSensitiveButton: some View {
        Button(action: onFindSensitiveData) {
            ZStack {
                if isFindingSensitiveData {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(toolbarIconForeground(isActive: false))
                }
            }
            .frame(width: 30, height: 26)
            .background(toolbarButtonBackground(isActive: isFindingSensitiveData), in: Capsule())
            .toolbarHover()
        }
        .buttonStyle(.plain)
        .help(isFindingSensitiveData ? "Finding Sensitive Data…" : "Find Sensitive Data")
        .accessibilityLabel(Text("Find Sensitive Data"))
        .accessibilityValue(Text(isFindingSensitiveData ? String(localized: "Scanning") : ""))
        .disabled(isEditingText || isFindingSensitiveData)
    }

    private var beautifyGroup: some View {
        Button(action: { showBeautifyPanel.toggle() }) {
            // Icon plus word: the bare sparkles icon wasn't found (Michael, 21.11.:
            // "Hintergrund ändern finde ich gar nicht, Formate auch nicht").
            // Below ~1000 pt the word gives way to the icon; the tooltip still names it.
            Group {
                let label = Label(String(localized: "Background"),
                                  systemImage: showBeautifyPanel ? "sparkles.rectangle.stack.fill" : "sparkles")
                if isNarrow { label.labelStyle(.iconOnly) } else { label.labelStyle(.titleAndIcon) }
            }
                .font(FamilyTheme.font(12, weight: .medium))
                .frame(minWidth: 30)
                .foregroundStyle(toolbarIconForeground(isActive: showBeautifyPanel))
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(toolbarButtonBackground(isActive: showBeautifyPanel), in: Capsule())
                .toolbarHover()
        }
        .buttonStyle(.plain)
        .help(String(localized: "Background and format (16:9, 1:1, 4:5)"))
        .accessibilityLabel(Text(String(localized: "Background")))
    }

    /// Measured width; 0 means "not measured yet" and counts as wide.
    private var isNarrow: Bool { toolbarWidth > 0 && toolbarWidth < 1000 }

    private var undoGroup: some View {
        HStack(spacing: 2) {
            // Off while a text is edited: ⌘Z then belongs to the text field, and the
            // document undo would act on objects behind the open editor.
            Button(action: onUndo) {
                undoFace("arrow.uturn.backward", isEnabled: canUndo && !isEditingText)
            }
            .disabled(!canUndo || isEditingText)
            .keyboardShortcut("z", modifiers: .command)
            .help("Undo")
            .accessibilityLabel(Text("Undo"))
            Button(action: onRedo) {
                undoFace("arrow.uturn.forward", isEnabled: canRedo && !isEditingText)
            }
            .disabled(!canRedo || isEditingText)
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .help("Redo")
            .accessibilityLabel(Text("Redo"))
        }
        .buttonStyle(.plain)
    }

    private func undoFace(_ icon: String, isEnabled: Bool) -> some View {
        Image(systemName: icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(isEnabled ? 0.82 : 0.28))
            .frame(width: 30, height: 26)
            .toolbarHover(isEnabled: isEnabled)
    }

    private var actionGroup: some View {
        HStack(spacing: 2) {
            actionButton(icon: "xmark", help: "Close", isDestructive: true, action: onCancel)

            dragActionButton

            copyActionButton

            actionButton(icon: "pin", help: "Pin", isBlockable: true, action: onPin)
                .keyboardShortcut("p", modifiers: .command)

            actionButton(icon: "square.and.arrow.up", help: "Share", isBlockable: true, action: { onShare(shareAnchor) })
                .background(SystemShareAnchorView(anchor: shareAnchor))
                .disabled(isEditingText)

            actionButton(icon: "square.and.arrow.down", help: "Save", isPrimary: true, isBlockable: true, action: onSave)
                .keyboardShortcut("s", modifiers: .command)
        }
    }

    private var dragActionButton: some View {
        ZStack {
            actionButtonFace(
                icon: "hand.draw",
                isPrimary: false,
                isDestructive: false
            )
            .opacity(isDragDisabled ? 0.45 : 1)

            QuickAccessDragSourceView(
                thumbnail: dragThumbnail,
                dragImageSize: CGSize(width: 240, height: 160),
                fileURLProvider: onDragFileURL,
                dragImageProvider: onDragPreviewImage,
                onDragStarted: onDragStarted,
                onDragEnded: { _ in onDragEnded() }
            )
            .frame(width: 32, height: 26)
            .disabled(isDragDisabled)
            .accessibilityHidden(true)
        }
        .help(dragHelp)
        .onHover { hovering in
            if hovering && !isDragDisabled {
                onPrepareDrag()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Drag Edited Image")
    }

    private var dragHelp: LocalizedStringKey {
        if isExportBlocked { return "Still looking for sensitive data …" }
        return isDragDisabled ? "Finish text editing before dragging" : "Drag Edited Image"
    }

    @ViewBuilder
    private var copyActionButton: some View {
        let button = actionButton(
            icon: "doc.on.doc",
            help: "Copy Image and Close (⌘C · ⏎ · ⌘⇧C)",
            label: "Copy",
            isBlockable: true,
            action: onCopy
        )
        .keyboardShortcut("c", modifiers: [.command, .shift])
        if isEditingText {
            // Leave ⌘C and Return to the text field being edited.
            button
        } else {
            button.background {
                ZStack {
                    hiddenCopyShortcut(.return, modifiers: [])
                    // Plain ⌘C only reaches here when the canvas declined it,
                    // i.e. no annotation object is selected (issue #236/#237).
                    hiddenCopyShortcut(KeyEquivalent("c"), modifiers: .command)
                }
            }
        }
    }

    private func hiddenCopyShortcut(
        _ key: KeyEquivalent,
        modifiers: EventModifiers
    ) -> some View {
        Button(action: onCopy) { EmptyView() }
            .keyboardShortcut(key, modifiers: modifiers)
            .buttonStyle(.plain)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }

    private func actionButton(
        icon: String,
        help: LocalizedStringKey,
        label: LocalizedStringKey? = nil,
        isPrimary: Bool = false,
        isDestructive: Bool = false,
        isBlockable: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let isBlocked = isBlockable && isExportBlocked
        // Stays clickable (and keeps its shortcut) so a blocked export explains
        // itself with a toast instead of failing silently.
        return Button(action: action) {
            actionButtonFace(icon: icon, isPrimary: isPrimary, isDestructive: isDestructive)
                .opacity(isBlocked ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .help(isBlocked ? "Still looking for sensitive data …" : help)
        // VoiceOver read only the SF Symbol name ("xmark", "pin").
        .accessibilityLabel(Text(label ?? help))
    }

    private func actionButtonFace(
        icon: String,
        isPrimary: Bool,
        isDestructive: Bool
    ) -> some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(actionIconForeground(isPrimary: isPrimary, isDestructive: isDestructive))
            .frame(width: isPrimary ? 40 : 32, height: 26)
            .background(actionButtonBackground(isPrimary: isPrimary, isDestructive: isDestructive), in: Capsule())
            .toolbarHover(isEnabled: !isPrimary)
    }

    private var toolbarDivider: some View {
        Capsule()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 16)
    }

    private func toolbarButtonBackground(isActive: Bool) -> Color {
        isActive ? FamilyTheme.accent.opacity(0.18) : Color.clear
    }

    private func toolbarIconForeground(isActive: Bool) -> Color {
        isActive ? FamilyTheme.accent : Color.primary.opacity(0.82)
    }

    /// Werkzeugsymbol: auf der Akzent-Pille weiß (accentFill ist für Weiß gerechnet).
    private func toolIconForeground(isActive: Bool) -> Color {
        isActive ? .white : Color.primary.opacity(0.82)
    }

    private func actionButtonBackground(isPrimary: Bool, isDestructive: Bool) -> Color {
        if isPrimary {
            return FamilyTheme.accentFill   // weißes Symbol darauf
        }
        return Color.clear
    }

    private func actionIconForeground(isPrimary: Bool, isDestructive: Bool) -> Color {
        if isPrimary {
            return .white
        }
        if isDestructive {
            return Color.primary.opacity(0.72)
        }
        return Color.primary.opacity(0.84)
    }

}

// MARK: - Glas-Kapseln und Hover

private struct ToolbarHoverModifier: ViewModifier {
    var isEnabled: Bool
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background {
                Capsule()
                    .fill(Color.primary.opacity(isEnabled && isHovered ? 0.09 : 0))
            }
            .contentShape(Capsule())
            .onHover { isHovered = $0 }
            .familyAnimation(FamilyTheme.Motion.hover, value: isHovered)
    }
}

private extension View {
    /// Leise Hover-Hervorhebung (neutrale Kapsel), wie Leistenknöpfe in macOS 26.
    func toolbarHover(isEnabled: Bool = true) -> some View {
        modifier(ToolbarHoverModifier(isEnabled: isEnabled))
    }

    /// Schwebende Glas-Kapsel um eine Knopfgruppe der Werkzeugleiste.
    func toolbarGlassPill() -> some View {
        padding(.horizontal, 5)
            .padding(.vertical, 4)
            .familyLiquidGlass(in: Capsule())
    }
}

extension AnnotationTool {
    var localizedShortcutHelpTitle: String {
        AnnotationToolShortcut.helpTitle(localizedToolName, for: self)
    }

    var localizedToolName: String {
        switch self {
        case .select: return String(localized: "Select")
        case .arrow: return String(localized: "Arrow")
        case .line: return String(localized: "Line")
        case .rectangle: return String(localized: "Rectangle")
        case .ellipse: return String(localized: "Ellipse")
        case .text: return String(localized: "Text")
        case .freehand: return String(localized: "Draw")
        case .pixelate: return String(localized: "Pixelate / Blur")
        case .counter: return String(localized: "Counter")
        case .highlighter: return String(localized: "Highlighter")
        case .spotlight: return String(localized: "Spotlight")
        }
    }
}

/// Segmented pickers on macOS only draw `Image` / `Text` labels, so glyphs are
/// rendered into template images (tinted for light and dark mode by the system).
private func templateGlyph(width: CGFloat, height: CGFloat, draw: @escaping (CGContext, CGSize) -> Void) -> Image {
    let size = NSSize(width: width, height: height)
    let image = NSImage(size: size, flipped: true) { _ in
        if let ctx = NSGraphicsContext.current?.cgContext { draw(ctx, size) }
        return true
    }
    image.isTemplate = true
    return Image(nsImage: image)
}

/// A small sample arrow drawn with the real renderer, so the picker matches the canvas.
struct ArrowHeadGlyph: View {
    let style: ArrowHeadStyle

    var body: some View {
        templateGlyph(width: 24, height: 14) { ctx, size in
            let arrow = ArrowObject(
                start: CGPoint(x: 3, y: size.height / 2),
                end: CGPoint(x: size.width - 3, y: size.height / 2),
                style: AnnotationKit.StrokeStyle(color: .black, lineWidth: 2, arrowHead: style)
            )
            arrow.headLength = 6
            arrow.render(in: ctx)
        }
    }
}

struct StrokePatternGlyph: View {
    let pattern: StrokePattern

    var body: some View {
        templateGlyph(width: 22, height: 14) { ctx, size in
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineCap(.round)
            switch pattern {
            case .solid:
                ctx.setLineWidth(2)
            case .dashed:
                ctx.setLineWidth(2)
                ctx.setLineDash(phase: 0, lengths: [7, 5])
            case .dotted:
                ctx.setLineWidth(2.4)
                ctx.setLineDash(phase: 0, lengths: [0, 5])
            }
            ctx.move(to: CGPoint(x: 3, y: size.height / 2))
            ctx.addLine(to: CGPoint(x: size.width - 3, y: size.height / 2))
            ctx.strokePath()
        }
    }
}

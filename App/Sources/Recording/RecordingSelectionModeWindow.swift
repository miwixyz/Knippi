import AppKit
import SwiftUI

enum RecordingSelectionMode: CaseIterable, Equatable {
    case area
    case window
    case fullScreen
    case lastArea

    init(action: CaptureOverlayShortcutAction) {
        switch action {
        case .selectArea: self = .area
        case .selectWindow: self = .window
        case .selectFullScreen: self = .fullScreen
        case .reuseLastArea: self = .lastArea
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .area: "Area"
        case .window: "Window"
        case .fullScreen: "Full Screen"
        case .lastArea: "Last Area"
        }
    }

    var shortcut: String {
        switch self {
        case .area: "A"
        case .window: "W"
        case .fullScreen: "F"
        case .lastArea: "R"
        }
    }

    var systemImage: String {
        switch self {
        case .area: "viewfinder"
        case .window: "macwindow"
        case .fullScreen: "rectangle.inset.filled"
        case .lastArea: "arrow.counterclockwise"
        }
    }
}

@MainActor
final class RecordingSelectionModeWindow: NSPanel {
    private let onSelect: (RecordingSelectionMode) -> Void
    private let onCancel: () -> Void
    private let onHover: (Bool) -> Void
    private let canUseLastArea: Bool
    private var selectedMode: RecordingSelectionMode

    init(
        screen: NSScreen,
        selectedMode: RecordingSelectionMode,
        canUseLastArea: Bool,
        onSelect: @escaping (RecordingSelectionMode) -> Void,
        onCancel: @escaping () -> Void,
        onHover: @escaping (Bool) -> Void = { _ in }
    ) {
        self.onSelect = onSelect
        self.onCancel = onCancel
        self.onHover = onHover
        self.canUseLastArea = canUseLastArea
        self.selectedMode = selectedMode

        // Leiste 520 × 56 pt, oben 30 pt unter dem sichtbaren Rand wie bisher; das Fenster ist
        // ringsum um Floating.edge größer, damit der Schatten der Leiste nicht abgeschnitten wird.
        let edge = FamilyTheme.Floating.edge
        let rail = NSSize(width: 520, height: 56)
        let visible = screen.visibleFrame
        let frame = NSRect(
            x: visible.midX - rail.width / 2 - edge,
            y: visible.maxY - 30 - rail.height - edge,
            width: rail.width + 2 * edge,
            height: rail.height + 2 * edge
        )

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver + 1
        isOpaque = false
        backgroundColor = .clear
        // Nur der Schatten der Ansicht (vorher doppelt: Fenster- plus Ansichtsschatten).
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        contentView = makeContentView()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func show() {
        orderFrontRegardless()
        makeKey()
        makeFirstResponder(contentView)
    }

    func setSelectedMode(_ mode: RecordingSelectionMode) {
        selectedMode = mode
        updateContent()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
            return
        }
        if event.keyCode == 49 {
            selectMode(selectedMode == .window ? .area : .window)
            return
        }
        if let action = CaptureOverlayShortcutAction(event: event) {
            let mode = RecordingSelectionMode(action: action)
            guard mode != .lastArea || canUseLastArea else {
                NSSound.beep()
                return
            }
            selectMode(mode)
            return
        }
        super.keyDown(with: event)
    }

    private func selectMode(_ mode: RecordingSelectionMode) {
        selectedMode = mode
        updateContent()
        onSelect(mode)
    }

    override func mouseEntered(with event: NSEvent) {
        onHover(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover(false)
    }

    /// Auswahl als beobachtbarer Zustand: die Leiste bleibt dieselbe Ansicht, damit die
    /// Akzent-Pille zur neuen Art gleiten kann (vorher wurde die Ansicht neu gebaut).
    private let railModel = RecordingSelectionModeRailModel()

    private func makeContentView() -> NSView {
        railModel.selectedMode = selectedMode
        let view = NSHostingView(rootView: RecordingSelectionModeRail(
            model: railModel,
            canUseLastArea: canUseLastArea,
            onSelect: { [weak self] mode in self?.selectMode(mode) }
        ))
        view.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
        return view
    }

    private func updateContent() {
        railModel.selectedMode = selectedMode
        makeFirstResponder(contentView)
    }
}

@MainActor
@Observable
private final class RecordingSelectionModeRailModel {
    var selectedMode: RecordingSelectionMode = .area
}

/// Modus-Auswahl als schwebende Glas-Kapsel; die gewählte Art trägt die leuchtende
/// Akzent-Pille, die beim Wechsel hinübergleitet (Glas-Umbau Phase 3).
private struct RecordingSelectionModeRail: View {
    let model: RecordingSelectionModeRailModel
    let canUseLastArea: Bool
    let onSelect: (RecordingSelectionMode) -> Void

    @Namespace private var pill
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(RecordingSelectionMode.allCases, id: \.self) { mode in
                let isSelected = model.selectedMode == mode
                // Auf der Akzent-Pille weiß (accentFill ist für weiße Schrift gerechnet).
                let foregroundColor: Color = isSelected ? .white : FamilyTheme.textPrimary
                let shortcutColor: Color = isSelected ? .white.opacity(0.8) : FamilyTheme.textSecondary

                Button {
                    onSelect(mode)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: mode.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                        Text(mode.title)
                            .font(FamilyTheme.font(12, weight: .semibold))
                            .lineLimit(1)
                        Text(mode.shortcut)
                            .font(FamilyTheme.font(10, weight: .bold))
                            .foregroundStyle(shortcutColor)
                    }
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .foregroundStyle(foregroundColor)
                    .background {
                        if isSelected {
                            CaptureAccentPill()
                                .matchedGeometryEffect(id: "selectedMode", in: pill)
                        }
                    }
                    .contentShape(Capsule())
                    .captureHoverLift(isEnabled: !isSelected)
                }
                .buttonStyle(RecordingModeButtonStyle())
                .disabled(mode == .lastArea && !canUseLastArea)
                .help(mode == .lastArea && !canUseLastArea ? "Record an area once to enable Last Area" : "")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(6)
        .frame(width: 520, height: 52)
        .familyAnimation(FamilyTheme.Motion.select, value: model.selectedMode)
        .familyLiquidGlass(in: Capsule(), tint: FamilyTheme.glassReadableTint)
        .captureAppear(appeared, reduceMotion: reduceMotion)
        .padding(.vertical, 2)
        .padding(FamilyTheme.Floating.edge)
        .onAppear {
            withAnimation(reduceMotion ? FamilyTheme.Motion.reduced : FamilyTheme.Motion.appear) { appeared = true }
        }
    }
}

private struct RecordingModeButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.86 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

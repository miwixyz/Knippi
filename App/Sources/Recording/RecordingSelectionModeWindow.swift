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

    private func makeContentView() -> NSView {
        let view = NSHostingView(rootView: RecordingSelectionModeRail(
            selectedMode: selectedMode,
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
        contentView = makeContentView()
        makeFirstResponder(contentView)
    }
}

private struct RecordingSelectionModeRail: View {
    let selectedMode: RecordingSelectionMode
    let canUseLastArea: Bool
    let onSelect: (RecordingSelectionMode) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(RecordingSelectionMode.allCases, id: \.self) { mode in
                let isSelected = selectedMode == mode
                // Aktiv: Akzentfläche mit `onAccent` (nie festes Weiß, Design-System G2).
                let foregroundColor: Color = isSelected ? FamilyTheme.onAccent : FamilyTheme.textPrimary
                let shortcutColor: Color = isSelected ? FamilyTheme.onAccent.opacity(0.78) : FamilyTheme.textSecondary
                let backgroundColor: Color = isSelected ? FamilyTheme.accent : .clear

                Button {
                    onSelect(mode)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: mode.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                        Text(mode.title)
                            .font(FamilyTheme.font(12, weight: .medium))
                            .lineLimit(1)
                        Text(mode.shortcut)
                            .font(FamilyTheme.font(10, weight: .semibold))
                            .foregroundStyle(shortcutColor)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(foregroundColor)
                    .background(
                        backgroundColor,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(RecordingModeButtonStyle())
                .disabled(mode == .lastArea && !canUseLastArea)
                .help(mode == .lastArea && !canUseLastArea ? "Record an area once to enable Last Area" : "")
            }
        }
        .padding(6)
        .frame(width: 520, height: 56)
        .familyFloatingSurface(in: RoundedRectangle(cornerRadius: FamilyTheme.Floating.radius, style: .continuous))
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

import AppKit
import SwiftUI

/// Bedienelemente über einem angehefteten Bild (Glas-Umbau Phase 3): beim Überfahren eine
/// kleine Glas-Kapsel mit Kopieren, Sichern, Deckkraft und Schließen, oben rechts das
/// Schloss, beim Zoomen eine Glas-Kapsel mit der Prozentzahl. Das Kontextmenü des Bildes
/// bleibt unverändert. Durchsichtige Stellen lassen Klicks zum Bild durch.
@MainActor
final class PinnedScreenshotChromeView: NSView {
    let model = PinnedScreenshotChromeModel()

    override var isFlipped: Bool { true }

    var isLocked: Bool {
        get { model.isLocked }
        set { model.isLocked = newValue }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        let host = NSHostingView(rootView: PinnedScreenshotChromeContent(model: model))
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(host)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showZoom(_ scalePercent: Int) {
        model.zoomPercent = scalePercent
        model.zoomVisibleToken += 1
        let token = model.zoomVisibleToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, self.model.zoomVisibleToken == token else { return }
            self.model.zoomPercent = nil
        }
    }
}

@MainActor
@Observable
final class PinnedScreenshotChromeModel {
    var isLocked = false
    /// Zeiger über dem Bild (gemeldet vom Bildfenster).
    var isPointerOverImage = false
    /// Zeiger über der Kapsel selbst (das Chrome-Fenster liegt dann vorn).
    var isPointerOverControls = false
    /// Nach dem Verlassen kurz stehen lassen, damit der Weg vom Bild zur Kapsel nicht flackert.
    var controlsVisible = false
    var zoomPercent: Int?
    var zoomVisibleToken = 0
    var opacity: Double = 1

    var onCopy: () -> Void = {}
    var onSave: () -> Void = {}
    var onClose: () -> Void = {}
    var onToggleLock: () -> Void = {}
    var onSetOpacity: (Double) -> Void = { _ in }

    private var hideToken = 0

    func pointerChanged() {
        let inside = isPointerOverImage || isPointerOverControls
        hideToken += 1
        if inside {
            controlsVisible = true
        } else {
            let token = hideToken
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, self.hideToken == token else { return }
                self.controlsVisible = false
            }
        }
    }
}

private struct PinnedScreenshotChromeContent: View {
    let model: PinnedScreenshotChromeModel

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 200
            ZStack {
                if let percent = model.zoomPercent {
                    Text(verbatim: "\(percent) %")
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(FamilyTheme.textPrimary)
                        .contentTransition(.numericText())
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .familyLiquidGlass(in: Capsule(), tint: FamilyTheme.glassReadableTint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 10)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                        .allowsHitTesting(false)
                }

                // Schloss: immer sichtbar, solange gesperrt (sonst käme man nicht mehr heran,
                // ein gesperrtes Bild lässt Klicks durch); entsperrt nur beim Überfahren.
                if model.isLocked || model.controlsVisible {
                    PinnedChromeRoundButton(
                        icon: model.isLocked ? "lock.fill" : "lock.open.fill",
                        help: model.isLocked ? String(localized: "Unlock") : String(localized: "Lock"),
                        isActive: model.isLocked,
                        action: model.onToggleLock
                    )
                    .onHover { model.isPointerOverControls = $0; model.pointerChanged() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(10)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                if model.controlsVisible && !model.isLocked {
                    actions(compact: compact)
                        .onHover { model.isPointerOverControls = $0; model.pointerChanged() }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 10)
                        .transition(.opacity.combined(with: .offset(y: 6)).combined(with: .scale(scale: 0.96, anchor: .bottom)))
                }
            }
        }
        .familyAnimation(FamilyTheme.Motion.appear, value: model.controlsVisible)
        .familyAnimation(FamilyTheme.Motion.select, value: model.isLocked)
        .familyAnimation(.snappy(duration: 0.18), value: model.zoomPercent)
    }

    private func actions(compact: Bool) -> some View {
        HStack(spacing: 2) {
            PinnedChromeButton(icon: "doc.on.doc", help: String(localized: "Copy"), action: model.onCopy)
            PinnedChromeButton(icon: "square.and.arrow.down", help: String(localized: "Save"), action: model.onSave)
            if !compact {
                Menu {
                    ForEach([1.0, 0.75, 0.5, 0.25], id: \.self) { value in
                        Button {
                            model.onSetOpacity(value)
                        } label: {
                            if abs(model.opacity - value) < 0.01 {
                                Label { Text(verbatim: "\(Int(value * 100))%") } icon: { Image(systemName: "checkmark") }
                            } else {
                                Text(verbatim: "\(Int(value * 100))%")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FamilyTheme.textPrimary.opacity(0.85))
                        .frame(width: 30, height: 26)
                        .captureHoverLift()
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(String(localized: "Opacity"))
                .accessibilityLabel(Text("Opacity"))
            }
            Capsule().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 16)
            PinnedChromeButton(icon: "xmark", help: String(localized: "Close"), action: model.onClose)
        }
        .captureGlassPill(readable: true)
    }
}

private struct PinnedChromeButton: View {
    let icon: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(FamilyTheme.textPrimary.opacity(0.85))
                .frame(width: 30, height: 26)
                .captureHoverLift()
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(Text(help))
    }
}

private struct PinnedChromeRoundButton: View {
    let icon: String
    let help: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isActive ? Color.white : FamilyTheme.textPrimary.opacity(0.85))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 30, height: 30)
                .background { if isActive { CaptureAccentPill(shape: Circle()) } }
                .familyLiquidGlass(in: Circle(), tint: isActive ? nil : FamilyTheme.glassReadableTint)
                .captureHoverLift(in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(Text(help))
    }
}

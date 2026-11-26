// App/Sources/Capture/ScrollCaptureHUD.swift
import AppKit
import SwiftUI
import CaptureKit
import SharedKit

/// Persistent overlay shown during scrolling capture.
/// Shows: selection border, live preview on the left, Cancel/Start/Done at the bottom.
@MainActor
final class ScrollCaptureOverlay {
    private var borderWindow: NSPanel?
    private var controlsWindow: NSPanel?
    private var previewWindow: NSPanel?
    private var borderView: ScrollCaptureBorderView?
    private let viewModel = ScrollCaptureViewModel()
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var keyEventTap: CFMachPort?
    private var keyEventTapRunLoopSource: CFRunLoopSource?
    private var escapeHotKey: ScrollCaptureEscapeHotKey?

    var onStart: (() -> Void)?
    var onAutoStart: (() -> Void)?
    var onDone: (() -> Void)?
    var onCancel: (() -> Void)?

    func show(selectionRect: CGRect, screen: NSScreen) {
        let screenOrigin = screen.frame.origin
        let screenRect = NSRect(
            x: screenOrigin.x + selectionRect.origin.x,
            y: screenOrigin.y + selectionRect.origin.y,
            width: selectionRect.width,
            height: selectionRect.height
        )

        showBorder(screenRect: screenRect)
        showControls(screenRect: screenRect, screen: screen)
        showPreview(screenRect: screenRect, screen: screen)
        installKeyHandlers()
    }

    func setCapturing(_ capturing: Bool) {
        viewModel.isCapturing = capturing
    }

    func updatePreview(image: CGImage, height: Int, frameCount: Int, isTrackingLost: Bool = false) {
        viewModel.isTrackingLost = isTrackingLost
        borderView?.isWarning = isTrackingLost
        viewModel.previewImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        viewModel.currentHeight = height
        viewModel.frameCount = frameCount
    }

    func close() {
        escapeHotKey?.unregister()
        escapeHotKey = nil
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
        if let source = keyEventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            keyEventTapRunLoopSource = nil
        }
        if let tap = keyEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            // Invalidate so the tap can never call back into a freed overlay
            // through its unretained refcon (audit C7, 21.11.).
            CFMachPortInvalidate(tap)
            keyEventTap = nil
        }
        borderWindow?.orderOut(nil)
        borderWindow = nil
        controlsWindow?.orderOut(nil)
        controlsWindow = nil
        previewWindow?.orderOut(nil)
        previewWindow = nil
    }

    private func installKeyHandlers() {
        escapeHotKey = ScrollCaptureEscapeHotKey { [weak self] in
            self?.onCancel?()
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            switch event.keyCode {
            case 53: // ESC
                self.onCancel?()
                return nil // consume the event
            case 36, 76: // Return, keypad Enter
                // Pass through while capturing (audit C7, 21.11.).
                if self.viewModel.isCapturing { return event }
                self.startCaptureFromKeyboard()
                return nil
            default:
                return event
            }
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return } // ESC
            Task { @MainActor in
                self?.onCancel?()
            }
        }

        installKeyEventTap()
    }

    private func installKeyEventTap() {
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, refcon in
                // macOS disables a tap whose callback was too slow or on certain user
                // input; without re-enabling, ESC and Return silently stop working.
                // The tap's run-loop source is on the main run loop.
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let refcon {
                        let overlay = Unmanaged<ScrollCaptureOverlay>.fromOpaque(refcon).takeUnretainedValue()
                        MainActor.assumeIsolated {
                            if let tap = overlay.keyEventTap {
                                CGEvent.tapEnable(tap: tap, enable: true)
                            }
                        }
                    }
                    return Unmanaged.passUnretained(event)
                }
                guard type == .keyDown,
                      let refcon else {
                    return Unmanaged.passUnretained(event)
                }

                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                guard keyCode == 53 || keyCode == 36 || keyCode == 76 else {
                    return Unmanaged.passUnretained(event)
                }

                let overlay = Unmanaged<ScrollCaptureOverlay>.fromOpaque(refcon).takeUnretainedValue()
                // Once capture is running, Return/Enter belong to the app being
                // scrolled again; only ESC stays reserved (audit C7, 21.11.).
                // The tap's run-loop source lives on the main run loop.
                if keyCode != 53, MainActor.assumeIsolated({ overlay.viewModel.isCapturing }) {
                    return Unmanaged.passUnretained(event)
                }
                Task { @MainActor in
                    if keyCode == 53 {
                        overlay.onCancel?()
                    } else {
                        overlay.startCaptureFromKeyboard()
                    }
                }
                return nil
            },
            userInfo: refcon
        ) else {
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        keyEventTap = tap
        keyEventTapRunLoopSource = source
    }

    private func startCaptureFromKeyboard() {
        guard !viewModel.isCapturing else { return }
        onStart?()
    }

    // MARK: - Border

    private func showBorder(screenRect: NSRect) {
        let inset: CGFloat = 3
        let borderRect = screenRect.insetBy(dx: -inset, dy: -inset)

        let panel = NSPanel(
            contentRect: borderRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false

        let borderView = ScrollCaptureBorderView(frame: NSRect(origin: .zero, size: borderRect.size))
        panel.contentView = borderView
        self.borderView = borderView

        self.borderWindow = panel
        panel.orderFrontRegardless()
    }

    // MARK: - Controls

    private func showControls(screenRect: NSRect, screen: NSScreen) {
        let controlsRect = ScrollCaptureOverlayPlacement.controlsFrame(
            selectionRect: screenRect,
            visibleFrame: screen.visibleFrame,
            controlsSize: CGSize(width: 460, height: ScrollCaptureOverlayPlacement.defaultControlsSize.height)
        )

        // Glas-Kapsel mit eigenem Schatten: Fenster ringsum um Floating.edge größer, kein
        // Fensterschatten (sonst Rechteck bzw. abgeschnittener Schatten, Familien-Regel).
        let edge = FamilyTheme.Floating.edge
        let panel = NSPanel(
            contentRect: controlsRect.insetBy(dx: -edge, dy: -edge),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false

        let hostingView = NSHostingView(rootView: ScrollCaptureControlsView(
            viewModel: viewModel,
            onStart: { [weak self] in self?.onStart?() },
            onAutoStart: { [weak self] in self?.onAutoStart?() },
            onCancel: { [weak self] in self?.onCancel?() },
            onDone: { [weak self] in self?.onDone?() }
        ))
        panel.contentView = hostingView

        self.controlsWindow = panel
        panel.orderFrontRegardless()
    }

    // MARK: - Preview

    private func showPreview(screenRect: NSRect, screen: NSScreen) {
        guard let previewRect = ScrollCaptureOverlayPlacement.previewFrame(
            selectionRect: screenRect,
            visibleFrame: screen.visibleFrame
        ) else { return }

        let panel = NSPanel(
            contentRect: previewRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false

        let hostingView = NSHostingView(rootView: ScrollCapturePreviewView(viewModel: viewModel))
        panel.contentView = hostingView

        self.previewWindow = panel
        panel.orderFrontRegardless()
    }
}

// MARK: - Border View

final class ScrollCaptureBorderView: NSView {
    private var dashPhase: CGFloat = 0
    /// Orange while the capture has lost track of the page (scrolled too fast).
    var isWarning = false {
        didSet { if isWarning != oldValue { needsDisplay = true } }
    }
    private nonisolated(unsafe) var animTimer: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        animTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.dashPhase += 2
                self?.needsDisplay = true
            }
        }
    }

    required init?(coder: NSCoder) { nil }

    deinit { animTimer?.invalidate() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let rect = bounds.insetBy(dx: 3, dy: 3)
        // Ein Akzent je App (Petrol statt Systemblau); Warnung bleibt orange.
        ctx.setStrokeColor((isWarning ? NSColor.systemOrange : NSColor(FamilyTheme.accentFill)).withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(isWarning ? 4 : 2.5)
        ctx.setLineDash(phase: dashPhase, lengths: [6, 4])
        ctx.stroke(rect)
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class ScrollCaptureViewModel {
    var previewImage: NSImage?
    var currentHeight: Int = 0
    var frameCount: Int = 0
    var isCapturing: Bool = false
    var isTrackingLost: Bool = false

    var statusText: String {
        if isTrackingLost {
            return String(localized: "Too fast – scroll back a little")
        }
        if !isCapturing {
            return String(localized: "Click Start, then scroll")
        }
        if frameCount == 0 {
            return String(localized: "Scroll slowly to capture")
        }
        return "\(currentHeight)px · \(frameCount) frames"
    }
}

// MARK: - Controls View

struct ScrollCaptureControlsView: View {
    let viewModel: ScrollCaptureViewModel
    let onStart: () -> Void
    let onAutoStart: () -> Void
    let onCancel: () -> Void
    let onDone: () -> Void

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Glas-Umbau Phase 3: schwebende Glas-Kapsel. Hauptaktion (Start/Fertig) als leuchtende
    // Akzent-Pille, Nebenaktionen leise; während der Aufnahme ein Akzent-Ring mit der Höhe.
    var body: some View {
        HStack(spacing: 6) {
            controlButton(icon: "xmark", label: String(localized: "Cancel"), isPrimary: false, action: onCancel)

            if viewModel.isCapturing {
                progressStatus
                controlButton(icon: "checkmark", label: String(localized: "Done"), isPrimary: true, action: onDone)
            } else {
                controlButton(icon: "arrow.down.to.line", label: String(localized: "Auto Scroll"),
                              isPrimary: false, action: onAutoStart)
                // Hauptaktion: accentFill trägt weiße Schrift (≥ 4,6 : 1), Grün nur 2,2 : 1.
                controlButton(icon: "play.fill", label: String(localized: "Start Capture"),
                              isPrimary: true, action: onStart)
            }
        }
        .captureGlassPill(readable: true)
        .familyAnimation(FamilyTheme.Motion.select, value: viewModel.isCapturing)
        .familyAnimation(FamilyTheme.Motion.select, value: viewModel.isTrackingLost)
        .captureAppear(appeared, reduceMotion: reduceMotion)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(FamilyTheme.Floating.edge)
        .onAppear {
            withAnimation(reduceMotion ? FamilyTheme.Motion.reduced : FamilyTheme.Motion.appear) { appeared = true }
        }
    }

    /// Läuft: Akzent-Ring dreht sich, daneben Höhe und Bildzahl (Ziffern weich).
    /// Zu schnell gescrollt: Warnung an derselben Stelle (die Vorschau fehlt, wenn die
    /// Auswahl den Bildschirm füllt – deshalb hier neben den Knöpfen).
    @ViewBuilder
    private var progressStatus: some View {
        if viewModel.isTrackingLost {
            Label(String(localized: "Too fast – scroll back a little"), systemImage: "exclamationmark.triangle.fill")
                .font(FamilyTheme.font(12, weight: .semibold))
                .foregroundStyle(FamilyTheme.warning)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .transition(.opacity)
        } else {
            HStack(spacing: 8) {
                ScrollCaptureActivityRing(isActive: viewModel.frameCount > 0)
                    .frame(width: 18, height: 18)
                Text(viewModel.frameCount == 0 ? viewModel.statusText : "\(viewModel.currentHeight) px")
                    .font(FamilyTheme.font(12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(FamilyTheme.textPrimary)
                    .contentTransition(.numericText())
                    .familyAnimation(.snappy(duration: 0.2), value: viewModel.currentHeight)
                    .lineLimit(1)
                if viewModel.frameCount > 0 {
                    Text(String(localized: "\(viewModel.frameCount) frames"))
                        .font(FamilyTheme.font(11, weight: .medium).monospacedDigit())
                        .foregroundStyle(FamilyTheme.textSecondary)
                        .contentTransition(.numericText())
                        .familyAnimation(.snappy(duration: 0.2), value: viewModel.frameCount)
                }
            }
            .padding(.horizontal, 8)
            .transition(.opacity)
        }
    }

    private func controlButton(icon: String, label: String, isPrimary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(label)
                    .font(FamilyTheme.font(13, weight: .semibold))
                    .fixedSize()
            }
            .foregroundStyle(isPrimary ? Color.white : FamilyTheme.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background {
                if isPrimary {
                    CaptureAccentPill()
                } else {
                    Capsule().fill(FamilyTheme.textPrimary.opacity(0.07))
                }
            }
            .captureHoverLift()
        }
        .buttonStyle(.plain)
    }
}

/// Akzent-Ring der Scroll-Aufnahme: dreht sich, solange Bilder ankommen (ohne
/// „Bewegung reduzieren“); sonst ein ruhiger, voller Ring.
private struct ScrollCaptureActivityRing: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: !isActive || reduceMotion)) { context in
            let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2 * 360
            ZStack {
                Circle().stroke(FamilyTheme.accent.opacity(0.22), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: isActive && !reduceMotion ? 0.3 : 1)
                    .stroke(FamilyTheme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(isActive && !reduceMotion ? angle : -90))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Preview View

struct ScrollCapturePreviewView: View {
    let viewModel: ScrollCaptureViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let image = viewModel.previewImage {
                // Scale-to-fit: show the entire captured image shrunk to fit the panel
                GeometryReader { geo in
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width)
                        .frame(maxHeight: geo.size.height, alignment: .top)
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 20))
                        .foregroundStyle(.tertiary)
                    Text(viewModel.statusText)
                        .font(FamilyTheme.font(11))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack {
                Text(viewModel.statusText)
                    .font(FamilyTheme.font(10, weight: .medium).monospacedDigit())
                    .foregroundStyle(FamilyTheme.textSecondary)
                    .contentTransition(.numericText())
                    .familyAnimation(.snappy(duration: 0.2), value: viewModel.currentHeight)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.bar)
        }
        // Vorschau ist Inhalt → feste Fläche statt Glas (G1).
        .background(FamilyTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: FamilyTheme.Floating.radius, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}

// App/Sources/Capture/SelfTimerHUD.swift
import AppKit
import SwiftUI
import SharedKit

/// Floating countdown overlay shown during a Self-Timer capture.
///
/// Visual design (see docs / design spec): rounded-square HUD using
/// `.regularMaterial` vibrancy, monochrome progress ring draining clockwise,
/// SF Rounded numeric digit driven by `.contentTransition(.numericText)`.
/// Adapts to light / dark with the system; never branded with accent color.
@MainActor
final class SelfTimerHUD {
    private var panel: SelfTimerPanel?
    private var borderPanel: NSPanel?
    private let viewModel = SelfTimerViewModel()
    private var keyMonitor: Any?
    private var escapeHotKey: ScrollCaptureEscapeHotKey?
    private var positionPersist: ((CGPoint) -> Void)?
    private var onCancel: (() -> Void)?
    private var playTickSound: Bool = false
    /// The running countdown. Cancelled synchronously on every cancel path so
    /// a cancel within the 160 ms fade-out cannot still fire the capture
    /// (audit C16, 21.11.).
    private var countdownTask: Task<Void, Never>?

    /// Reusable system "Tink" sound for per-second countdown ticks. Loaded
    /// once and stopped/restarted on each tick so consecutive ticks don't
    /// drop. The shutter sound at t=0 is fired by `CaptureCoordinator`, not
    /// here — we never tick on the final beat.
    private static let tickSound: NSSound? = NSSound(named: "Tink")

    /// Show the HUD on `screen` for `duration` seconds. Draws a thin
    /// monochrome border around `selectionRect` for the lifetime of the
    /// countdown so the user can see what's about to be captured. Calls
    /// `onComplete` once the countdown finishes — the caller is expected
    /// to immediately fire the capture. Calls `onCancel` on Esc / click.
    /// Both the HUD and the border are guaranteed to be off-screen
    /// *before* `onComplete` returns.
    func show(
        on screen: NSScreen,
        selectionRect: CGRect,
        duration: Int,
        playTickSound: Bool,
        savedPosition: CGPoint?,
        persistPosition: @escaping (CGPoint) -> Void,
        onComplete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        dismiss()  // guard against re-entrant show

        self.positionPersist = persistPosition
        self.onCancel = onCancel
        self.playTickSound = playTickSound
        viewModel.totalDuration = TimeInterval(duration)
        viewModel.startDate = Date()
        viewModel.remaining = duration

        showSelectionBorder(rect: selectionRect, screen: screen)

        // Die Kachel ist 108 pt; das Fenster ist ringsum um Floating.edge größer, damit der Schatten
        // nicht an der Fenstergrenze abgeschnitten wird. Gespeichert wird weiter die Kachelposition.
        let size = NSSize(width: 108, height: 108)
        let edge = FamilyTheme.Floating.edge
        let origin = Self.resolveOrigin(savedPosition: savedPosition, screen: screen, hudSize: size)
        let windowSize = NSSize(width: size.width + 2 * edge, height: size.height + 2 * edge)

        let panel = SelfTimerPanel(
            contentRect: NSRect(origin: NSPoint(x: origin.x - edge, y: origin.y - edge), size: windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false  // SwiftUI draws its own
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true

        let host = NSHostingView(rootView: SelfTimerHUDView(
            viewModel: viewModel,
            hudSize: size,
            onCancel: { [weak self] in self?.cancelByUser() },
            onDragEnded: { [weak self] newOrigin in
                self?.positionPersist?(CGPoint(x: newOrigin.x + edge, y: newOrigin.y + edge))
            }
        ))
        host.frame = NSRect(origin: .zero, size: windowSize)
        panel.contentView = host
        self.panel = panel

        installKeyMonitor()

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        }

        // Drive the visible digit on a 1Hz tick. The progress ring is driven
        // by TimelineView in SwiftUI for sub-second smoothness.
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            guard let self else { return }
            for tick in 1...duration {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled || self.panel == nil { return }
                let next = duration - tick
                withAnimation(.snappy(duration: 0.28)) {
                    self.viewModel.remaining = next
                }
                // Tick on every beat *except* the final one — at t=0 the
                // shutter sound from CaptureCoordinator takes over.
                if next > 0 && self.playTickSound {
                    Self.tickSound?.stop()
                    Self.tickSound?.play()
                }
            }
            // Tear down both panels synchronously, give the window server
            // two frames to ensure they're fully off-screen, then fire.
            self.dismissImmediate()
            try? await Task.sleep(for: .milliseconds(33))
            guard !Task.isCancelled else { return }
            self.countdownTask = nil
            onComplete()
        }
    }

    /// Draw a 2pt white border around `rect` on `screen`, with a soft black
    /// outer shadow so the border stays visible on any wallpaper. Sits at
    /// `.floating` level just below the HUD; ignores mouse events so the
    /// user can keep interacting with whatever they're capturing.
    private func showSelectionBorder(rect: CGRect, screen: NSScreen) {
        let inset: CGFloat = 4  // padding around the rect for the stroke + shadow
        let screenOrigin = screen.frame.origin
        let panelRect = NSRect(
            x: screenOrigin.x + rect.origin.x - inset,
            y: screenOrigin.y + rect.origin.y - inset,
            width: rect.width + inset * 2,
            height: rect.height + inset * 2
        )
        let panel = NSPanel(
            contentRect: panelRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false

        let view = SelfTimerBorderView(
            frame: NSRect(origin: .zero, size: panelRect.size),
            inset: inset
        )
        panel.contentView = view
        self.borderPanel = panel
        panel.orderFrontRegardless()
    }

    /// User-driven cancel (Esc / click). Animates out then calls onCancel.
    private func cancelByUser() {
        countdownTask?.cancel()
        countdownTask = nil
        let cb = onCancel
        animatedDismiss { cb?() }
    }

    /// Pull both panels down with no animation. Used when the timer fires —
    /// the screenshot must not see either panel, so this is synchronous.
    private func dismissImmediate() {
        if let mon = keyMonitor {
            NSEvent.removeMonitor(mon)
            keyMonitor = nil
        }
        escapeHotKey?.unregister()
        escapeHotKey = nil
        panel?.orderOut(nil)
        panel = nil
        borderPanel?.orderOut(nil)
        borderPanel = nil
    }

    /// Animate then tear down. Used for cancel paths. Uses a delayed
    /// `asyncAfter` for clean-up rather than `runAnimationGroup`'s
    /// completion handler — that closure is `@Sendable`, which doesn't play
    /// nicely with main-actor-isolated state. The pattern matches
    /// `CaptureCoordinator.dismissOverlay`.
    private func animatedDismiss(then completion: (() -> Void)? = nil) {
        guard let panel else { completion?(); return }
        if let mon = keyMonitor {
            NSEvent.removeMonitor(mon)
            keyMonitor = nil
        }
        escapeHotKey?.unregister()
        escapeHotKey = nil
        let border = borderPanel
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
            border?.animator().alphaValue = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            panel.orderOut(nil)
            border?.orderOut(nil)
            self?.panel = nil
            self?.borderPanel = nil
            completion?()
        }
    }

    /// External cancel (e.g., another capture flow starts). No callback fires.
    func dismiss() {
        countdownTask?.cancel()
        countdownTask = nil
        if let mon = keyMonitor {
            NSEvent.removeMonitor(mon)
            keyMonitor = nil
        }
        escapeHotKey?.unregister()
        escapeHotKey = nil
        panel?.orderOut(nil)
        panel = nil
        borderPanel?.orderOut(nil)
        borderPanel = nil
        onCancel = nil
        positionPersist = nil
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc
                self?.cancelByUser()
                return nil
            }
            return event
        }
        // The HUD never becomes key (the target app keeps focus, so its window stays active in
        // the shot), so the local monitor misses Esc. A system-wide hot key catches it, as in
        // the scrolling capture (audit C9, 21.11.).
        escapeHotKey = ScrollCaptureEscapeHotKey { [weak self] in self?.cancelByUser() }
    }

    /// Default placement: top-center of `screen`, 80pt below the menu bar /
    /// top edge. If the user has dragged before, restore that position
    /// clamped into the visible frame so a disconnected display can't trap
    /// the HUD off-screen.
    private static func resolveOrigin(savedPosition: CGPoint?, screen: NSScreen, hudSize: NSSize) -> NSPoint {
        if let saved = savedPosition {
            let visible = screensVisibleBounds()
            let x = max(visible.minX, min(saved.x, visible.maxX - hudSize.width))
            let y = max(visible.minY, min(saved.y, visible.maxY - hudSize.height))
            return NSPoint(x: x, y: y)
        }
        let frame = screen.visibleFrame
        let x = frame.midX - hudSize.width / 2
        let y = frame.maxY - hudSize.height - 80
        return NSPoint(x: x, y: y)
    }

    private static func screensVisibleBounds() -> NSRect {
        var union = NSRect.zero
        for s in NSScreen.screens {
            union = union.isEmpty ? s.visibleFrame : union.union(s.visibleFrame)
        }
        return union
    }
}

// MARK: - Panel (allows borderless windows to become key for Esc handling)

private final class SelfTimerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Selection border view

/// Draws a 2pt white border with a soft black outer shadow so the rect is
/// visible on bright, dark, and busy backgrounds alike. Static — no marching
/// ants — to keep the visual language quiet and consistent with the HUD.
private final class SelfTimerBorderView: NSView {
    private let inset: CGFloat

    init(frame: NSRect, inset: CGFloat) {
        self.inset = inset
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let rect = bounds.insetBy(dx: inset, dy: inset)

        ctx.saveGState()
        ctx.setShadow(
            offset: .zero,
            blur: 4,
            color: NSColor.black.withAlphaComponent(0.5).cgColor
        )
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.stroke(rect)
        ctx.restoreGState()
    }
}

// MARK: - View model

@MainActor
@Observable
final class SelfTimerViewModel {
    var totalDuration: TimeInterval = 5
    var startDate: Date = Date()
    var remaining: Int = 5
}

// MARK: - SwiftUI view

/// Intern statt privat: die Sichttest-Testkopie zeigt die Kachel ohne echten Countdown.
struct SelfTimerHUDView: View {
    let viewModel: SelfTimerViewModel
    let hudSize: NSSize
    let onCancel: () -> Void
    /// Called when a drag finishes, with the new bottom-left origin in screen
    /// coordinates (matching NSWindow.frame.origin convention).
    let onDragEnded: (CGPoint) -> Void

    @State private var isHovering = false
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Glas-Umbau Phase 3: schwebende Liquid-Glass-Kachel, Countdown groß mit weichem
    // Ziffernwechsel, Fortschritt als leuchtender Ring im Akzent. Überfahren zeigt „Abbrechen“.
    var body: some View {
        ZStack {
            // Progress ring + digit.
            TimelineView(.animation(paused: reduceMotion)) { context in
                let elapsed = context.date.timeIntervalSince(viewModel.startDate)
                // Bei „Bewegung reduzieren“ springt der Ring je Sekunde statt zu fließen.
                let shown = reduceMotion ? Double(viewModel.totalDuration) - Double(viewModel.remaining) : elapsed
                let progress = max(0, min(1, 1 - shown / viewModel.totalDuration))

                ZStack {
                    Circle()
                        .stroke(FamilyTheme.accent.opacity(0.18), lineWidth: 4)
                        .frame(width: 82, height: 82)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(FamilyTheme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 82, height: 82)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: FamilyTheme.accent.opacity(0.55), radius: 5)

                    Group {
                        if isHovering {
                            Image(systemName: "xmark")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(FamilyTheme.textSecondary)
                        } else {
                            Text("\(viewModel.remaining)")
                                .font(FamilyTheme.font(46, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(FamilyTheme.textPrimary)
                                .contentTransition(.numericText(countsDown: true))
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
        }
        .frame(width: hudSize.width, height: hudSize.height)
        .familyLiquidGlass(in: RoundedRectangle(cornerRadius: 30, style: .continuous),
                           tint: FamilyTheme.glassReadableTint)
        .scaleEffect(isHovering && !reduceMotion ? 1.03 : 1)
        .captureAppear(appeared, reduceMotion: reduceMotion)
        .overlay(WindowDragHandle(onTap: onCancel, onDragEnded: onDragEnded))
        .padding(FamilyTheme.Floating.edge)
        .onHover { hovering in
            withAnimation(reduceMotion ? FamilyTheme.Motion.reduced : FamilyTheme.Motion.hover) { isHovering = hovering }
        }
        .onAppear {
            withAnimation(reduceMotion ? FamilyTheme.Motion.reduced : FamilyTheme.Motion.appear) { appeared = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Self-timer countdown"))
        .accessibilityValue(Text("\(viewModel.remaining) seconds remaining"))
    }
}

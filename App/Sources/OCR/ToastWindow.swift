// App/Sources/OCR/ToastWindow.swift
import AppKit
import SwiftUI

/// A reusable Liquid Glass toast notification that slides up from bottom-center.
@MainActor
final class ToastWindow: NSPanel {
    private var dismissTimer: Timer?

    /// Übergang für ältere Aufrufer mit `NSColor`-Systemfarben: `.systemGreen` → `success`,
    /// `.systemYellow`/`.systemOrange` → `warning`, `.systemRed` → `danger` (FamilyTheme).
    convenience init(message: String, icon: String = "checkmark.circle.fill", iconColor: NSColor, screen: NSScreen? = nil) {
        self.init(message: message, icon: icon, tint: FamilyTheme.statusColor(for: iconColor), screen: screen)
    }

    init(message: String, icon: String = "checkmark.circle.fill", tint: Color = FamilyTheme.success, screen: NSScreen? = nil) {
        // The hosting view sizes the panel to its content, so center on that size.
        // The view carries a transparent Floating.edge around the capsule for its shadow.
        let hostingView = NSHostingView(rootView: ToastView(message: message, icon: icon, iconColor: tint))
        let windowWidth = hostingView.fittingSize.width
        let windowHeight = hostingView.fittingSize.height

        let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = targetScreen.visibleFrame
        let x = screenFrame.midX - windowWidth / 2
        // Kapsel bleibt wie bisher ~62 pt über dem unteren Rand; das Fenster ist um den Schattenrand größer.
        let y = screenFrame.minY + 62 - FamilyTheme.Floating.edge

        super.init(
            contentRect: NSRect(x: x, y: y, width: windowWidth, height: windowHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .transient]
        self.isMovableByWindowBackground = false
        self.animationBehavior = .utilityWindow

        self.contentView = hostingView
    }

    func show(autoDismissAfter: TimeInterval = 1.5) {
        // Die Kapsel federt in SwiftUI herein (ToastView.onAppear); das Fenster steht still.
        alphaValue = 1
        makeKeyAndOrderFront(nil)

        dismissTimer = Timer.scheduledTimer(withTimeInterval: autoDismissAfter, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.dismiss()
            }
        }
    }

    private func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
        })
    }
}

private struct ToastView: View {
    let message: String
    let icon: String
    let iconColor: Color
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(iconColor)
                // Häkchen „springt“ einmal, sobald der Hinweis da ist (nicht bei „Bewegung reduzieren“).
                .symbolEffect(.bounce.up.byLayer, options: .nonRepeating, value: appeared && !reduceMotion)
                .accessibilityHidden(true)
            Text(message)
                .font(FamilyTheme.font(13, weight: .medium))
                .foregroundStyle(FamilyTheme.textPrimary)
        }
        .fixedSize()
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        // Echtes Liquid Glass, leicht getönt (Desktop färbt nicht ein); kein Glas-Schatten.
        .familyLiquidGlass(in: Capsule(), tint: FamilyTheme.glassReadableTint)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.9)
        .offset(y: appeared || reduceMotion ? 0 : 10)
        .blur(radius: appeared || reduceMotion ? 0 : 4)
        .opacity(appeared ? 1 : 0)
        // Transparenter Rand wie bisher: Fenstergröße und Lage bleiben gleich.
        .padding(FamilyTheme.Floating.edge)
        .onAppear {
            withAnimation(reduceMotion ? FamilyTheme.Motion.reduced : FamilyTheme.Motion.appear) { appeared = true }
        }
    }
}

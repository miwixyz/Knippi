// App/Sources/Recording/RecordingControlsWindow.swift
import AppKit
import SwiftUI
import RecordingKit

@MainActor
final class RecordingControlsWindow: NSPanel {
    /// Sichtbare Leiste; das Fenster ist ringsum um `Floating.edge` größer (Schattenrand).
    static let barSize = CGSize(width: 264, height: 52)

    init(recordingFrame: CGRect, screen: NSScreen, recorder: ScreenRecorder, onTogglePause: @escaping () -> Void, onStop: @escaping () -> Void, onRestart: @escaping () -> Void, onDelete: @escaping () -> Void) {
        let width = Self.barSize.width
        let height = Self.barSize.height
        let edge = FamilyTheme.Floating.edge

        let screenFrame = screen.visibleFrame
        var x = recordingFrame.midX - width / 2
        var y = recordingFrame.minY - height - 18

        // If there isn't enough room below, place above the selection instead.
        if y < screenFrame.minY + 8 {
            y = recordingFrame.maxY + 18
        }

        // Clamp horizontally and vertically to the visible screen.
        x = max(screenFrame.minX + 8, min(x, screenFrame.maxX - width - 8))
        y = max(screenFrame.minY + 8, min(y, screenFrame.maxY - height - 8))

        super.init(
            contentRect: NSRect(x: x - edge, y: y - edge, width: width + 2 * edge, height: height + 2 * edge),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        // Halbtransparentes Glas: Schatten zeichnet die Ansicht im transparenten Rand.
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .transient]
        self.isMovableByWindowBackground = true
        self.sharingType = .none

        let view = RecordingControlsView(recorder: recorder, onTogglePause: onTogglePause, onStop: onStop, onRestart: onRestart, onDelete: onDelete)
        self.contentView = NSHostingView(rootView: view)
    }

    func show() { makeKeyAndOrderFront(nil) }
}

private struct RecordingControlsView: View {
    let recorder: ScreenRecorder
    let onTogglePause: () -> Void
    let onStop: () -> Void
    let onRestart: () -> Void
    let onDelete: () -> Void

    private var isPaused: Bool { recorder.state == .paused }
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(FamilyTheme.danger)
                    .frame(width: 28, height: 28)
                    .background(FamilyTheme.danger.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Stop recording")
            .accessibilityLabel(String(localized: "Stop recording"))

            // Pausiert: Zeit in Sekundärtext (≥ 4,5 : 1 auf der Glastönung) plus Pause-Symbol,
            // damit die Farbe nicht das einzige Signal ist. Läuft: Zeit in `danger` mit Punkt.
            HStack(spacing: 5) {
                Image(systemName: isPaused ? "pause.fill" : "circle.fill")
                    .font(.system(size: isPaused ? 10 : 8, weight: .bold))
                    // Aufnahmepunkt pulsiert, solange aufgenommen wird.
                    .symbolEffect(.pulse, options: .repeating, isActive: !isPaused && !reduceMotion)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 10)
                    .accessibilityHidden(true)
                Text(formatTime(recorder.elapsedTime))
                    .font(FamilyTheme.font(14, weight: .semibold).monospacedDigit())
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: false))
                    .familyAnimation(.snappy(duration: 0.25), value: Int(recorder.elapsedTime))
            }
            .foregroundStyle(isPaused ? FamilyTheme.textSecondary : FamilyTheme.danger)
            .frame(minWidth: 58, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityValue(isPaused ? String(localized: "Paused") : "")

            Rectangle().fill(FamilyTheme.cardStroke).frame(width: 1, height: 18)

            Button(action: onTogglePause) {
                barIcon(isPaused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(.plain)
            .help(isPaused ? "Resume recording" : "Pause recording")
            .accessibilityLabel(isPaused
                ? String(localized: "Resume recording")
                : String(localized: "Pause recording"))

            Button(action: onRestart) {
                barIcon("arrow.counterclockwise")
            }
            .buttonStyle(.plain)
            .help("Restart recording")
            .accessibilityLabel(String(localized: "Restart recording"))

            Button(action: onDelete) {
                barIcon("trash", secondary: true)
            }
            .buttonStyle(.plain)
            .help("Delete recording")
            .accessibilityLabel(String(localized: "Delete recording"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: RecordingControlsWindow.barSize.width, height: RecordingControlsWindow.barSize.height)
        // Liquid-Glass-Kapsel, lesbar getönt (Text dahinter schien bei 0,42 durch, gemessen 26.11.); Knöpfe darin bleiben feste Flächen (kein Glas auf Glas).
        .familyLiquidGlass(in: Capsule(), tint: FamilyTheme.glassReadableTint)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.92)
        .blur(radius: appeared || reduceMotion ? 0 : 4)
        .opacity(appeared ? 1 : 0)
        .padding(FamilyTheme.Floating.edge)
        .onAppear {
            withAnimation(reduceMotion ? FamilyTheme.Motion.reduced : FamilyTheme.Motion.appear) { appeared = true }
        }
    }

    /// Runder Leistenknopf: feste, leicht abgesetzte Fläche (kein Glas auf Glas).
    private func barIcon(_ name: String, secondary: Bool = false) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(secondary ? FamilyTheme.textSecondary : FamilyTheme.textPrimary)
            .frame(width: 28, height: 28)
            .background(FamilyTheme.textPrimary.opacity(0.08), in: Circle())
            .contentShape(Circle())
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

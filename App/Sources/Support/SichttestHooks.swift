// App/Sources/Support/SichttestHooks.swift
import AppKit
import ImageIO
import CaptureKit
import RecordingKit
import SharedKit

/// Messhilfen NUR für die Testkopie „Knippi Sichttest“ (`scripts/sichttest.sh`, eigene Kennung).
/// In der echten App (dev.mwlr.knippi) tut dieser Code nichts.
///
/// - `defaults write dev.mwlr.knippi.sichttest debugAppearance dark|light`
///   stellt nur die Testkopie auf Dunkel/Hell, ohne die Systemeinstellung anzufassen.
/// - `defaults write dev.mwlr.knippi.sichttest debugDemoSurfaces <png-pfad>`
///   zeigt beim Start Vorschaukarte, Hinweis und Aufnahmeleiste mit diesem Bild, damit die
///   schwebenden Flächen im echten Fenster fotografiert werden können (ohne Aufnahme,
///   ohne Bildschirmfreigabe, ohne Zwischenablage).
@MainActor
enum SichttestHooks {
    private static var isTestCopy: Bool { Bundle.main.bundleIdentifier == "dev.mwlr.knippi.sichttest" }
    private static var keepAlive: [AnyObject] = []

    static func apply(captureCoordinator: CaptureCoordinator?) {
        guard isTestCopy else { return }
        let defaults = UserDefaults.standard
        switch defaults.string(forKey: "debugAppearance") {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
        guard let path = defaults.string(forKey: "debugDemoSurfaces"),
              let captureCoordinator,
              let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let screen = NSScreen.main ?? NSScreen.screens.first!
            let result = CaptureResult(
                image: image, mode: .area,
                captureRect: CGRect(x: 0, y: 0, width: image.width, height: image.height),
                appName: "Sichttest", displayID: screen.displayID)
            captureCoordinator.showQuickAccess(for: result, entryID: UUID(), autoUpload: false)

            let toast = ToastWindow(message: String(localized: "Copied"),
                                    icon: "checkmark.circle.fill", tint: FamilyTheme.success, screen: screen)
            toast.show(autoDismissAfter: 60)
            let recorder = ScreenRecorder()
            let frame = screen.visibleFrame
            let bar = RecordingControlsWindow(
                recordingFrame: CGRect(x: frame.midX - 300, y: frame.midY - 100, width: 600, height: 300),
                screen: screen, recorder: recorder,
                onTogglePause: {}, onStop: {}, onRestart: {}, onDelete: {})
            // Nur hier: die echte Leiste ist von Bildschirmaufnahmen ausgenommen (sharingType .none),
            // für das Messfoto der Testkopie wird sie sichtbar gemacht.
            bar.sharingType = .readOnly
            bar.orderFrontRegardless()
            keepAlive = [toast, recorder, bar]
        }
    }
}

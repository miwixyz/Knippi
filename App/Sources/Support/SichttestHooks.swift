// App/Sources/Support/SichttestHooks.swift
import AppKit
import AVFoundation
import EditorKit
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
    /// Nur abgeschottete Testkopien (eigene Kennung unter dev.mwlr.knippi.*), nie die echte App.
    private static var isTestCopy: Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        return id.hasPrefix("dev.mwlr.knippi.") && id != "dev.mwlr.knippi"
    }
    private static var keepAlive: [AnyObject] = []
    private static var demoEditor: AnyObject?

    private static func openDemoEditor(url: URL) {
        Task { @MainActor in
            let asset = AVURLAsset(url: url)
            let duration = (try? await asset.load(.duration).seconds) ?? 0
            let tracks = try? await asset.loadTracks(withMediaType: .video)
            let size = (try? await tracks?.first?.load(.naturalSize)) ?? .zero
            let project = RecordingProject(sourceVideoURL: url, cursorTelemetryURL: nil, showsCursor: true,
                                           videoDuration: duration, videoSize: size, recordingAreaSize: size)
            let coordinator = EditorCoordinator(project: project, outputFormat: .mp4)
            let window = RecordingEditorWindow(coordinator: coordinator)
            demoEditor = window
            window.showCentered()
        }
    }

    static func apply(captureCoordinator: CaptureCoordinator?) {
        guard isTestCopy else { return }
        let defaults = UserDefaults.standard
        switch defaults.string(forKey: "debugAppearance") {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
        // `defaults write dev.mwlr.knippi.sichttest debugOpenSettings <tab>` (z. B. general, export)
        // öffnet beim Start die Einstellungen auf diesem Tab – zum Fotografieren des Fensters.
        if let raw = defaults.string(forKey: "debugOpenSettings") {
            let tab = PreferencesTab(rawValue: raw) ?? .general
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                NotificationCenter.default.post(name: .openPreferencesTab, object: tab)
            }
        }
        // `defaults write dev.mwlr.knippi.sichttest debugDemoEditor <video-pfad>` öffnet den
        // Video-Editor mit diesem Video (ohne Aufnahme). Kein onClose: die Datei bleibt liegen.
        if let videoPath = defaults.string(forKey: "debugDemoEditor") {
            openDemoEditor(url: URL(fileURLWithPath: videoPath))
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

    /// Glas-Umbau Phase 2 (nur Testkopien), gesetzt per `defaults write <kennung> …`:
    /// - `debugHistoryFolder <ordner>`: Ablage- und damit Verlaufsordner der TESTKOPIE auf einen
    ///   Scratch-Ordner mit Testbildern, Verlauf an (50), automatisch sichern an. `debugHistoryOff 1`
    ///   lässt den Verlauf dabei aus (für den Aus-Zustand).
    /// - `debugOpenPopover 1`: öffnet beim Start das Menüleisten-Fenster.
    /// - `debugPopoverRecording 1`: zeigt darin den Aufzeichnungsblock (ohne echte Aufnahme).
    /// - `debugHoverAction <id>`: Hover-Optik eines Aktionsknopfs und eines Verlaufs-Kärtchens ohne Zeiger.
    /// - `debugOpenHistory 1`: öffnet beim Start den Verlauf.
    static func menuBarReady(_ controller: MenuBarController, settings: AppSettings) {
        guard isTestCopy else { return }
        let defaults = UserDefaults.standard
        if let path = defaults.string(forKey: "debugHistoryFolder") {
            settings.setExportLocation(URL(fileURLWithPath: path, isDirectory: true))
            settings.screenshotAutoSave = true
            settings.historyKeepCount = defaults.bool(forKey: "debugHistoryOff") ? 0 : 50
        }
        if defaults.object(forKey: "debugHoverAction") != nil {
            let id = defaults.integer(forKey: "debugHoverAction")
            controller.popover.model.debugHoverAction = id
            HistoryDebug.forceHoverIndex = id
        }
        if defaults.object(forKey: "debugHistorySelect") != nil {
            HistoryDebug.selectIndex = defaults.integer(forKey: "debugHistorySelect")
        }
        if defaults.bool(forKey: "debugPopoverRecording") {
            let start = Date().addingTimeInterval(-83)
            controller.popover.model.currentRecording = { .init(elapsed: Date().timeIntervalSince(start), isPaused: false) }
        }
        let openPopover = defaults.bool(forKey: "debugOpenPopover")
        // Zum Fotografieren: Klicks anderswo (Michael arbeitet nebenher) schließen es nicht.
        controller.popover.ignoresOutsideClicks = openPopover
        let openHistory = defaults.bool(forKey: "debugOpenHistory")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if openHistory { controller.showHistory() }
        }
        // Später als der Verlauf: dessen Aktivierung würde das Fenster sonst gleich wieder schließen.
        DispatchQueue.main.asyncAfter(deadline: .now() + (openHistory ? 3.5 : 1.5)) {
            if openPopover { controller.showPopover() }
        }
    }
}

/// Messhilfe für den Verlauf (nur von `SichttestHooks` gesetzt): diese Karte zeigt die Hover-Optik.
@MainActor
enum HistoryDebug {
    static var forceHoverIndex: Int?
    /// Diese Karte (Index in der Trefferliste) wird beim ersten Füllen ausgewählt.
    static var selectIndex: Int?
}

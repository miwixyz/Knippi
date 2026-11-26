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
            guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
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

// MARK: - Glas-Umbau Phase 3: Oberflächen rund ums Aufnehmen (nur Testkopien)

import SwiftUI

extension SichttestHooks {
    private static var captureDemoKeepAlive: [AnyObject] = []

    /// `defaults write <kennung> debugDemoCaptureSurfaces <n>` zeigt die Aufnahme-Oberflächen ohne
    /// echte Aufnahme, ohne Bildschirmfreigabe und ohne globale Esc-Kurztaste (Michael arbeitet nebenher):
    /// - `1`: Aufnahme-Werkzeugleiste, Modus-Auswahl, Aufzeichnungsleiste, Scroll-Leiste (bereit und
    ///   laufend) samt Vorschau, Selbstauslöser-Kachel und ein angeheftetes Testbild mit Hover-Kapsel.
    /// - `2`: Alles-in-einem-Leiste waagerecht (ohne eingefrorenes Bild) samt Auswahl.
    /// - `3`: Alles-in-einem mit eingefrorenem Bild: Seitenleiste plus Annotationsleiste.
    /// Zusatz: `debugDemoImage <png>` (Testbild), `debugHoverMode <i>` (Aufnahmeart als überfahren),
    /// `debugDemoSeconds <s>` (Alles-in-einem schließt sich danach selbst, Standard 45 s – das
    /// Auswahl-Overlay deckt den Bildschirm ab).
    static func demoCaptureSurfaces(settings: AppSettings) {
        guard isTestCopy else { return }
        let defaults = UserDefaults.standard
        let variant = defaults.integer(forKey: "debugDemoCaptureSurfaces")
        guard variant > 0 else { return }
        if defaults.object(forKey: "debugHoverMode") != nil {
            CaptureSurfacesDebug.hoveredModeIndex = defaults.integer(forKey: "debugHoverMode")
        }
        let image = defaults.string(forKey: "debugDemoImage").flatMap { path -> CGImage? in
            guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        let seconds = defaults.object(forKey: "debugDemoSeconds") != nil ? defaults.double(forKey: "debugDemoSeconds") : 45
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
            switch variant {
            case 2, 3: showAllInOneDemo(screen: screen, image: variant == 3 ? image : nil, seconds: seconds)
            default: showCaptureIslands(screen: screen, image: image, settings: settings)
            }
        }
    }

    private static func showAllInOneDemo(screen: NSScreen, image: CGImage?, seconds: Double) {
        let local = CGRect(x: screen.frame.width * 0.28, y: screen.frame.height * 0.36,
                           width: screen.frame.width * 0.32, height: screen.frame.height * 0.4)
        // Eingefrorenes „Bildschirmbild“: das Testbild auf Bildschirmgröße gezogen.
        let frozen = image.flatMap { scaled($0, to: screen.frame.size, scale: screen.backingScaleFactor) }
        let toolbar = CaptureAllInOneToolbarWindow(selectionRect: local, screen: screen,
                                                   presets: [.freeform], activePreset: .freeform, frozenImage: frozen)
        toolbar.onCancel = { [weak toolbar] in toolbar?.close() }
        toolbar.show()
        captureDemoKeepAlive.append(toolbar)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak toolbar] in toolbar?.close() }
    }

    private static func showCaptureIslands(screen: NSScreen, image: CGImage?, settings: AppSettings) {
        let visible = screen.visibleFrame
        var keep: [AnyObject] = []
        func reveal(_ window: NSWindow) {
            // Manche Flächen sind von Bildschirmaufnahmen ausgenommen – nur hier fürs Messfoto sichtbar.
            window.sharingType = .readOnly
            window.orderFrontRegardless()
            keep.append(window)
        }

        // Aufnahme-Werkzeugleiste (vor dem Start), links.
        let area = CGRect(x: visible.minX + 60, y: visible.midY - 200, width: 420, height: 400)
        let recordingToolbar = RecordingToolbarWindow(
            selectionRect: area, screen: screen, settings: settings,
            onRecord: { _, _, _, _, _ in }, onCameraToggled: { _, _ in false },
            onChangeArea: {}, onCancel: {}, onCameraSettingsChanged: {})
        reveal(recordingToolbar)

        // Modus-Auswahl oben mittig.
        let modeRail = RecordingSelectionModeWindow(screen: screen, selectedMode: .window, canUseLastArea: true,
                                                    onSelect: { _ in }, onCancel: {})
        reveal(modeRail)

        // Aufzeichnungsleiste unter der Werkzeugleiste.
        let recorder = ScreenRecorder()   // Ruhezustand: Leiste zeigt „läuft“ (nicht pausiert)
        keep.append(recorder)
        let controls = RecordingControlsWindow(
            recordingFrame: CGRect(x: area.minX, y: visible.minY + 260, width: 420, height: 10), screen: screen,
            recorder: recorder, onTogglePause: {}, onStop: {}, onRestart: {}, onDelete: {})
        reveal(controls)

        // Scroll-Leiste bereit und laufend, plus Vorschau.
        let edge = FamilyTheme.Floating.edge
        let idleModel = ScrollCaptureViewModel()
        let runningModel = ScrollCaptureViewModel()
        runningModel.isCapturing = true
        runningModel.currentHeight = 4_280
        runningModel.frameCount = 23
        if let image { runningModel.previewImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)) }
        keep += [idleModel, runningModel]
        for (index, model) in [idleModel, runningModel].enumerated() {
            let rect = CGRect(x: visible.minX + 560, y: visible.minY + 120 + CGFloat(index) * 90, width: 460, height: 52)
            let panel = demoPanel(rect.insetBy(dx: -edge, dy: -edge), ScrollCaptureControlsView(
                viewModel: model, onStart: {}, onAutoStart: {}, onCancel: {}, onDone: {}))
            reveal(panel)
        }
        let preview = demoPanel(CGRect(x: visible.minX + 1060, y: visible.minY + 120, width: 180, height: 300),
                                ScrollCapturePreviewView(viewModel: runningModel), shadow: true)
        reveal(preview)

        // Selbstauslöser-Kachel (ohne Countdown, ohne Esc-Kurztaste).
        let timer = SelfTimerViewModel()
        // Sehr lange Gesamtdauer: der Ring steht fürs Foto bei gut zwei Dritteln.
        timer.totalDuration = 36_000
        timer.startDate = Date().addingTimeInterval(-11_500)
        timer.remaining = 7
        keep.append(timer)
        let tileSize = NSSize(width: 108, height: 108)
        let timerPanel = demoPanel(
            CGRect(x: visible.minX + 1300 - edge, y: visible.minY + 120 - edge,
                   width: tileSize.width + 2 * edge, height: tileSize.height + 2 * edge),
            SelfTimerHUDView(viewModel: timer, hudSize: tileSize, onCancel: {}, onDragEnded: { _ in }))
        reveal(timerPanel)

        // Angeheftetes Testbild mit Hover-Kapsel (Mitte rechts).
        if let image {
            let pin = PinnedScreenshotController(image: image, anchorRect: nil, activatesApp: false,
                                                 onCopy: {}, onSave: {}, onDidClose: { _ in })
            pin.show()
            pin.showControlsForSichttest()
            keep.append(pin)
        }
        captureDemoKeepAlive = keep
    }

    private static func demoPanel<V: View>(_ frame: CGRect, _ view: V, shadow: Bool = false) -> NSPanel {
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = shadow
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: view)
        return panel
    }

    private static func scaled(_ image: CGImage, to size: CGSize, scale: CGFloat) -> CGImage? {
        let width = Int(size.width * scale), height = Int(size.height * scale)
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Ruhiger Schreibtisch, Testbild in Originalgröße mittig (nicht verzerrt).
        ctx.setFillColor(CGColor(srgbRed: 0.45, green: 0.55, blue: 0.68, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let w = CGFloat(image.width) * scale, h = CGFloat(image.height) * scale
        ctx.draw(image, in: CGRect(x: (CGFloat(width) - w) / 2, y: (CGFloat(height) - h) / 2, width: w, height: h))
        return ctx.makeImage()
    }
}

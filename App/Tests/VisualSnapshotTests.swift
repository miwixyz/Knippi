// App/Tests/VisualSnapshotTests.swift
//
// Messwerkzeug, kein Regressionstest: rendert die wichtigsten Oberflächen als PNG
// (hell und dunkel), damit die Optik ohne Bildschirmaufnahme beurteilt werden kann.
//
// Läuft nur, wenn KNIPPI_SNAPSHOT_DIR gesetzt ist; sonst XCTSkip, `make test` bleibt schnell.
//
//   xcodebuild … test -only-testing:KnippiTests/VisualSnapshotTests \
//     -testLanguage de -testRegion DE TEST_RUNNER_KNIPPI_SNAPSHOT_DIR=/pfad/zum/ordner
//
// Schreibt `<name>-light.png` / `<name>-dark.png`, `menubar-menu.txt` und `_info.txt`.
// Echte Einstellungen bleiben unberührt: eigene UserDefaults-Suite, eigener
// Verlaufsordner und Suchindex, eigener Upload-Speicher.

import AnnotationKit
import AppKit
import CoreText
import OCRKit
import SharedKit
import ShareKit
import SwiftUI
import XCTest
@testable import Knippi
@testable import RecordingKit

@MainActor
final class VisualSnapshotTests: XCTestCase {

    private var outDir: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var settings: AppSettings!
    private var scratch: URL!

    private enum Look: CaseIterable {
        case light, dark
        var suffix: String { self == .light ? "light" : "dark" }
        var appearance: NSAppearance { NSAppearance(named: self == .light ? .aqua : .darkAqua)! }
        var scheme: ColorScheme { self == .light ? .light : .dark }
        /// Neutraler "Schreibtisch" hinter frei schwebenden Elementen.
        var backdrop: NSColor {
            self == .light ? NSColor(srgbRed: 0.84, green: 0.86, blue: 0.89, alpha: 1)
                           : NSColor(srgbRed: 0.17, green: 0.18, blue: 0.21, alpha: 1)
        }
    }

    // MARK: Setup

    override func setUpWithError() throws {
        guard let dir = ProcessInfo.processInfo.environment["KNIPPI_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("KNIPPI_SNAPSHOT_DIR nicht gesetzt – Snapshot-Messung übersprungen")
        }
        outDir = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        FamilyTheme.app = .knippi
        _ = FamilyTheme.registerFonts(bundle: .main)

        suiteName = "dev.mwlr.knippi.snapshots.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        settings = AppSettings(defaults: defaults)

        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("knippi-snapshots-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let suiteName { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        if let scratch { try? FileManager.default.removeItem(at: scratch) }
    }

    // MARK: 0) Umgebung

    func test00Environment() throws {
        let families = (CTFontManagerCopyAvailableFontFamilyNames() as? [String]) ?? []
        let lines = [
            "Datum: \(Date())",
            "Plus Jakarta Sans registriert: \(families.contains(FamilyTheme.fontFamily))",
            "Locale.current: \(Locale.current.identifier)",
            "Bundle.main.preferredLocalizations: \(Bundle.main.preferredLocalizations)",
            "AppleLanguages: \(UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? [])",
            "Probe String(localized: \"General\"): \(String(localized: "General"))",
            "Probe String(localized: \"Knippi Settings\"): \(String(localized: "Knippi Settings"))",
            "FeatureFlags.screenRecording: \(FeatureFlags.screenRecording)",
            "CGPreflightScreenCaptureAccess: \(CGPreflightScreenCaptureAccess())",
        ]
        try lines.joined(separator: "\n").appending("\n")
            .write(to: outDir.appendingPathComponent("_info.txt"), atomically: true, encoding: .utf8)
    }

    // MARK: 1) Einstellungen – jeder Tab

    func test01PreferencesTabs() throws {
        let updateManager = UpdateManager(updater: FakeSoftwareUpdater())
        // Der Rechte-Tab fragt beim Erscheinen SCShareableContent ab; ohne Freigabe könnte
        // das eine Systemabfrage auslösen. Dann nur per ImageRenderer (kein .task).
        let permissionsSafe = CGPreflightScreenCaptureAccess()

        for tab in PreferencesTab.visibleCases {
            let viewModel = PreferencesViewModel(settings: settings, permissionManager: PermissionManager())
            let useRenderer = tab == .permissions && !permissionsSafe

            // a) Fenster wie beim Nutzer (PreferencesView.windowSize, Inhalt scrollt)
            let window = { AnyView(PreferencesView(viewModel: viewModel, updateManager: updateManager, initialTab: tab)) }
            if useRenderer {
                // ImageRenderer zeichnet ScrollView-Inhalt nicht – Fensteransicht entfällt, nur "-full".
            } else {
                snapshot("prefs-\(tab.rawValue)", size: PreferencesView.windowSize, settle: 0.6, make: window)
            }

            // b) Ganzer Tab-Inhalt ohne Scroll-Beschnitt (Inhaltsbreite wie im Fenster: 499 pt)
            let full = {
                AnyView(
                    VStack(alignment: .leading, spacing: 0) { Self.tabContent(tab, viewModel, updateManager) }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 24)
                        .frame(width: 499, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(FamilyTheme.backgroundGradient)
                )
            }
            if useRenderer {
                snapshotRenderer("prefs-\(tab.rawValue)-full", size: nil, make: full)
            } else {
                snapshot("prefs-\(tab.rawValue)-full", size: nil, settle: 0.6, fitWidth: 499, make: full)
            }
        }
    }

    @ViewBuilder
    private static func tabContent(_ tab: PreferencesTab, _ vm: PreferencesViewModel, _ um: UpdateManager) -> some View {
        switch tab {
        case .general: GeneralSettingsView(viewModel: vm, updateManager: um)
        case .permissions: PermissionSettingsView(viewModel: vm)
        case .screenshots: ScreenshotSettingsView(viewModel: vm)
        case .recording: RecordingSettingsView(viewModel: vm)
        case .quickAccess: QuickAccessSettingsView(viewModel: vm)
        case .cloudShare: CloudShareSettingsView(viewModel: vm)
        case .export: ExportSettingsView(viewModel: vm)
        case .ocr: OCRSettingsView(viewModel: vm)
        case .shortcuts: ShortcutSettingsView(viewModel: vm)
        }
    }

    // MARK: 2) Annotation: Werkzeugleiste und Editor

    func test02AnnotationToolbar() throws {
        let thumb = NSImage(cgImage: Self.testImage(width: 800, height: 500), size: NSSize(width: 200, height: 125))
        for (name, tool) in [("annotation-toolbar", AnnotationTool.arrow), ("annotation-toolbar-text", .text), ("annotation-toolbar-pixelate", .pixelate)] {
            snapshot(name, size: nil, padding: 16, backdrop: true) {
                AnyView(
                    AnnotationToolbar(
                        currentTool: .constant(tool),
                        currentColor: .constant(.red),
                        lineWidth: .constant(tool == .text ? 48 : 3),
                        strokePattern: .constant(.solid),
                        arrowHead: .constant(.standard),
                        filled: .constant(false),
                        textFillEnabled: .constant(false),
                        textOutlineEnabled: .constant(false),
                        textStrokeEnabled: .constant(true),
                        redactionMode: .constant(.pixelate),
                        showBeautifyPanel: .constant(false),
                        canUndo: true,
                        canRedo: false,
                        onUndo: {}, onRedo: {}, onSave: {}, onCopy: {}, onPin: {},
                        dragThumbnail: thumb,
                        onPrepareDrag: {},
                        onDragFileURL: { nil },
                        onDragPreviewImage: { nil },
                        onDragStarted: {}, onDragEnded: {},
                        isDragDisabled: false,
                        onCancel: {}, onCrop: {}
                    )
                )
            }
        }
    }

    func test03AnnotationEditor() throws {
        let image = Self.testImage(width: 1600, height: 1000)
        for (name, size) in [("annotation-editor", CGSize(width: 1180, height: 820)),
                             ("annotation-editor-wide", CGSize(width: 1840, height: 1100))] {
        snapshot(name, size: size, settle: 1.0) {
            let document = AnnotationDocument(imageSize: CGSize(width: image.width, height: image.height))
            document.addObjects([
                ArrowObject(start: CGPoint(x: 1150, y: 760), end: CGPoint(x: 820, y: 520), style: StrokeStyle(color: .red, lineWidth: 6)),
                RectangleObject(rect: CGRect(x: 180, y: 300, width: 520, height: 200), style: StrokeStyle(color: .blue, lineWidth: 5)),
                CounterObject(center: CGPoint(x: 160, y: 280), number: 1, style: StrokeStyle(color: .orange)),
            ])
            return AnyView(
                AnnotationEditorView(
                    sourceImage: image,
                    document: document,
                    sourceAppName: "Safari",
                    sourceWindowTitle: "Beispielseite",
                    captureDate: Date(timeIntervalSince1970: 1_780_000_000),
                    screenshotOutput: self.settings.screenshotOutputOptions,
                    screenshotFilenameTemplate: self.settings.screenshotFilenameTemplate,
                    onSave: { _ in }, onSaveAs: { _ in }, onCopy: { _ in }, onPin: { _ in },
                    onDragStarted: {}, onDragEnded: {}, onCancel: {}
                )
            )
        }
        }
    }

    // MARK: 3) Quick-Access-Vorschaukarte

    func test04QuickAccess() throws {
        let image = Self.testImage(width: 1920, height: 1080)
        let thumb = NSImage(cgImage: image, size: NSSize(width: 536, height: 302))

        func card(share: ShareCoordinator?, autoUpload: Bool) -> AnyView {
            AnyView(QuickAccessView(
                thumbnail: thumb,
                captureImage: image,
                dimensions: "1920×1080",
                capturedAt: Date().addingTimeInterval(-40),
                sourceAppName: "Safari",
                sourceWindowTitle: "Beispielseite – Knippi Testbild",
                screenshotOutput: settings.screenshotOutputOptions,
                screenshotFilenameTemplate: settings.screenshotFilenameTemplate,
                shareCoordinator: share,
                autoUpload: autoUpload,
                onCopy: {}, onSave: {}, onSaveAs: {}, onAnnotate: {}, onFindSensitive: {},
                onOCR: {}, onPin: {}, onPreview: {}, onDragStarted: {}, onDragEnded: { _ in },
                onHoverChanged: { _ in }, onClose: {}
            ))
        }
        let records = { UploadRecordStore(fileURL: self.scratch.appendingPathComponent("uploads-\(UUID().uuidString).json")) }

        // Ruhezustand (Bildunterschrift)
        snapshot("quickaccess", size: nil, padding: 28, backdrop: true) { card(share: nil, autoUpload: false) }
        // Mit Hover/Fokus (Werkzeugleiste sichtbar) – per Fokus/Mausbewegung ausgelöst
        snapshot("quickaccess-hover", size: nil, padding: 28, backdrop: true, settle: 0.8, interact: Self.revealByPointer) {
            card(share: ShareCoordinator(destination: HangingDestination(), uploadRecords: records()), autoUpload: false)
        }
        // Hochladen läuft
        snapshot("quickaccess-uploading", size: nil, padding: 28, backdrop: true, settle: 0.8, interact: Self.revealByPointer) {
            card(share: ShareCoordinator(destination: HangingDestination(), uploadRecords: records()), autoUpload: true)
        }
        // Hochladen gescheitert
        snapshot("quickaccess-failed", size: nil, padding: 28, backdrop: true, settle: 1.2) {
            card(share: ShareCoordinator(destination: FailingDestination(), uploadRecords: records()), autoUpload: true)
        }
    }

    /// Bewegt einen künstlichen Mauszeiger über die Mitte und gibt dem Inhalt den Fokus.
    private static func revealByPointer(_ window: NSWindow, _ host: NSView) {
        window.makeKey()
        window.makeFirstResponder(host)
        let center = NSPoint(x: window.frame.width / 2, y: window.frame.height / 2)
        for type in [NSEvent.EventType.mouseMoved, .mouseMoved] {
            if let event = NSEvent.mouseEvent(with: type, location: center, modifierFlags: [],
                                              timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil,
                                              eventNumber: 0, clickCount: 0, pressure: 0) {
                window.sendEvent(event)
            }
        }
    }

    // MARK: 4) Aufnahme-Bedienleiste

    func test05RecordingControls() throws {
        let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first)
        for (name, paused) in [("recording-controls", false), ("recording-controls-paused", true)] {
            let barSize = RecordingControlsWindow.barSize
            let edge = FamilyTheme.Floating.edge
            snapshotView(name, size: CGSize(width: barSize.width + 2 * edge, height: barSize.height + 2 * edge), padding: 0) {
                let recorder = ScreenRecorder()
                recorder.state = paused ? .paused : .recording
                let panel = RecordingControlsWindow(
                    recordingFrame: CGRect(x: 200, y: 300, width: 800, height: 500), screen: screen,
                    recorder: recorder, onTogglePause: {}, onStop: {}, onRestart: {}, onDelete: {})
                let content = panel.contentView!
                panel.contentView = NSView()
                panel.close()
                return (content, recorder)
            }
        }
    }

    // MARK: 4b) Schwebende Leisten und Hinweise

    func test05bFloatingSurfaces() throws {
        // Werkzeugleiste vor der Aufnahme (Bereich gewählt)
        snapshot("recording-toolbar", size: nil, backdrop: true) {
            AnyView(RecordingToolbarView(
                width: 1920, height: 1080,
                cameraEnabled: .constant(false), selectedCameraID: .constant(nil),
                micEnabled: .constant(true), systemAudioEnabled: .constant(true),
                settings: self.settings,
                onRecordVideo: {}, onRecordGIF: {}, onChangeArea: {}, onCancel: {}, onCameraSettingsChanged: {}))
        }
        // Hinweis (Toast) – Inhalt des Panels
        let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first)
        for (name, icon, color) in [("toast-success", "checkmark.circle.fill", NSColor.systemGreen),
                                    ("toast-warning", "exclamationmark.triangle.fill", NSColor.systemOrange)] {
            let probe = ToastWindow(message: "Probe", icon: icon, iconColor: color, screen: screen)
            let size = probe.frame.size
            probe.close()
            snapshotView(name, size: CGSize(width: 520, height: size.height), padding: 0) {
                let toast = ToastWindow(message: name == "toast-success" ? "In die Zwischenablage kopiert"
                                                                         : "Konnte das Bildschirmfoto nicht vorbereiten",
                                        icon: icon, iconColor: color, screen: screen)
                let content = toast.contentView!
                toast.contentView = NSView()
                toast.close()
                return (content, toast)
            }
        }
    }

    // MARK: 5) Verlauf

    func test06History() throws {
        let shots = scratch.appendingPathComponent("shots", isDirectory: true)
        try FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
        let titles = ["Rechnung November", "Fahrplan S-Bahn", "Kalender Woche 48", "Notizen Meeting",
                      "Fehlermeldung Xcode", "Wetter München"]
        for (i, title) in titles.enumerated() {
            let img = Self.testImage(width: 1280, height: 800, title: title, hue: CGFloat(i) / CGFloat(titles.count))
            let url = shots.appendingPathComponent("Knippi \(i).png")
            try NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!.write(to: url)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-Double(i) * 3600)],
                                                  ofItemAtPath: url.path)
        }
        settings.setExportLocation(shots)
        settings.historyKeepCount = 50
        settings.screenshotAutoSave = true

        let index = SearchIndex(fileURL: scratch.appendingPathComponent("index/SearchIndex.json"),
                                recognizer: { _ in "" })
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("knippi.snapshots.\(UUID().uuidString)"))
        let store = HistoryStore(settings: settings, index: index, pasteboard: pasteboard,
                                 trash: { _ in nil }, restore: { _, _ in }, openInEditor: { _ in })
        store.activate()
        pump(until: { store.items.count == titles.count }, timeout: 8)
        if let second = store.items.dropFirst().first { store.click(second, extend: false) }

        snapshot("history", size: CGSize(width: 640, height: 520), settle: 1.5) { AnyView(HistoryView(store: store)) }
        store.deactivate()

        // Ausgeschaltet
        let offDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName + ".off"))
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName + ".off") }
        let offSettings = AppSettings(defaults: offDefaults)
        offSettings.historyKeepCount = 0
        let offStore = HistoryStore(settings: offSettings, index: index, pasteboard: pasteboard,
                                    trash: { _ in nil }, restore: { _, _ in }, openInEditor: { _ in })
        snapshot("history-off", size: CGSize(width: 640, height: 520)) { AnyView(HistoryView(store: offStore)) }
    }

    // MARK: 6) Menüleisten-Menü als Text

    func test07MenuBarMenu() throws {
        settings.showMenuBarIcon = true
        let capture = CaptureCoordinator(settings: settings)
        let recording = RecordingCoordinator(settings: settings)
        let ocr = OCRCoordinator(settings: settings)
        let controller = MenuBarController(
            settings: settings, captureCoordinator: capture, recordingCoordinator: recording,
            ocrCoordinator: ocr, desktopIconsCover: DesktopIconsCover(),
            updateManager: UpdateManager(updater: FakeSoftwareUpdater()), onShowPreferences: {})

        let statusItem = Mirror(reflecting: controller).children
            .first { $0.label == "statusItem" }?.value as? NSStatusItem
        // Seit dem Glas-Popover (Phase 2) hängt das klassische Menü nicht mehr dauerhaft am Status-Item,
        // sondern öffnet sich per Rechtsklick/⌥-Klick und über „Mehr“.
        XCTAssertNil(statusItem?.menu, "Linksklick soll das Popover öffnen, nicht das Menü")
        let classic = Mirror(reflecting: controller).children.first { $0.label == "classicMenu" }?.value as? NSMenu
        let menu = try XCTUnwrap(classic, "Klassisches Menü nicht erreichbar")
        menu.delegate?.menuWillOpen?(menu)

        var lines: [String] = ["# Knippi Menüleisten-Menü (Zustand nach menuWillOpen, ohne Pins/Quick Access)",
                               "# [versteckt] = isHidden, [aus] = deaktiviert, ✓ = state on", ""]
        func dump(_ menu: NSMenu, depth: Int) {
            menu.delegate?.menuNeedsUpdate?(menu)
            for item in menu.items {
                let indent = String(repeating: "    ", count: depth)
                if item.isSeparatorItem { lines.append(indent + "———"); continue }
                var flags: [String] = []
                if item.isHidden { flags.append("[versteckt]") }
                if !item.isEnabled { flags.append("[aus]") }
                let check = item.state == .on ? "✓ " : ""
                let key = Self.shortcutText(item)
                lines.append("\(indent)\(check)\(item.title)\(key.isEmpty ? "" : "    \(key)")\(flags.isEmpty ? "" : "  " + flags.joined(separator: " "))")
                if let sub = item.submenu { dump(sub, depth: depth + 1) }
            }
        }
        dump(menu, depth: 0)
        try lines.joined(separator: "\n").appending("\n")
            .write(to: outDir.appendingPathComponent("menubar-menu.txt"), atomically: true, encoding: .utf8)

        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        settings.showMenuBarIcon = false
    }

    private static func shortcutText(_ item: NSMenuItem) -> String {
        guard !item.keyEquivalent.isEmpty else { return "" }
        let m = item.keyEquivalentModifierMask
        var s = ""
        if m.contains(.control) { s += "control-" }
        if m.contains(.option) { s += "option-" }
        if m.contains(.shift) { s += "shift-" }
        if m.contains(.command) { s += "command-" }
        return s + item.keyEquivalent.uppercased()
    }

    // MARK: - Render-Werkzeuge

    private func pump(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func pump(until condition: () -> Bool, timeout: TimeInterval) {
        let end = Date().addingTimeInterval(timeout)
        while !condition() && Date() < end { pump(0.05) }
    }

    /// SwiftUI-Ansicht in einem Fenster außerhalb des Bildschirms rendern (AppKit-Steuerelemente inklusive).
    private func snapshot(
        _ name: String, size: CGSize?, padding: CGFloat = 0, backdrop: Bool = false, settle: TimeInterval = 0.5,
        fitWidth: CGFloat? = nil, interact: ((NSWindow, NSView) -> Void)? = nil, make: () -> AnyView
    ) {
        for look in Look.allCases {
            let root = make()
                .defaultAppStorage(defaults)
                .environment(\.colorScheme, look.scheme)
            let host = NSHostingView(rootView: root)
            var target = size
            if size == nil, let fitWidth {
                // Höhe für feste Breite messen (fittingSize liefert hier zu viel Luft).
                let fit = NSHostingController(rootView: root)
                    .sizeThatFits(in: CGSize(width: fitWidth, height: 20_000))
                // Gierige Ansichten (maxHeight: .infinity) melden die volle Vorschlagshöhe – deckeln,
                // durchsichtige Ränder werden danach abgeschnitten.
                target = CGSize(width: fitWidth, height: min(ceil(fit.height), 6_000))
            }
            render(name, look: look, content: host, size: target, padding: padding, backdrop: backdrop,
                   settle: settle, interact: interact)
        }
    }

    /// Fertige NSView (z. B. Inhalt eines Panels) rendern. `keepAlive` hält Modelle am Leben.
    private func snapshotView(_ name: String, size: CGSize, padding: CGFloat, make: () -> (NSView, AnyObject)) {
        for look in Look.allCases {
            let (view, keepAlive) = make()
            render(name, look: look, content: view, size: size, padding: padding, backdrop: true, settle: 0.4, interact: nil)
            withExtendedLifetime(keepAlive) {}
        }
    }

    private func render(
        _ name: String, look: Look, content: NSView, size: CGSize?, padding: CGFloat, backdrop: Bool,
        settle: TimeInterval, interact: ((NSWindow, NSView) -> Void)?
    ) {
        let contentSize = size ?? content.fittingSize
        let outer = NSSize(width: ceil(contentSize.width + 2 * padding), height: ceil(contentSize.height + 2 * padding))
        let container = BackdropView(frame: NSRect(origin: .zero, size: outer))
        container.fill = backdrop ? look.backdrop : nil
        content.frame = NSRect(x: padding, y: padding, width: contentSize.width, height: contentSize.height)
        container.addSubview(content)

        let window = SnapshotWindow(contentRect: NSRect(x: -40_000, y: -40_000, width: outer.width, height: outer.height),
                                    styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = look.appearance
        window.backgroundColor = backdrop ? look.backdrop : .windowBackgroundColor
        window.contentView = container
        window.orderFrontRegardless()
        container.layoutSubtreeIfNeeded()
        pump(0.15)
        interact?(window, content)
        pump(settle)
        container.layoutSubtreeIfNeeded()
        container.displayIfNeeded()

        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(outer.width * scale), pixelsHigh: Int(outer.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { XCTFail("Bitmap für \(name) nicht anlegbar"); return }
        rep.size = outer
        look.appearance.performAsCurrentDrawingAppearance {
            container.cacheDisplay(in: container.bounds, to: rep)
        }
        write(Self.trimTransparentRows(rep), name: name, look: look)

        window.orderOut(nil)
        window.contentView = nil
        window.close()
    }

    /// Reines SwiftUI-Rendern ohne Fenster (kein onAppear/.task) – AppKit-Steuerelemente fehlen dabei.
    private func snapshotRenderer(_ name: String, size: CGSize?, make: () -> AnyView) {
        for look in Look.allCases {
            let base = make().defaultAppStorage(defaults).environment(\.colorScheme, look.scheme)
            let framed: AnyView = size.map { AnyView(base.frame(width: $0.width, height: $0.height)) } ?? AnyView(base)
            let renderer = ImageRenderer(content: framed)
            renderer.scale = 2
            var cg: CGImage?
            look.appearance.performAsCurrentDrawingAppearance { cg = renderer.cgImage }
            guard let cg else { XCTFail("ImageRenderer lieferte kein Bild für \(name)"); continue }
            write(NSBitmapImageRep(cgImage: cg), name: name, look: look)
        }
    }

    /// Schneidet oben und unten vollständig durchsichtige Zeilen ab (Messluft der Hosting-View).
    private static func trimTransparentRows(_ rep: NSBitmapImageRep) -> NSBitmapImageRep {
        guard let data = rep.bitmapData, rep.samplesPerPixel == 4, rep.bitsPerSample == 8,
              let cg = rep.cgImage else { return rep }
        let w = rep.pixelsWide, h = rep.pixelsHigh, bpr = rep.bytesPerRow
        func rowIsEmpty(_ y: Int) -> Bool {
            let row = data + y * bpr
            for x in 0..<w where row[x * 4 + 3] != 0 { return false }
            return true
        }
        var top = 0, bottom = h - 1
        while top < h && rowIsEmpty(top) { top += 1 }
        while bottom > top && rowIsEmpty(bottom) { bottom -= 1 }
        guard top < h, top > 0 || bottom < h - 1,
              let cropped = cg.cropping(to: CGRect(x: 0, y: top, width: w, height: bottom - top + 1))
        else { return rep }
        return NSBitmapImageRep(cgImage: cropped)
    }

    private func write(_ rep: NSBitmapImageRep, name: String, look: Look) {
        let url = outDir.appendingPathComponent("\(name)-\(look.suffix).png")
        guard let data = rep.representation(using: .png, properties: [:]) else {
            XCTFail("PNG für \(name) nicht erzeugbar"); return
        }
        XCTAssertNoThrow(try data.write(to: url))
    }

    // MARK: - Testbild (CoreGraphics, Fensterattrappe mit Text)

    static func testImage(width: Int, height: Int, title: String = "Knippi Testbild – Fensterattrappe",
                          hue: CGFloat = 0.58) -> CGImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        let W = CGFloat(width), H = CGFloat(height)
        // Schreibtisch
        NSGradient(starting: NSColor(hue: hue, saturation: 0.45, brightness: 0.85, alpha: 1),
                   ending: NSColor(hue: hue + 0.08, saturation: 0.55, brightness: 0.55, alpha: 1))!
            .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -60)
        // Fenster
        let win = NSRect(x: W * 0.08, y: H * 0.08, width: W * 0.84, height: H * 0.84)
        NSColor(white: 0, alpha: 0.25).setFill()
        NSBezierPath(roundedRect: win.offsetBy(dx: 0, dy: -H * 0.01), xRadius: 18, yRadius: 18).fill()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: win, xRadius: 18, yRadius: 18).fill()
        let barH = H * 0.07
        NSColor(white: 0.93, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: win.minX, y: win.maxY - barH, width: win.width, height: barH),
                     xRadius: 18, yRadius: 18).fill()
        for (i, c) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            c.setFill()
            let d = barH * 0.32
            NSBezierPath(ovalIn: NSRect(x: win.minX + barH * 0.5 + CGFloat(i) * d * 1.6,
                                        y: win.maxY - barH / 2 - d / 2, width: d, height: d)).fill()
        }
        let titleFont = NSFont.systemFont(ofSize: barH * 0.36, weight: .semibold)
        (title as NSString).draw(at: NSPoint(x: win.minX + barH * 3, y: win.maxY - barH / 2 - titleFont.pointSize * 0.6),
                                 withAttributes: [.font: titleFont, .foregroundColor: NSColor(white: 0.25, alpha: 1)])
        // Inhalt
        let body = NSFont.systemFont(ofSize: H * 0.035)
        let heading = NSFont.systemFont(ofSize: H * 0.06, weight: .bold)
        var y = win.maxY - barH - H * 0.11
        ("Überschrift im Testbild" as NSString).draw(at: NSPoint(x: win.minX + W * 0.04, y: y),
            withAttributes: [.font: heading, .foregroundColor: NSColor(white: 0.1, alpha: 1)])
        y -= H * 0.08
        for line in ["Rechnung Nr. 4711 vom 26.11.2026 – Betrag 249,00 €",
                     "Kontakt: test@example.com · +49 89 000000",
                     "Lorem ipsum dolor sit amet, consectetur adipiscing elit.",
                     "Äpfel, Öl, Übergröße, ß – Umlaute zur Schriftprobe."] {
            (line as NSString).draw(at: NSPoint(x: win.minX + W * 0.04, y: y),
                                    withAttributes: [.font: body, .foregroundColor: NSColor(white: 0.3, alpha: 1)])
            y -= H * 0.06
        }
        NSColor(hue: hue, saturation: 0.6, brightness: 0.9, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: win.minX + W * 0.04, y: win.minY + H * 0.06, width: W * 0.18, height: H * 0.07),
                     xRadius: 10, yRadius: 10).fill()
        ("Knopf" as NSString).draw(at: NSPoint(x: win.minX + W * 0.07, y: win.minY + H * 0.075),
                                   withAttributes: [.font: body, .foregroundColor: NSColor.white])
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }
}

// MARK: - Hilfstypen

private final class SnapshotWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Zeichnet seinen Hintergrund in draw(_:), damit cacheDisplay ihn mitnimmt.
private final class BackdropView: NSView {
    var fill: NSColor?
    override var isFlipped: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        guard let fill else { return }
        fill.setFill()
        bounds.fill()
    }
}

/// Upload, der nie fertig wird – zeigt den Zustand „läuft“.
private struct HangingDestination: ShareDestination {
    func upload(file: URL, key: String, contentType: String) async throws -> URL {
        try await Task.sleep(for: .seconds(30))
        throw ShareError.network(underlying: "Snapshot-Test")
    }
    func publicURL(for key: String) -> URL { URL(string: "https://example.invalid/\(key)")! }
    func delete(key: String) async throws {}
    func validateConfig() async throws {}
}

/// Upload, der sofort scheitert – zeigt den Fehlerzustand.
private struct FailingDestination: ShareDestination {
    func upload(file: URL, key: String, contentType: String) async throws -> URL {
        throw ShareError.network(underlying: "Die Verbindung zum Server wurde getrennt.")
    }
    func publicURL(for key: String) -> URL { URL(string: "https://example.invalid/\(key)")! }
    func delete(key: String) async throws {}
    func validateConfig() async throws {}
}

// MARK: - Familien-Umbau B: Cloud-Assistent, Video-Editor, Werkzeugleiste (26.11.)

import AVFoundation
import EditorKit

extension VisualSnapshotTests {

    /// Jeder Schritt des Cloud-Freigabe-Assistenten, ohne Netz (Zustände direkt gesetzt).
    func test20CloudShareWizardSteps() throws {
        let cases: [(String, (CloudShareWizardModel) -> Void)] = [
            ("wizard-1-welcome", { $0.step = .welcome }),
            ("wizard-2-provider", { $0.step = .provider }),
            ("wizard-3-keys", { $0.step = .getKeys }),
            ("wizard-4-credentials", { m in
                m.step = .credentials
                m.accountID = "1234abcd"; m.blurredAccountID = true
                m.bucket = "knippi-shots"; m.accessKey = "AKIA1234"; m.blurredAccessKey = true
                m.secretKey = "geheim"
            }),
            ("wizard-5-url-success", { m in
                m.step = .urlPrefix; m.urlPrefix = "https://cdn.example.com"; m.pathPrefix = "shots"
                m.testState = .success(roundTripSeconds: 0.8)
            }),
            ("wizard-5-url-failure", { m in
                m.step = .urlPrefix; m.urlPrefix = "https://cdn.example.com"
                m.testState = .failure(.publicAccessUnreachable)
            }),
            ("wizard-6-done", { $0.step = .done }),
        ]
        for (name, configure) in cases {
            // Aktives Fenster: sonst zeichnet macOS gefüllte Knöpfe grau (inaktiver Zustand).
            snapshot(name, size: CGSize(width: 640, height: 560), settle: 0.6, interact: { w, _ in w.makeKey() }) {
                let model = CloudShareWizardModel()
                configure(model)
                let vm = PreferencesViewModel(settings: self.settings, permissionManager: PermissionManager())
                return AnyView(CloudShareWizardView(viewModel: vm, onComplete: {}, model: model))
            }
        }
    }

    /// Video-Editor mit einem erzeugten 6-s-Testvideo (AVAssetWriter), Schnitt + Zoom + Unschärfe.
    func test21RecordingEditor() throws {
        let videoURL = try Self.makeTestVideo(in: scratch, seconds: 6)
        for (name, size, select) in [("video-editor", CGSize(width: 960, height: 640), "cut"),
                                     ("video-editor-zoom", CGSize(width: 1180, height: 760), "zoom")] {
            var keep: [EditorCoordinator] = []
            snapshot(name, size: size, settle: 1.2, interact: { w, _ in w.makeKey() }) {
                let project = RecordingProject(sourceVideoURL: videoURL, showsCursor: false, videoDuration: 6,
                                               videoSize: CGSize(width: 1280, height: 800),
                                               recordingAreaSize: CGSize(width: 1280, height: 800))
                let coordinator = EditorCoordinator(project: project, outputFormat: .mp4)
                coordinator.addZoomSegment(at: 2.2)
                let zoomID = coordinator.selectedEffectSegmentID
                coordinator.addBlurEffect(at: 3.0)
                coordinator.addCut(at: 0.6)
                if select == "zoom" {
                    coordinator.selectedCutRegionID = nil
                    coordinator.selectedEffectSegmentID = zoomID
                }
                keep.append(coordinator)
                return AnyView(RecordingEditorView(coordinator: coordinator))
            }
            withExtendedLifetime(keep) {}
        }
    }

    /// Werkzeugleiste in typischen Fensterbreiten (Inhaltsbreite = Fensterbreite) und im ganzen Editor.
    func test22AnnotationToolbarWidths() throws {
        let thumb = NSImage(cgImage: Self.testImage(width: 800, height: 500), size: NSSize(width: 200, height: 125))
        for width in [1180, 900] {
            for (suffix, tool) in [("", AnnotationTool.arrow), ("-text", .text)] {
                snapshot("annotation-toolbar-\(width)\(suffix)", size: CGSize(width: CGFloat(width), height: tool == .text ? 110 : 76),
                         backdrop: true, settle: 0.6) {
                    AnyView(Self.toolbar(tool: tool, thumb: thumb))
                }
            }
        }
        let image = Self.testImage(width: 1600, height: 1000)
        for (name, size) in [("annotation-editor-1180", CGSize(width: 1180, height: 820)),
                             ("annotation-editor-900", CGSize(width: 900, height: 680))] {
            snapshot(name, size: size, settle: 1.0) {
                let document = AnnotationDocument(imageSize: CGSize(width: image.width, height: image.height))
                return AnyView(
                    AnnotationEditorView(
                        sourceImage: image, document: document, sourceAppName: "Safari",
                        sourceWindowTitle: "Beispielseite", captureDate: Date(timeIntervalSince1970: 1_780_000_000),
                        screenshotOutput: self.settings.screenshotOutputOptions,
                        screenshotFilenameTemplate: self.settings.screenshotFilenameTemplate,
                        onSave: { _ in }, onSaveAs: { _ in }, onCopy: { _ in }, onPin: { _ in },
                        onDragStarted: {}, onDragEnded: {}, onCancel: {}
                    )
                )
            }
        }
    }

    private static func toolbar(tool: AnnotationTool, thumb: NSImage) -> AnnotationToolbar {
        AnnotationToolbar(
            currentTool: .constant(tool), currentColor: .constant(.red),
            lineWidth: .constant(tool == .text ? 48 : 3), strokePattern: .constant(.solid),
            arrowHead: .constant(.standard), filled: .constant(false),
            textFillEnabled: .constant(false), textOutlineEnabled: .constant(false),
            textStrokeEnabled: .constant(true), redactionMode: .constant(.pixelate),
            showBeautifyPanel: .constant(false), canUndo: true, canRedo: false,
            onUndo: {}, onRedo: {}, onSave: {}, onCopy: {}, onPin: {},
            dragThumbnail: thumb, onPrepareDrag: {}, onDragFileURL: { nil },
            onDragPreviewImage: { nil }, onDragStarted: {}, onDragEnded: {},
            isDragDisabled: false, onCancel: {}, onCrop: {}
        )
    }

    /// Kurzes H.264-Video: Testbild als Standbild, `seconds` lang bei 5 Bildern/s.
    private static func makeTestVideo(in dir: URL, seconds: Int) throws -> URL {
        let url = dir.appendingPathComponent("editor-test-\(UUID().uuidString).mov")
        let width = 640, height = 400, fps: Int32 = 5
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)

        let still = testImage(width: width, height: height, title: "Knippi Video-Testbild")
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferCGImageCompatibilityKey: true,
                             kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &buffer)
        let pixelBuffer = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer), width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        ctx?.draw(still, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        for frame in 0..<(seconds * Int(fps)) {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
            adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(frame), timescale: fps))
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        return url
    }
}

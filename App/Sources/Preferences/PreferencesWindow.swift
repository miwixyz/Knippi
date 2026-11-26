// App/Sources/Preferences/PreferencesWindow.swift
import AppKit
import SwiftUI
import SharedKit

@MainActor
final class PreferencesWindow {
    private var window: NSWindow?
    private let settings: AppSettings
    private let permissionManager: PermissionManager
    private let updateManager: UpdateManager?

    init(settings: AppSettings, permissionManager: PermissionManager, updateManager: UpdateManager? = nil) {
        self.settings = settings
        self.permissionManager = permissionManager
        self.updateManager = updateManager
    }

    func show(tab: PreferencesTab? = nil) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            // Navigate to requested tab if window already exists.
            // Use a dedicated notification name (NOT .openScreenshotSettings)
            // to avoid recursing back through AppDelegate's observer.
            if let tab {
                NotificationCenter.default.post(name: .preferencesSwitchTab, object: tab)
            }
            return
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: PreferencesView.windowSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.identifier = DockPresenceController.windowIdentifier
        window.title = String(localized: "Knippi Settings")
        // Glas-Umbau Phase 2: keine sichtbare Titelleiste, der lebende Hintergrund reicht über die
        // ganze Fläche, die Ampelknöpfe liegen über der schwebenden Glas-Insel. Der Fenstertitel
        // bleibt für Fenster-Menü und Bedienungshilfen gesetzt.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        // Leere Werkzeugleiste nur für die höhere Titelzone: die Ampelknöpfe rücken dadurch nach
        // innen und sitzen IN der Glas-Insel statt auf ihrer Kante (wie Finder/Systemeinstellungen).
        let toolbar = NSToolbar(identifier: "KnippiSettingsToolbar")
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.backgroundColor = FamilyTheme.canvasBackdropNS
        window.isReleasedWhenClosed = false

        let viewModel = PreferencesViewModel(settings: settings, permissionManager: permissionManager)
        let hosting = NSHostingController(rootView: PreferencesView(
            viewModel: viewModel, updateManager: updateManager, initialTab: tab))
        // Größe kommt fest vom Fenster, nicht aus der SwiftUI-Wunschgröße.
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(PreferencesView.windowSize)
        window.contentMinSize = PreferencesView.windowSize
        window.contentMaxSize = PreferencesView.windowSize
        window.center()

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

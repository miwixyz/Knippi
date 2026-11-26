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
        // macOS-26-Einstellungsfenster: durchsichtige Titelleiste, Inhalt bis oben, die
        // Glas-Seitenleiste schwebt unter den Ampel-Knöpfen (wie die Systemeinstellungen).
        // Der Titel steht als Überschrift im Inhalt; der Fenstertitel bleibt für Fenster-Menü
        // und Bedienungshilfen gesetzt.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // Keine Werkzeugleiste: sie brachte nur einen leeren Streifen über der Seitenleiste.
        // Die Seitenleiste zeichnet AppKit wie in Schriftsammlung/Finder (verglichen 26.11.).
        window.isReleasedWhenClosed = false

        let viewModel = PreferencesViewModel(settings: settings, permissionManager: permissionManager)
        let navigation = PreferencesNavigation(selectedTab: tab ?? .general)
        // NSSplitViewController mit Seitenleisten-Element: macOS 26 zeichnet die Seitenleiste
        // dann selbst als schwebendes Liquid Glass (wie Systemeinstellungen/Finder).
        let split = NSSplitViewController()
        let sidebarItem = NSSplitViewItem(sidebarWithViewController:
            NSHostingController(rootView: PreferencesSidebarView(navigation: navigation)))
        sidebarItem.minimumThickness = PreferencesView.sidebarWidth
        sidebarItem.maximumThickness = PreferencesView.sidebarWidth
        sidebarItem.canCollapse = false
        let detail = NSHostingController(rootView: PreferencesDetailView(
            navigation: navigation, viewModel: viewModel, updateManager: updateManager))
        let detailItem = NSSplitViewItem(viewController: detail)
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(detailItem)
        window.contentViewController = split
        window.setContentSize(PreferencesView.windowSize)
        window.contentMinSize = PreferencesView.windowSize
        window.contentMaxSize = PreferencesView.windowSize
        window.center()

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

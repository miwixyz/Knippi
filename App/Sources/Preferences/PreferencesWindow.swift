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
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.identifier = DockPresenceController.windowIdentifier
        window.title = String(localized: "Knippi Settings")
        window.minSize = PreferencesView.windowSize
        window.maxSize = PreferencesView.windowSize
        window.isReleasedWhenClosed = false
        window.center()

        // App-Familie G1: fester Fensterkörper statt Behind-Window-Blur
        // (der Schreibtisch würde sonst den Inhalt einfärben).
        let visualEffect = NSView()
        window.contentView = visualEffect

        let viewModel = PreferencesViewModel(settings: settings, permissionManager: permissionManager)
        let hostingView = NSHostingView(rootView: PreferencesView(viewModel: viewModel, updateManager: updateManager, initialTab: tab))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
        ])

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

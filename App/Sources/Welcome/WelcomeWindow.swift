// App/Sources/Welcome/WelcomeWindow.swift
import AppKit
import KeyboardShortcuts
import SharedKit
import SwiftUI

/// One-time welcome on the very first launch (0.8.0): the shortcut, where screenshots
/// go, and the Screen Recording permission. Only new installs see it (`WelcomeGate`).
/// It asks macOS for nothing itself: the permission is requested on the first capture
/// (`CapturePermissionGate`), a second request here would bring up a second dialog.
@MainActor
final class WelcomeWindow {
    private var window: NSWindow?

    func show(settings: AppSettings, screenRecordingGranted: Bool, onOpenSettings: @escaping () -> Void) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // Same identifier as the settings: shows the Dock icon while it is open.
        window.identifier = DockPresenceController.windowIdentifier
        window.title = String(localized: "Welcome to Knippi")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = FamilyTheme.canvasBackdropNS
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: WelcomeView(
            shortcut: KeyboardShortcuts.getShortcut(for: .captureArea)?.description,
            folder: Self.displayName(of: settings.exportLocation),
            autoSave: settings.screenshotAutoSave,
            autoCopy: settings.screenshotAutoCopy,
            screenRecordingGranted: screenRecordingGranted,
            onStart: { [weak window] in window?.close() },
            onOpenSettings: { [weak window] in
                window?.close()
                onOpenSettings()
            }
        ))
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The folder as Finder names it ("Bilder/Knippi", "iCloud Drive/Screenshots"), not the
    /// file system path ("~/Pictures/Knippi"); parts above the home folder are left out.
    static func displayName(of folder: URL) -> String {
        let fileManager = FileManager.default
        guard let parts = fileManager.componentsToDisplay(forPath: folder.path) else { return folder.path }
        // iCloud Drive sits under ~/Library/Mobile Documents; Finder shows it from "iCloud Drive" on.
        let iCloudName = fileManager.componentsToDisplay(forPath: NSHomeDirectory() + "/Library/Mobile Documents/com~apple~CloudDocs")?.last
        if let iCloudName, let start = parts.lastIndex(of: iCloudName) {
            return parts[start...].joined(separator: "/")
        }
        let home = fileManager.componentsToDisplay(forPath: NSHomeDirectory()) ?? []
        let shown = parts.starts(with: home) && parts.count > home.count ? Array(parts.dropFirst(home.count)) : parts
        return shown.joined(separator: "/")
    }
}

struct WelcomeView: View {
    let shortcut: String?
    let folder: String
    let autoSave: Bool
    let autoCopy: Bool
    let screenRecordingGranted: Bool
    let onStart: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: FamilyTheme.Space.l) {
            VStack(spacing: FamilyTheme.Space.s) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                        .accessibilityHidden(true)
                }
                Text("Welcome to Knippi")
                    .font(FamilyTheme.font(24, weight: .bold))
                    .foregroundStyle(FamilyTheme.textPrimary)
                Text("Screenshots from the menu bar, quick and simple.")
                    .font(FamilyTheme.font(13))
                    .foregroundStyle(FamilyTheme.textSecondary)
            }
            .padding(.top, FamilyTheme.Space.xl)

            VStack(alignment: .leading, spacing: FamilyTheme.Space.l) {
                WelcomeRow(icon: "viewfinder", title: "Take a screenshot", text: captureText)
                WelcomeRow(icon: "menubar.rectangle", title: "Everything else",
                           text: String(localized: "The Knippi icon in the menu bar has all capture modes, your recent screenshots and the settings."))
                WelcomeRow(icon: "folder", title: "Where screenshots go", text: storageText)
                WelcomeRow(icon: screenRecordingGranted ? "checkmark.shield" : "lock.shield",
                           title: "Screen & System Audio Recording permission", text: permissionText,
                           tint: screenRecordingGranted ? FamilyTheme.success : nil)
            }
            .padding(FamilyTheme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .preferencesGlassCard(cornerRadius: FamilyTheme.Radius.tile)

            HStack {
                Button("Settings…", action: onOpenSettings)
                    .controlSize(.large)
                Spacer()
                Button("Get Started", action: onStart)
                    .buttonStyle(AccentCapsuleButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, FamilyTheme.Space.xl)
        .padding(.bottom, FamilyTheme.Space.xl)
        .frame(width: 520)
        .background { HelpBackdrop() }
    }

    private var captureText: String {
        if let shortcut {
            return String(localized: "Press \(shortcut) and drag over the area you want.")
        }
        return String(localized: "Click the Knippi icon in the menu bar and choose an area.")
    }

    private var storageText: String {
        switch (autoSave, autoCopy) {
        case (true, true):
            return String(localized: "Every screenshot is saved to \(folder) and copied to the clipboard.")
        case (true, false):
            return String(localized: "Every screenshot is saved to \(folder).")
        case (false, true):
            return String(localized: "Every screenshot is copied to the clipboard. Click Save in the preview to keep it in \(folder).")
        case (false, false):
            return String(localized: "Click Save in the preview to keep a screenshot in \(folder).")
        }
    }

    private var permissionText: String {
        screenRecordingGranted
            ? String(localized: "Granted. Knippi can capture your screen.")
            : String(localized: "macOS asks for it on your first screenshot. Knippi only looks at the screen when you capture.")
    }
}

private struct WelcomeRow: View {
    let icon: String
    let title: LocalizedStringKey
    let text: String
    var tint: Color?

    var body: some View {
        HStack(alignment: .top, spacing: FamilyTheme.Space.m) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(tint ?? FamilyTheme.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(FamilyTheme.font(13, weight: .semibold))
                    .foregroundStyle(FamilyTheme.textPrimary)
                Text(text)
                    .font(FamilyTheme.font(12))
                    .foregroundStyle(FamilyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

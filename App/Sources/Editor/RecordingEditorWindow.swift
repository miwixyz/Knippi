import AppKit
import SwiftUI

final class RecordingEditorWindow: NSPanel {

    private let coordinator: EditorCoordinator

    init(coordinator: EditorCoordinator) {
        self.coordinator = coordinator

        let contentRect = NSRect(x: 0, y: 0, width: 960, height: 640)
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        identifier = DockPresenceController.windowIdentifier
        title = String(localized: "Recording Editor")
        minSize = NSSize(width: 800, height: 540)
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        // Glas-Umbau Phase 2: Titelleiste unsichtbar, der lebende Hintergrund reicht bis oben.
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        titlebarSeparatorStyle = .none
        backgroundColor = FamilyTheme.canvasBackdropNS

        // Fester Fensterkörper: Der Familien-Verlauf kommt aus RecordingEditorView. Vorher lag
        // hier ein NSVisualEffectView (.sidebar, behindWindow), das vom Schreibtischbild
        // getönt wird (Design-System: kein violetter Stich).
        contentView = NSHostingView(rootView: RecordingEditorView(coordinator: coordinator))
    }

    private var hasClosed = false

    /// Red close button and ⌘W. Programmatic `close()` (after a finished export)
    /// does not pass through here and closes without asking.
    override func performClose(_ sender: Any?) {
        // Closing mid-export would cut the export off; the overlay already
        // says the editor closes on its own when it is done.
        if coordinator.isExporting {
            NSSound.beep()
            return
        }
        // A finished export closes the window by code, never through here, so every
        // pass through this method means the recording has not been saved. The source
        // file is deleted when the editor closes, hence always ask.
        let hasEdits = !coordinator.project.trimRegions.isEmpty || !coordinator.project.effectSegments.isEmpty
        let alert = NSAlert()
        alert.alertStyle = .warning
        if hasEdits {
            alert.messageText = String(localized: "Discard your edits?")
            alert.informativeText = String(localized: "Your cuts and effects haven't been exported and will be lost.")
        } else {
            alert.messageText = String(localized: "Discard this recording?")
            alert.informativeText = String(localized: "The recording hasn't been saved and will be lost.")
        }
        alert.addButton(withTitle: String(localized: "Discard"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        super.performClose(sender)
    }

    /// The red close button closes the window directly, bypassing
    /// `EditorCoordinator.onClose`: stop playback and tear down here too
    /// (audit E8, 21.11.).
    override func close() {
        guard !hasClosed else { return }
        hasClosed = true
        coordinator.pause()
        super.close()
        coordinator.closeEditor()
    }

    func showCentered() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - frame.width / 2
        let y = screenFrame.midY - frame.height / 2
        setFrameOrigin(NSPoint(x: x, y: y))
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
}

// App/Sources/KnippiApp.swift
import SwiftUI

@main
enum KnippiMain {
    @MainActor
    static func main() {
        // Finish helper requests before SwiftUI/AppKit starts an application
        // lifecycle. An OCR retry must not take focus from the running app.
        if OCRProcessFallback.runHelperIfRequested() {
            return
        }
        KnippiApp.main()
    }
}

struct KnippiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(String(localized: "Settings…")) {
                    appDelegate.showPreferences()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

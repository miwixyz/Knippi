// App/Sources/Support/SichttestHooksGlas2.swift
import AppKit
import SwiftUI

/// Messhilfen für Glas-Umbau Phase 3 — NUR in abgeschotteten Testkopien (Kennung unter
/// `dev.mwlr.knippi.*`, nie `dev.mwlr.knippi`). In der echten App tut dieser Code nichts.
/// Gesetzt per `defaults write <kennung> …`:
///
/// - `debugGlasWizard <schritt>` (welcome, provider, getKeys, credentials, urlPrefix, done,
///   `success` = URL-Schritt mit geglücktem Test): Cloud-Assistent als Blatt über den Einstellungen.
/// - `debugGlasAutomation 1`: Blatt „Automatisierungs-URLs“ über den Einstellungen.
/// - `debugGlasHelp 1`: Hilfe-Fenster.
/// - `debugQAReveal 1`: Vorschaukarte im Hover-Zustand (Leiste sichtbar).
/// - `debugQATool copy|save|annotate|share|drag`: dieser Knopf in Hover-Optik.
/// - `debugQAUpload uploading|failed`: Upload-Zustand der Vorschaukarte.
///
/// Auslöser: einmal beim ersten Erscheinen der Einstellungen (`PreferencesView`), die sich per
/// `debugOpenSettings <tab>` beim Start öffnen lassen.
@MainActor
enum SichttestHooksGlas2 {
    static var isTestCopy: Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        return id.hasPrefix("dev.mwlr.knippi.") && id != "dev.mwlr.knippi"
    }

    private static var didRun = false
    private static var keepAlive: [AnyObject] = []

    static func preferencesAppeared(viewModel: PreferencesViewModel) {
        guard isTestCopy, !didRun else { return }
        didRun = true
        let defaults = UserDefaults.standard
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if let step = defaults.string(forKey: "debugGlasWizard") {
                presentWizard(step: step, viewModel: viewModel)
            } else if defaults.bool(forKey: "debugGlasAutomation") {
                presentSheet(AnyView(AutomationURLsSheetView(isPresented: .constant(true))))
            }
            if defaults.bool(forKey: "debugGlasHelp") {
                let help = HelpWindow()
                keepAlive.append(help)
                help.show()
            }
        }
    }

    private static func presentWizard(step: String, viewModel: PreferencesViewModel) {
        let model = CloudShareWizardModel()
        switch step {
        case "provider": model.step = .provider
        case "getKeys": model.step = .getKeys
        case "credentials": model.step = .credentials
        case "urlPrefix": model.step = .urlPrefix
        case "success":
            model.step = .urlPrefix
            model.urlPrefix = "https://share.example.com"
            model.testState = .success(roundTripSeconds: 1.4)
        case "done": model.step = .done
        default: model.step = .welcome
        }
        presentSheet(AnyView(CloudShareWizardView(viewModel: viewModel, onComplete: {}, model: model)))
    }

    private static func presentSheet(_ view: AnyView) {
        let title = String(localized: "Knippi Settings")
        guard let parent = NSApp.windows.first(where: { $0.title == title && $0.isVisible }) else { return }
        let hosting = NSHostingController(rootView: view)
        let sheet = NSWindow(contentViewController: hosting)
        keepAlive.append(sheet)
        parent.beginSheet(sheet)
    }
}

/// Messhilfe für die Vorschaukarte (nur Testkopien, siehe oben). In der App immer aus/nil.
@MainActor
enum QuickAccessDebug {
    static var forceRevealed: Bool {
        SichttestHooksGlas2.isTestCopy && UserDefaults.standard.bool(forKey: "debugQAReveal")
    }
    static var hoveredTool: String? {
        SichttestHooksGlas2.isTestCopy ? UserDefaults.standard.string(forKey: "debugQATool") : nil
    }
    static var uploadState: String? {
        SichttestHooksGlas2.isTestCopy ? UserDefaults.standard.string(forKey: "debugQAUpload") : nil
    }
}

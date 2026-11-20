// App/Sources/Help/HelpView.swift
import AppKit
import SwiftUI

/// Hilfe, Änderungen und Fremdcode-Hinweise — direkt aus dem Bundle gelesen,
/// nicht als Swift-Strings gepflegt (Muster Seam).
///
/// Warum: Eine Prosa-Doku im Quelltext driftet. Tippis Hilfe hing an einem Tag
/// fünf Versionen hinterher. Hier liegen `HILFE.md`, `CHANGELOG.md` und
/// `THIRD_PARTY_NOTICES.md` als Ressourcen im App-Bundle (siehe `project.yml`);
/// CHANGELOG und Hinweise kommen bei jedem Build frisch aus dem Repo-Wurzelordner.
///
/// Fremdcode muss in der App erreichbar sein: Die MIT-Lizenzen von Capso und
/// Sparkle verlangen Urheberhinweis und Lizenztext bei der Auslieferung.
struct HelpView: View {

    enum Doc: String, CaseIterable, Identifiable {
        case help, changes, thirdParty
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .help: "Help"
            case .changes: "What's New"
            case .thirdParty: "Third-Party Notices"
            }
        }

        var resource: String {
            switch self {
            case .help: "HILFE"
            case .changes: "CHANGELOG"
            case .thirdParty: "THIRD_PARTY_NOTICES"
            }
        }
    }

    @State private var doc: Doc = .help

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $doc) {
                ForEach(Doc.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ScrollView {
                MarkdownView(source: Self.text(for: doc))
                    .textSelection(.enabled)
                    .padding(.trailing, 6)
            }

            HStack(spacing: 8) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 30, height: 30)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: "Knippi").font(.callout.weight(.semibold))
                    Text("Version \(version)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(16)
    }

    /// Fehlt eine Datei, steht das sichtbar da — statt einer leeren Fläche, die
    /// wie „keine Änderungen“ aussieht. Ein fehlendes Dokument ist ein Build-Fehler.
    static func text(for doc: Doc) -> String {
        guard let url = Bundle.main.url(forResource: doc.resource, withExtension: "md"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return "## Dokument fehlt\n\n`\(doc.resource).md` liegt nicht im App-Bundle. "
                 + "Das ist ein Fehler beim Bauen, keine leere Datei."
        }
        return raw
    }
}

/// Eigenes Fenster für die Hilfe (Muster `PreferencesWindow`).
@MainActor
final class HelpWindow {
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        // Gleiche Kennung wie die Einstellungen: zeigt das Dock-Symbol, solange
        // das Fenster offen ist (DockPresenceController).
        window.identifier = DockPresenceController.windowIdentifier
        window.title = String(localized: "Knippi Help")
        window.minSize = NSSize(width: 480, height: 400)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: HelpView())
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

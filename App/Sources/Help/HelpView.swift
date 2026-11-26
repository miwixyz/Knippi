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

        var icon: String {
            switch self {
            case .help: "questionmark.circle"
            case .changes: "sparkles"
            case .thirdParty: "doc.text"
            }
        }
    }

    @State private var doc: Doc = .help
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    /// Glas-Umbau Phase 3: lebender Hintergrund über das ganze Fenster (Titelleiste unsichtbar),
    /// oben eine schwebende Glas-Kapsel als Dokument-Umschalter mit gleitender Akzent-Pille,
    /// der Text liegt lesbar auf einer festen Karte (Regel G1).
    var body: some View {
        VStack(spacing: 12) {
            GlassPillBar(items: Doc.allCases, selection: doc,
                         label: { Text($0.title) }, icon: { $0.icon }) { doc = $0 }

            ScrollView {
                MarkdownView(source: Self.text(for: doc))
                    .textSelection(.enabled)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(doc)
                    .transition(reduceMotion
                                ? .opacity
                                : .asymmetric(insertion: .opacity.combined(with: .offset(y: 10)), removal: .opacity))
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .familyAnimation(FamilyTheme.Motion.appear, value: doc)
            .preferencesGlassCard(cornerRadius: FamilyTheme.Radius.tile)

            HStack(spacing: 8) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 26, height: 26)
                        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: "Knippi")
                        .font(FamilyTheme.font(12, weight: .semibold))
                        .foregroundStyle(FamilyTheme.textPrimary)
                    Text("Version \(version)")
                        .font(FamilyTheme.font(11))
                        .foregroundStyle(FamilyTheme.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .background { HelpBackdrop() }
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

/// Lebender Hintergrund der Nebenfenster (Hilfe, Automatisierungs-Blatt): AmbientBackdrop plus
/// ein Akzent-Licht oben, hinter der Glas-Kapsel, damit das Glas etwas zum Brechen hat.
struct HelpBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .top) {
            AmbientBackdrop(glow: 1.0)
            if !reduceTransparency && contrast != .increased {
                Ellipse()
                    .fill(FamilyTheme.accent.opacity(colorScheme == .light ? 0.42 : 0.36))
                    .frame(width: 360, height: 150)
                    .blur(radius: 60)
                    .offset(y: -40)
                Ellipse()
                    .fill(FamilyTheme.iris.opacity(0.22))
                    .frame(width: 340, height: 240)
                    .blur(radius: 90)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .offset(x: 110, y: 90)
            }
        }
        .accessibilityHidden(true)
        .ignoresSafeArea()
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
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // Gleiche Kennung wie die Einstellungen: zeigt das Dock-Symbol, solange
        // das Fenster offen ist (DockPresenceController).
        window.identifier = DockPresenceController.windowIdentifier
        window.title = String(localized: "Knippi Help")
        // Titelleiste unsichtbar, der lebende Hintergrund reicht bis an den oberen Rand (Phase 3).
        // Der Titel bleibt für Fenster-Menü und Bedienungshilfen gesetzt.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = FamilyTheme.canvasBackdropNS
        window.minSize = NSSize(width: 480, height: 400)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: HelpView())
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

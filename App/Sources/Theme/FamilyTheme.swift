// FamilyTheme.swift — Design-Tokens der App-Familie (Tippi, Kalli, TippAI, Qotti)
//
// Quelle der Wahrheit: „App-Familie Design-System.md“ im selben Ordner (Vault).
// Stand 2026-09-29. In ein App-Projekt KOPIEREN und dort nur `FamilyTheme.app`
// setzen — die Werte hier nicht pro App abwandeln, sonst driftet die Familie.
//
// Plattformen: macOS 14+/iOS 17+ (Farben, Verlauf, Karten). Liquid Glass ab
// macOS/iOS 26 über `glassEffect`, darunter ein Material-Fallback.

import CoreText
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Hell/Dunkel-Farben

extension Color {
    /// Farbe mit getrenntem Wert für Hell und Dunkel, als echte dynamische Systemfarbe
    /// (reagiert auf NSApp.appearance / Trait-Wechsel ohne Neuzeichnen von Hand).
    ///
    /// `lightHC`/`darkHC` (optional, ab 2026-10-29): Werte für die Systemeinstellung „Kontrast erhöhen“
    /// (Mac: Bedienungshilfen → Anzeige; iPhone: „Kontrast erhöhen“). Ziel 7 : 1 für Text/Akzent,
    /// 3 : 1 für Linien. Fehlen sie, gilt der normale Wert – kein View muss davon wissen.
    init(light: UInt32, dark: UInt32, lightHC: UInt32? = nil, darkHC: UInt32? = nil) {
        let hcLight = lightHC ?? light, hcDark = darkHC ?? dark
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            let high = traits.accessibilityContrast == .high
            if traits.userInterfaceStyle == .dark { return UIColor(hex: high ? hcDark : dark) }
            return UIColor(hex: high ? hcLight : light)
        })
        #elseif canImport(AppKit)
        // Kontrast: direkt die Systemeinstellung fragen. Über NSAppearance-Namen lässt es sich nicht
        // verlässlich erkennen – `NSAppearance(named: .accessibilityHighContrastAqua)` liefert schlicht
        // „Aqua“ (gemessen 29.10.). macOS zeichnet nach dem Umschalten neu und ruft den Block erneut auf.
        self.init(nsColor: NSColor(name: nil) { appearance in
            let high = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(hex: high ? hcDark : dark)
            }
            return NSColor(hex: high ? hcLight : light)
        })
        #endif
    }
}

#if canImport(UIKit)
private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#elseif canImport(AppKit)
private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#endif

// MARK: - Tokens

enum FamilyTheme {

    /// Welche App — bestimmt nur den Akzent. Alles andere ist für alle gleich.
    enum App { case tippi, kalli, tippAI, qotti, seam, knippi }

    /// In jeder App genau einmal setzen (z. B. im App-Einstieg).
    nonisolated(unsafe) static var app: App = .kalli

    // Kontrast erhöhen (29.10.): *HC-Werte gerechnet auf 7 : 1 gegen Weiß, F3F5F9, D9DDE8 bzw. 1B2130, 0D1019,
    // 1F2433; Füllungen 7 : 1 gegen Weiß; cardStroke 3 : 1 (Nicht-Text). Ohne HC-Wert reicht der normale schon.
    // Akzente „Schiefer“ (Variante B, Michael 29.09.): aus #56607E abgeleitet, Farbton 208–242°, gedämpft, Kontrast geprüft (WCAG ≥ 4,5 : 1
    // für Text auf Weiß bzw. auf der dunklen Karte, gerechnet 2026-09-29).
    static var accent: Color {
        switch app {
        case .tippi:  Color(light: 0x3E5998, dark: 0x98AEE1, lightHC: 0x2F4474, darkHC: 0x99AFE1)   // Schieferblau
        case .kalli:  Color(light: 0x3E4D98, dark: 0x98A4E1, lightHC: 0x33407E, darkHC: 0xA1ACE4)   // Schieferindigo
        case .tippAI: Color(light: 0x413E98, dark: 0x9B98E1, lightHC: 0x3D3A8F, darkHC: 0xACAAE6)   // Schieferviolett
        case .qotti:  Color(light: 0x3E6E98, dark: 0x98BFE1, lightHC: 0x284763)   // Schiefer-Himmelblau
        case .seam:   Color(light: 0x3E5398, dark: 0x98A9E1, lightHC: 0x32427A, darkHC: 0x9DADE2)   // Iris (Seam-Website)
        case .knippi: Color(light: 0x2E6F80, dark: 0x94D0DF, lightHC: 0x225868, darkHC: 0xA4D8E5)   // Petrol
        }
    }
    /// Füllung für Flächen mit WEISSER Schrift (`.borderedProminent`, gefüllte Kapseln).
    /// Hell = `accent`. Dunkel ein satterer Ton: Der helle Dunkelmodus-Akzent ist für
    /// Text/Symbole gedacht, Weiß darauf hätte nur 2,2 : 1 (Tippi, gemessen 29.09.).
    /// Diese Werte halten Weiß ≥ 4,6 : 1. Einsatz: `.tint(FamilyTheme.accentFill)`.
    static var accentFill: Color {
        switch app {
        case .tippi:  Color(light: 0x3E5998, dark: 0x5172BD, lightHC: 0x3D5795, darkHC: 0x395697)
        case .kalli:  Color(light: 0x3E4D98, dark: 0x5C6DC1, darkHC: 0x4052A9)
        case .tippAI: Color(light: 0x413E98, dark: 0x6B67C5, darkHC: 0x4D49B9)
        case .qotti:  Color(light: 0x3E6E98, dark: 0x4179AA, lightHC: 0x345C80, darkHC: 0x315C81)
        case .seam:   Color(light: 0x3E5398, dark: 0x5A6DC0, darkHC: 0x3F52A5)
        case .knippi: Color(light: 0x2E6F80, dark: 0x2C7487, darkHC: 0x225868)
        }
    }

    /// Gemeinsamer Familienton (Iris) — für Übergreifendes: Website, Icons, Marketing.
    static let iris = Color(light: 0x3E5398, dark: 0x98A9E1)

    /// Text/Symbol AUF einer Akzentfläche (aktive Kapsel, „heute“). Hell weiß, dunkel
    /// dunkel — weiß auf dem hellen Dunkelmodus-Akzent wäre kaum lesbar (im Rendering-
    /// Test 2026-09-29 gesehen). Nie `.white` fest verdrahten.
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x0D1019)

    // Flächen
    static let backgroundTop    = Color(light: 0xF3F5F9, dark: 0x0D1019)
    static let backgroundMiddle = Color(light: 0xE7E9F1, dark: 0x161A25)
    static let backgroundBottom = Color(light: 0xD9DDE8, dark: 0x1F2433)
    /// Feste Inhaltsfläche (Karte, Editor, Liste). Nie transparent.
    static let card        = Color(light: 0xFFFFFF, dark: 0x1B2130)
    static let cardStroke  = Color(light: 0xE2E5EE, dark: 0x2A3142, lightHC: 0x8C93A8, darkHC: 0x6B7491)
    /// Tönung für große Glasflächen (siehe `familyTintedGlass`). Mitte des Verlaufs,
    /// 78 % Deckkraft — ruhig, aber das Glas bleibt als Glas erkennbar.
    static let glassTint = Color(light: 0xF3F5F9, dark: 0x161A25).opacity(0.78)
    /// Leichte Tönung für kleines echtes Liquid Glass (Vorschaukarte, Hinweis, Aufnahmeleiste):
    /// nimmt dem Schreibtisch die Farbe, lässt aber Lichtbrechung und Rand sichtbar.
    static let glassLightTint = Color(light: 0xF3F5F9, dark: 0x161A25).opacity(0.42)
    /// Etwas kräftigere Tönung für Glas, auf dem Text steht (Hinweis): bleibt auch über
    /// dunklen Fenstern lesbar (gemessen 26.11.: 0,42 über dunklem Fenster nur mittelgrau).
    static let glassReadableTint = Color(light: 0xF3F5F9, dark: 0x161A25).opacity(0.66)
    /// Hauptknopf der schwebenden Leiste („+“): dunkel im Hellen, hell im Dunklen.
    static let primaryFill = Color(light: 0x1E2433, dark: 0xECEFF6)
    static let onPrimary   = Color(light: 0xFFFFFF, dark: 0x1E2433)

    // Text
    static let textPrimary   = Color(light: 0x1E2433, dark: 0xECEFF6)
    static let textSecondary = Color(light: 0x56607E, dark: 0xA3ACC8, lightHC: 0x3E455B, darkHC: 0xA6AECA)   // Michaels Referenzton

    // Status (sparsam — Farbe trägt nie allein die Bedeutung). Achtung (gerechnet 29.10.): hell auf
    // backgroundBottom nur 3,2–3,8 : 1 – für kleinen Text auf dem Verlauf zu wenig, auf Karte/Weiß ok.
    static let success = Color(light: 0x1F8A6B, dark: 0x6FE0C1, lightHC: 0x114D3C)
    static let warning = Color(light: 0xB25E09, dark: 0xF5B35C, lightHC: 0x6B3805)
    static let danger  = Color(light: 0xC23B4E, dark: 0xFF8A9A, lightHC: 0x7C2632, darkHC: 0xFF8E9D)

    // MARK: Schrift — Plus Jakarta Sans (Michael, 2026-09-29), SIL OFL 1.1
    //
    // Datei `PlusJakartaSans-Variable.ttf` (eine Datei, alle Stärken) ins App-Bundle
    // legen und beim Start einmal `FamilyTheme.registerFonts()` aufrufen. `relativeTo:`
    // hält Dynamic Type/große Systemschrift am Leben.
    static let fontFamily = "Plus Jakarta Sans"

    static func font(_ size: CGFloat, weight: Font.Weight = .regular,
                     relativeTo style: Font.TextStyle = .body) -> Font {
        Font.custom(fontFamily, size: size, relativeTo: style).weight(weight)
    }

    /// Ersatz für `.font(.caption)`, `.font(.headline)` usw.: gleiche Größe wie der
    /// Apple-Textstil der Plattform, aber in Plus Jakarta Sans. Auf iPhone/iPad wächst
    /// sie mit Dynamic Type (`relativeTo:`). Überschrift-Stile sind SemiBold wie bei Apple.
    static func font(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
        let size: CGFloat
        let defaultWeight: Font.Weight
        #if os(macOS)
        switch style {
        case .largeTitle: size = 26; defaultWeight = .regular
        case .title: size = 22; defaultWeight = .regular
        case .title2: size = 17; defaultWeight = .regular
        case .title3: size = 15; defaultWeight = .regular
        case .headline: size = 13; defaultWeight = .semibold
        case .subheadline: size = 11; defaultWeight = .regular
        case .callout: size = 12; defaultWeight = .regular
        case .footnote, .caption, .caption2: size = 10; defaultWeight = .regular
        default: size = 13; defaultWeight = .regular
        }
        #else
        switch style {
        case .largeTitle: size = 34; defaultWeight = .regular
        case .title: size = 28; defaultWeight = .regular
        case .title2: size = 22; defaultWeight = .regular
        case .title3: size = 20; defaultWeight = .regular
        case .headline: size = 17; defaultWeight = .semibold
        case .subheadline: size = 15; defaultWeight = .regular
        case .callout: size = 16; defaultWeight = .regular
        case .footnote: size = 13; defaultWeight = .regular
        case .caption: size = 12; defaultWeight = .regular
        case .caption2: size = 11; defaultWeight = .regular
        default: size = 17; defaultWeight = .regular
        }
        #endif
        return font(size, weight: weight ?? defaultWeight, relativeTo: style)
    }

    /// Registriert die Schriftdatei aus dem App-Bundle. Gibt zurück, ob es geklappt hat —
    /// ohne Registrierung fällt SwiftUI still auf die Systemschrift zurück.
    @discardableResult
    static func registerFonts(bundle: Bundle = .main) -> Bool {
        guard let url = bundle.url(forResource: "PlusJakartaSans-Variable", withExtension: "ttf") else {
            return false
        }
        var error: Unmanaged<CFError>?
        let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        // „bereits registriert“ zählt als Erfolg.
        return ok || (error?.takeRetainedValue()).map { CFErrorGetCode($0) == 105 } == true
    }

    // Formen (Punkte)
    enum Radius {
        static let card: CGFloat = 28     // große Inhaltskarten
        static let tile: CGFloat = 20     // Kacheln, Listenzeilen-Gruppen
        static let field: CGFloat = 14    // Eingabefelder, kleine Karten
    }
    // Abstände: 4-Punkt-Raster
    enum Space {
        static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16
        static let xl: CGFloat = 24, xxl: CGFloat = 32
    }

    /// Schwebende Fenster (Panel, HUD, Hinweis, Vorschaukarte): ein gemeinsamer Satz.
    /// Halbtransparentes Glas → Fensterschatten aus (`hasShadow = false`), Schatten in der
    /// Ansicht zeichnen und das Fenster ringsum um `edge` größer machen. `edge` muss größer
    /// sein als `shadowRadius + shadowY`, sonst schneidet die Fenstergrenze den Schatten
    /// rechteckig ab (Kalli-Tagesblatt-Muster, Design-System „Verbote“, 15.11.).
    enum Floating {
        static let radius: CGFloat = 14
        static let edge: CGFloat = 24
        static let shadowRadius: CGFloat = 10
        static let shadowY: CGFloat = 5
        static let shadowColor = Color(light: 0x1E2846, dark: 0x000000).opacity(0.22)
    }

    /// Übergang für alte Aufrufer mit `NSColor`-Systemfarben (Toasts): bildet sie auf die
    /// Status-Tokens ab. Grün → `success`, Gelb/Orange → `warning`, Rot → `danger`.
    #if canImport(AppKit) && !canImport(UIKit)
    static func statusColor(for color: NSColor) -> Color {
        switch color {
        case .systemGreen: success
        case .systemYellow, .systemOrange: warning
        case .systemRed: danger
        default: Color(nsColor: color)
        }
    }
    #endif

    /// Hintergrundverlauf „Schiefer“: kühles Blaugrau. Fest, nicht transparent.
    static var backgroundGradient: LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundMiddle, backgroundBottom],
                       startPoint: .top, endPoint: .bottom)
    }

    /// Ruhiger Fensterverlauf für Inhaltsbereiche mit Glas-Seitenleiste (Einstellungen):
    /// diagonal, kaum sichtbar, damit das Glas darüber etwas zum Brechen hat.
    static var calmGradient: LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundMiddle], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Arbeitsfläche hinter dem Bild im Editor (wie Vorschau: hell im Hellen, dunkel im Dunklen).
    /// Fest — darüber schweben die Glas-Kapseln der Werkzeugleiste.
    static let canvasBackdrop = Color(light: 0xDCE0E9, dark: 0x10131B)
    #if canImport(AppKit) && !canImport(UIKit)
    static let canvasBackdropNS = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(hex: 0x10131B) : NSColor(hex: 0xDCE0E9)
    }
    #endif

    /// Bewegung der Familie: ruhige Federn ohne Nachwippen. Bei „Bewegung reduzieren“
    /// liefern die Bausteine unten `nil` bzw. eine kurze Überblendung.
    enum Motion {
        /// Auswahl wechselt, Kapsel gleitet (Werkzeug, Seitenleiste).
        static let select = Animation.spring(response: 0.34, dampingFraction: 0.86)
        /// Schwebendes erscheint (Vorschaukarte, Hinweis).
        static let appear = Animation.spring(response: 0.46, dampingFraction: 0.8)
        /// Hover hebt an.
        static let hover = Animation.spring(response: 0.28, dampingFraction: 0.9)
        /// Ersatz bei „Bewegung reduzieren“: nur Deckkraft, kurz.
        static let reduced = Animation.easeOut(duration: 0.15)
    }
}

// MARK: - Bausteine

extension View {
    /// Fenster-/Bildschirmhintergrund der Familie.
    func familyBackground() -> some View {
        background(FamilyTheme.backgroundGradient.ignoresSafeArea())
    }

    /// Feste Inhaltskarte: weiß bzw. dunkles Violett, großer Radius, weicher Schatten.
    func familyCard(radius: CGFloat = FamilyTheme.Radius.card) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(FamilyTheme.card)
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(FamilyTheme.cardStroke, lineWidth: 0.8)
                }
                .shadow(color: Color(light: 0x1E2846, dark: 0x000000).opacity(0.10), radius: 18, y: 8)
        }
    }

    /// Schiefer-Tönung ÜBER dem Glas einer großen Fläche (Popover, Vollbild-Hinweis).
    /// Ohne sie scheint das Schreibtischbild voll durch und färbt alles ein — in Kalli
    /// 0.6.0-Test gesehen: pinkes Hintergrundbild → rosa Popover (Michael, 29.09.).
    /// Entspricht der Vorschau (Fläche mit ca. 80 % Deckkraft über Unschärfe).
    func familyTintedGlass<S: Shape>(in shape: S) -> some View {
        background(shape.fill(FamilyTheme.glassTint)).familyGlass(in: shape)
    }

    /// Schwebende Fläche der Familie: getöntes Glas, feiner Rand, weicher Schatten,
    /// ringsum `Floating.edge` transparenter Rand für den Schatten. Das Fenster muss
    /// um 2 × `edge` größer sein als die Fläche und `hasShadow = false` haben.
    func familyFloatingSurface<S: Shape>(in shape: S) -> some View {
        familyTintedGlass(in: shape)
            .overlay { shape.stroke(FamilyTheme.cardStroke.opacity(0.9), lineWidth: 0.5) }
            .compositingGroup()
            .shadow(color: FamilyTheme.Floating.shadowColor,
                    radius: FamilyTheme.Floating.shadowRadius, y: FamilyTheme.Floating.shadowY)
            .padding(FamilyTheme.Floating.edge)
    }

    /// Glas-Element (Kapsel, runder Knopf, schwebende Leiste). NUR für Bedienelemente,
    /// die über Inhalt schweben — nie für Inhaltsflächen (siehe Design-System, Regel G1).
    func familyGlass<S: Shape>(in shape: S) -> some View {
        modifier(FamilyGlassModifier(shape: shape))
    }
}

/// `familyGlass`: bei „Transparenz reduzieren“ eine feste Familien-Fläche statt Glas
/// (bei `familyTintedGlass` liegt die Tönung dann deckend darauf).
private struct FamilyGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(shape.fill(FamilyTheme.card))
                .overlay(shape.stroke(FamilyTheme.cardStroke, lineWidth: 0.8))
        } else if #available(macOS 26.0, iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay { shape.stroke(.white.opacity(0.35), lineWidth: 0.8) }
        }
    }
}

// MARK: - Liquid Glass mit Bedienungshilfen

/// Echtes Liquid Glass (macOS 26) für Schwebendes, das selbst auf die Bedienungshilfen hört:
/// „Transparenz reduzieren“ → feste Fläche (`card`), „Kontrast erhöhen“ → sichtbarer Rand.
/// `tint` färbt das Glas leicht (z. B. `FamilyTheme.accent.opacity(0.25)` für die aktive Pille),
/// `interactive` lässt es auf Zeiger und Klick reagieren (Aufleuchten, leichtes Nachgeben).
private struct FamilyLiquidGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let increased = contrast == .increased
        Group {
            if reduceTransparency {
                // Feste Fläche; eine (halbdurchsichtige) Tönung liegt deckend darauf, nie über dem Schreibtisch.
                content
                    .background { if let tint { shape.fill(tint) } }
                    .background(shape.fill(FamilyTheme.card))
                    .overlay(shape.stroke(FamilyTheme.cardStroke, lineWidth: increased ? 1 : 0.8))
            } else if #available(macOS 26.0, iOS 26.0, *) {
                content
                    .glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
                    .overlay {
                        if increased { shape.stroke(FamilyTheme.cardStroke, lineWidth: 1) }
                    }
            } else {
                content
                    .background(.ultraThinMaterial, in: shape)
                    .overlay(shape.stroke(.white.opacity(0.35), lineWidth: 0.8))
            }
        }
    }
}

/// Animation, die „Bewegung reduzieren“ achtet: dann nur eine kurze Überblendung.
private struct FamilyAnimationModifier<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? FamilyTheme.Motion.reduced : animation, value: value)
    }
}

extension View {
    /// Liquid Glass der Familie für schwebende Bedienelemente (Leisten, Kapseln, Karten-Rahmen).
    /// Nie für Inhaltsflächen (Regel G1).
    func familyLiquidGlass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(FamilyLiquidGlassModifier(shape: shape, tint: tint, interactive: interactive))
    }

    /// `.animation(_:value:)` mit Rücksicht auf „Bewegung reduzieren“.
    func familyAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(FamilyAnimationModifier(animation: animation, value: value))
    }
}

// MARK: - Neutraler Glas-Knopf

/// Glas-Kapsel bzw. runder Glas-Knopf wie in der Vorschau: NEUTRAL, Schrift in
/// `textPrimary`. Apples `.buttonStyle(.glass)` übernimmt dagegen die Akzentfarbe
/// der App und füllt jeden Knopf blau (Kalli 0.6.0-Test, 29.09.) — für eine Leiste
/// aus mehreren Knöpfen ist das zu laut. Den Akzent trägt nur der eine aktive Knopf.
struct FamilyGlassButtonStyle: ButtonStyle {
    enum Form { case circle, capsule }
    var form: Form = .capsule
    /// Durchmesser bzw. Mindesthöhe in Punkten.
    var size: CGFloat = 26

    func makeBody(configuration: Configuration) -> some View {
        FamilyGlassButtonLabel(configuration: configuration, form: form, size: size)
    }
}

private struct FamilyGlassButtonLabel: View {
    let configuration: ButtonStyleConfiguration
    let form: FamilyGlassButtonStyle.Form
    let size: CGFloat
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let label = configuration.label
            .foregroundStyle(FamilyTheme.textPrimary)
            .opacity(isEnabled ? (configuration.isPressed ? 0.55 : 1) : 0.4)
            .contentShape(Rectangle())
        switch form {
        case .circle:
            label.frame(width: size, height: size).familyGlass(in: Circle())
        case .capsule:
            label.padding(.horizontal, size * 0.42).frame(minHeight: size).familyGlass(in: Capsule())
        }
    }
}

extension ButtonStyle where Self == FamilyGlassButtonStyle {
    static var familyGlass: FamilyGlassButtonStyle { FamilyGlassButtonStyle() }
    static func familyGlass(_ form: FamilyGlassButtonStyle.Form, size: CGFloat = 26) -> FamilyGlassButtonStyle {
        FamilyGlassButtonStyle(form: form, size: size)
    }
}

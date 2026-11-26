// App/Sources/Capture/CaptureGlassKit.swift
//
// Glas-Umbau Phase 3: gemeinsame Bausteine für alle Oberflächen rund ums Aufnehmen
// (Alles-in-einem-Leiste, Aufnahme-Werkzeugleiste, Bereichsauswahl, Scroll-HUD,
// Selbstauslöser, angeheftete Bilder). Gleiche Sprache wie die Editor-Leiste
// (AnnotationToolbar): schwebende Liquid-Glass-Kapseln, aktive Elemente als leuchtende
// Akzent-Pille, Hover hebt leicht an, Federn aus FamilyTheme.Motion.
import AppKit
import SwiftUI

enum CaptureGlass {
    /// Knopfgröße der Werkzeugknöpfe in der Editor-Leiste – überall gleich.
    static let toolButton = CGSize(width: 30, height: 26)
    /// Abstand zwischen Werkzeugknöpfen (Versatz der gleitenden Pille).
    static let toolSpacing: CGFloat = 4
}

// MARK: - Akzent-Pille

/// Leuchtende Akzent-Pille hinter dem aktiven Element. Weißes Symbol darauf
/// (`accentFill` ist für Weiß gerechnet, ≥ 4,6 : 1).
struct CaptureAccentPill<S: Shape>: View {
    var shape: S
    var glow: Bool = true

    var body: some View {
        shape
            .fill(FamilyTheme.accentFill)
            .overlay(shape.stroke(.white.opacity(0.22), lineWidth: 0.6))
            .shadow(color: FamilyTheme.accentFill.opacity(glow ? 0.55 : 0), radius: 8, y: 1)
            .accessibilityHidden(true)
    }
}

extension CaptureAccentPill where S == Capsule {
    init(glow: Bool = true) { self.init(shape: Capsule(), glow: glow) }
}

// MARK: - Hover

/// Leise Hover-Hervorhebung (neutrale Fläche), Knopf hebt sich leicht an –
/// wie in der Editor-Leiste, bei „Bewegung reduzieren“ ohne Bewegung.
private struct CaptureHoverLiftModifier<S: Shape>: ViewModifier {
    let shape: S
    var isEnabled: Bool
    var onChange: ((Bool) -> Void)?
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let lifted = isEnabled && isHovered
        content
            .background { shape.fill(Color.primary.opacity(lifted ? 0.10 : 0)) }
            .contentShape(shape)
            .scaleEffect(lifted && !reduceMotion ? 1.06 : 1)
            .offset(y: lifted && !reduceMotion ? -1 : 0)
            .onHover { hovering in
                isHovered = hovering
                onChange?(hovering)
            }
            .familyAnimation(FamilyTheme.Motion.hover, value: isHovered)
    }
}

extension View {
    /// Hover hebt an (neutrale Kapsel bzw. Form).
    func captureHoverLift(isEnabled: Bool = true, onChange: ((Bool) -> Void)? = nil) -> some View {
        modifier(CaptureHoverLiftModifier(shape: Capsule(), isEnabled: isEnabled, onChange: onChange))
    }

    func captureHoverLift<S: Shape>(in shape: S, isEnabled: Bool = true, onChange: ((Bool) -> Void)? = nil) -> some View {
        modifier(CaptureHoverLiftModifier(shape: shape, isEnabled: isEnabled, onChange: onChange))
    }

    /// Schwebende Glas-Kapsel um eine Knopfgruppe (wie `toolbarGlassPill` im Editor).
    /// `readable`: getönt, damit Beschriftung über unruhigem Bildschirm lesbar bleibt.
    func captureGlassPill(readable: Bool = false) -> some View {
        padding(.horizontal, 5)
            .padding(.vertical, 4)
            .familyLiquidGlass(in: Capsule(), tint: readable ? FamilyTheme.glassReadableTint : nil)
    }

    /// Glas-Insel mit beliebiger Form (z. B. senkrechte Leiste, Kachel).
    func captureGlassIsland<S: Shape>(in shape: S, readable: Bool = true) -> some View {
        familyLiquidGlass(in: shape, tint: readable ? FamilyTheme.glassReadableTint : nil)
    }

    /// Erscheinen schwebender Inseln: leicht vergrößert und unscharf → scharf (wie Aufnahmeleiste).
    func captureAppear(_ appeared: Bool, reduceMotion: Bool) -> some View {
        scaleEffect(appeared || reduceMotion ? 1 : 0.94)
            .blur(radius: appeared || reduceMotion ? 0 : 4)
            .opacity(appeared ? 1 : 0)
    }
}

// MARK: - Tastenkürzel-Marke

/// Kleine Marke für ein Tastenkürzel (⌘C, ⏎, Esc) im Familienton.
struct CaptureShortcutKey: View {
    let text: String
    var onAccent = false

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .foregroundStyle(onAccent ? Color.white.opacity(0.88) : FamilyTheme.textSecondary)
            .padding(.horizontal, 4)
            .frame(minHeight: 15)
            .background(Capsule().fill(onAccent ? Color.white.opacity(0.18) : FamilyTheme.textPrimary.opacity(0.08)))
            .accessibilityHidden(true)
    }
}

// MARK: - Overlay-Chrome (Maßanzeige, Hinweise, Lupenbeschriftung)

/// Kleine Glas-Kapseln über einer gezeichneten Overlay-Ansicht. Die Overlay-Ansicht
/// rechnet Lage und Größe wie bisher (AppKit-Koordinaten, Ursprung unten links) und
/// trägt sie hier ein; SwiftUI zeichnet Glas, Ziffern mit `numericText`.
/// Abdunklung, Rahmen und Fadenkreuz zeichnet die Overlay-Ansicht weiter selbst –
/// der Bildschirminhalt bleibt echt.
@MainActor
@Observable
final class CaptureOverlayChromeModel {
    struct Item: Identifiable, Equatable {
        enum Style: Equatable {
            /// Neutrale Glas-Kapsel, Ziffern gleichbreit (Maße, Koordinaten).
            case metric
            /// Leuchtende Akzent-Pille (Vorlage, Seitenverhältnis).
            case accent
            /// Glas-Kapsel mit Haupttext und leiserem Zusatz (z. B. „Frei · R zum Wechseln“).
            case hint(secondary: String?)
            /// Lupenbeschriftung: Farbfeld plus Farbwert.
            case swatch(red: Double, green: Double, blue: Double)
        }

        /// Stabil je Rolle („dimension“, „badge“ …), damit Ziffern weich wechseln statt neu zu erscheinen.
        let id: String
        var text: String
        var style: Style
        /// Rahmen in Koordinaten der Overlay-Ansicht (Ursprung unten links).
        var frame: CGRect
        var fontSize: CGFloat = 12
    }

    var items: [Item] = []
    /// Höhe der Overlay-Ansicht (für die Umrechnung in SwiftUI-Koordinaten).
    var viewHeight: CGFloat = 0

    func set(_ newItems: [Item], viewHeight: CGFloat) {
        if self.viewHeight != viewHeight { self.viewHeight = viewHeight }
        if items != newItems { items = newItems }
    }

    /// Schrift der Kapseln – dieselbe, mit der die Overlay-Ansicht die Größe misst.
    static func font(size: CGFloat, monospaced: Bool) -> NSFont {
        monospaced
            ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
            : NSFont.systemFont(ofSize: size, weight: .semibold)
    }

    /// Größe einer Kapsel für `text` (plus Polster), passend zur SwiftUI-Darstellung.
    static func capsuleSize(for text: String, fontSize: CGFloat = 12, monospaced: Bool = true,
                            horizontalPadding: CGFloat = 10, height: CGFloat = 24) -> CGSize {
        let width = (text as NSString).size(withAttributes: [.font: font(size: fontSize, monospaced: monospaced)]).width
        return CGSize(width: ceil(width) + horizontalPadding * 2 + 2, height: height)
    }
}

/// Zeichnet die Kapseln des Modells. Nimmt keine Klicks an.
struct CaptureOverlayChromeView: View {
    let model: CaptureOverlayChromeModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(model.items) { item in
                CaptureOverlayChromeCapsule(item: item)
                    .frame(width: item.frame.width, height: item.frame.height)
                    .position(x: item.frame.midX, y: model.viewHeight - item.frame.midY)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CaptureOverlayChromeCapsule: View {
    let item: CaptureOverlayChromeModel.Item

    var body: some View {
        switch item.style {
        case .metric:
            Text(verbatim: item.text)
                .font(.system(size: item.fontSize, weight: .semibold).monospacedDigit())
                .foregroundStyle(FamilyTheme.textPrimary)
                .contentTransition(.numericText())
                .familyAnimation(.snappy(duration: 0.18), value: item.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .familyLiquidGlass(in: Capsule(), tint: FamilyTheme.glassReadableTint)
        case .accent:
            Text(verbatim: item.text)
                .font(.system(size: item.fontSize - 1, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CaptureAccentPill(glow: false))
        case .hint(let secondary):
            HStack(spacing: 8) {
                Text(verbatim: item.text)
                    .font(.system(size: item.fontSize, weight: .semibold))
                    .foregroundStyle(FamilyTheme.textPrimary)
                if let secondary {
                    Text(verbatim: secondary)
                        .font(.system(size: item.fontSize, weight: .regular))
                        .foregroundStyle(FamilyTheme.textSecondary)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .familyLiquidGlass(in: Capsule(), tint: FamilyTheme.glassReadableTint)
        case .swatch(let red, let green, let blue):
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(.sRGB, red: red, green: green, blue: blue))
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(FamilyTheme.textPrimary.opacity(0.35), lineWidth: 0.8))
                Text(verbatim: item.text)
                    .font(.system(size: item.fontSize, weight: .semibold).monospacedDigit())
                    .foregroundStyle(FamilyTheme.textPrimary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .familyLiquidGlass(in: Capsule(), tint: FamilyTheme.glassReadableTint)
        }
    }
}

/// NSHostingView, die keine Maus-Ereignisse annimmt: das Overlay darunter behält
/// Ziehen, Klicks und Zeiger.
final class CapturePassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }
}

extension CaptureOverlayChromeModel {
    /// Legt die Chrome-Ebene als Unteransicht über `view` (füllt sie ganz aus).
    func install(in view: NSView) -> NSView {
        let host = CapturePassthroughHostingView(rootView: CaptureOverlayChromeView(model: self))
        host.frame = view.bounds
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        view.addSubview(host)
        return host
    }
}

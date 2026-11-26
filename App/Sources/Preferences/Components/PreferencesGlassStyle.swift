import SwiftUI

/// Schwebende Glas-Insel der Einstellungen und Nebenfenster (Glas-Umbau Phase 3).
///
/// Hell wirkte `Glass.regular` milchig-weiß, das Akzent-Licht dahinter kam kaum durch (Foto
/// 26.11.). Darum hell das klarere Glas mit leichter weißer Tönung (Lesbarkeit bleibt), dazu
/// ein feiner heller Innenrand (oben kräftig, unten verlaufend) und ein weicher Schatten, der nur
/// AUSSERHALB der Insel liegt – innen würde ihn das Glas mitbrechen und grau färben.
/// Bedienungshilfen: „Transparenz reduzieren“ → feste Karte, „Kontrast erhöhen“ → sichtbarer Rand.
struct FloatingGlassIsland<S: InsettableShape>: ViewModifier {
    let shape: S
    /// Leichte Färbung des Glases (z. B. Akzent für eine Kapsel), sonst neutral.
    var tint: Color?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let light = colorScheme == .light
        let increased = contrast == .increased
        if reduceTransparency {
            content
                .background(shape.fill(FamilyTheme.card))
                .overlay(shape.strokeBorder(FamilyTheme.cardStroke, lineWidth: increased ? 1 : 0.8))
        } else {
            content
                .glassEffect(glass(light: light), in: shape)
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(colors: [.white.opacity(light ? 0.9 : 0.24),
                                                .white.opacity(light ? 0.28 : 0.04)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
                    .allowsHitTesting(false)
                }
                .overlay {
                    if increased { shape.strokeBorder(FamilyTheme.cardStroke, lineWidth: 1) }
                }
                .background {
                    shape.fill(Color(light: 0x1E2846, dark: 0x000000).opacity(light ? 0.16 : 0.45))
                        .blur(radius: 18)
                        .offset(y: 8)
                        .mask {
                            Rectangle().padding(-80)
                                .overlay { shape.fill(.black).blendMode(.destinationOut) }
                                .compositingGroup()
                        }
                        .allowsHitTesting(false)
                }
        }
    }

    private func glass(light: Bool) -> Glass {
        if let tint { return Glass.regular.tint(tint) }
        return light ? Glass.clear.tint(Color.white.opacity(0.22)) : Glass.regular
    }
}

extension View {
    func floatingGlassIsland<S: InsettableShape>(in shape: S, tint: Color? = nil) -> some View {
        modifier(FloatingGlassIsland(shape: shape, tint: tint))
    }
}

/// Glas-Kapsel mit gleitender, leuchtender Akzent-Pille (Sprache der Einstellungs-Seitenleiste)
/// für Umschalter in Nebenfenstern: Hilfe-Dokumente, Schritte des Cloud-Assistenten.
/// `isEnabled(i) == false` → Eintrag nicht anklickbar (z. B. künftige Assistenten-Schritte).
struct GlassPillBar<Item: Hashable>: View {
    let items: [Item]
    let selection: Item
    let label: (Item) -> Text
    var icon: ((Item) -> String?)? = nil
    var isEnabled: (Item) -> Bool = { _ in true }
    let onSelect: (Item) -> Void

    @Namespace private var space
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                GlassPillSegment(
                    label: label(item), icon: icon?(item), isSelected: item == selection,
                    isEnabled: isEnabled(item), space: space
                ) {
                    guard item != selection else { return }
                    withAnimation(reduceMotion ? FamilyTheme.Motion.reduced : FamilyTheme.Motion.select) {
                        onSelect(item)
                    }
                }
            }
        }
        .padding(4)
        .floatingGlassIsland(in: Capsule(style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

private struct GlassPillSegment: View {
    let label: Text
    let icon: String?
    let isSelected: Bool
    let isEnabled: Bool
    let space: Namespace.ID
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                }
                label
                    .font(FamilyTheme.font(12, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.white
                             : FamilyTheme.textPrimary.opacity(isEnabled ? 1 : 0.42))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(FamilyTheme.accentFill.gradient)
                        .overlay(Capsule().strokeBorder(.white.opacity(contrast == .increased ? 0.6 : 0.22),
                                                        lineWidth: 0.6))
                        .shadow(color: FamilyTheme.accentFill.opacity(0.45), radius: 8, y: 2)
                        .matchedGeometryEffect(id: "pill", in: space)
                } else if isHovered && isEnabled {
                    Capsule(style: .continuous).fill(FamilyTheme.textPrimary.opacity(0.07))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
        .familyAnimation(FamilyTheme.Motion.hover, value: isHovered)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// App-Familie, Regel G1: Einstellungen sind Inhalt, kein schwebendes Element.
// Deshalb feste Flächen aus der Schiefer-Familie statt Glas (Namen der
// Modifier bleiben, damit die Aufrufer unverändert bleiben).
extension View {
    /// Feste Familien-Karte (Radius 20) mit weicher Tiefe nach Familien-Regel (Radius 18, y 8,
    /// Schieferblau 10 % hell, Schwarz dunkel) – liegt auf dem lebenden Hintergrund.
    func preferencesGlassCard(cornerRadius: CGFloat = FamilyTheme.Radius.tile) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .clipShape(shape)
            .background {
                shape.fill(FamilyTheme.card)
                    .shadow(color: Color(light: 0x1E2846, dark: 0x000000).opacity(0.10), radius: 18, y: 8)
                    .shadow(color: Color(light: 0x1E2846, dark: 0x000000).opacity(0.06), radius: 2, y: 1)
            }
            .overlay(shape.strokeBorder(FamilyTheme.cardStroke, lineWidth: 0.8))
    }

    /// Aktiver Seitenleisten-Eintrag: Akzent 14 % (Listenzeilen-Muster), Hover neutral.
    func preferencesSidebarSelectionBackground(isSelected: Bool, isHovered: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return self.background(
            shape.fill(
                isSelected ? FamilyTheme.accent.opacity(0.14) :
                isHovered ? FamilyTheme.textPrimary.opacity(0.06) : Color.clear
            )
        )
    }

    func preferencesGlassActionBackground(isHovered: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return self
            .background(shape.fill(isHovered ? FamilyTheme.backgroundMiddle : FamilyTheme.card))
            .overlay(shape.strokeBorder(FamilyTheme.cardStroke, lineWidth: 0.8))
    }
}

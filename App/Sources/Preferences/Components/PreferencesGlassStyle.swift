import SwiftUI

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

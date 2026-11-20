import SwiftUI

// App-Familie, Regel G1: Einstellungen sind Inhalt, kein schwebendes Element.
// Deshalb feste Flächen aus der Schiefer-Familie statt Glas (Namen der
// Modifier bleiben, damit die Aufrufer unverändert bleiben).
extension View {
    func preferencesGlassCard(cornerRadius: CGFloat = FamilyTheme.Radius.field) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(FamilyTheme.card, in: shape)
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

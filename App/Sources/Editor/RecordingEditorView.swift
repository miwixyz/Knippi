import SwiftUI
import EditorKit

struct RecordingEditorView: View {
    @Bindable var coordinator: EditorCoordinator

    /// Glas-Umbau Phase 2: lebender Hintergrund über die ganze Fläche (Titelleiste unsichtbar),
    /// die Vorschau als feste Karte, die Wiedergabe als schwebende Glas-Kapsel über der Zeitleiste,
    /// das Effekt-Panel als schwebende Glas-Insel wie in den Einstellungen.
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: FamilyTheme.Space.m) {
                ZStack {
                    EditorPreviewView(coordinator: coordinator)
                        .shadow(color: Self.cardShadow, radius: 18, y: 8)
                        .padding(.horizontal, FamilyTheme.Space.xl)
                        .animation(Animation.easeInOut(duration: 0.2), value: coordinator.project.backgroundStyle.enabled)
                        .animation(Animation.easeInOut(duration: 0.15), value: coordinator.project.backgroundStyle.padding)
                        .animation(Animation.easeInOut(duration: 0.15), value: coordinator.project.backgroundStyle.cornerRadius)
                        .animation(Animation.easeInOut(duration: 0.15), value: coordinator.project.backgroundStyle.shadowEnabled)

                    if coordinator.isExporting {
                        exportOverlay
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                // Platz für die Ampelknöpfe über der Vorschau.
                .padding(.top, 40)
                // Die Vorschau gibt nach, Wiedergabe und Zeitleiste behalten ihre Höhe.
                .layoutPriority(-1)

                EditorPlaybackControls(coordinator: coordinator)
                    .padding(.leading, 6)
                    .padding(.trailing, FamilyTheme.Space.m)
                    .padding(.vertical, 6)
                    .familyLiquidGlass(in: Capsule(), tint: FamilyTheme.glassLightTint)
                    .padding(.horizontal, FamilyTheme.Space.l)

                EditorTimelineView(coordinator: coordinator)
                    .padding(FamilyTheme.Space.m)
                    .frame(height: 194)
                    .familyCard(radius: FamilyTheme.Radius.tile)
                    .padding(.horizontal, FamilyTheme.Space.l)
                    .padding(.bottom, FamilyTheme.Space.l)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            EditorSettingsPanel(coordinator: coordinator)
                .frame(width: 280)
                .frame(maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .familyLiquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous),
                                   tint: FamilyTheme.glassLightTint)
                .padding(10)
        }
        .background(AmbientBackdrop(glow: 1.3).ignoresSafeArea())
        .ignoresSafeArea()
        .foregroundStyle(FamilyTheme.textPrimary)
    }

    private static let cardShadow = Color(light: 0x1E2846, dark: 0x000000).opacity(0.22)

    private var exportOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.24))
                .ignoresSafeArea()

            VStack(spacing: FamilyTheme.Space.m) {
                ProgressView(value: coordinator.exportProgress)
                    .progressViewStyle(.linear)
                    .tint(FamilyTheme.accent)
                    .frame(width: 220)

                Text(coordinator.exportStatusMessage ?? "Exporting…")
                    .font(FamilyTheme.font(13, weight: .medium))
                    .foregroundStyle(FamilyTheme.textPrimary)

                Text("The editor will close when the export is finished.")
                    .font(FamilyTheme.font(11))
                    .foregroundStyle(FamilyTheme.textSecondary)
            }
            .padding(.horizontal, FamilyTheme.Space.xl)
            .padding(.vertical, FamilyTheme.Space.l)
            // Schwebt über dem Inhalt → getöntes Glas der Familie (Regel G1 erlaubt Glas hier).
            .familyTintedGlass(in: RoundedRectangle(cornerRadius: FamilyTheme.Radius.field, style: .continuous))
        }
        .transition(.opacity)
    }
}

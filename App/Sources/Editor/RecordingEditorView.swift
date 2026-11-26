import SwiftUI
import EditorKit

struct RecordingEditorView: View {
    @Bindable var coordinator: EditorCoordinator

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ZStack {
                    EditorPreviewView(coordinator: coordinator)
                        .padding(16)
                        .animation(Animation.easeInOut(duration: 0.2), value: coordinator.project.backgroundStyle.enabled)
                        .animation(Animation.easeInOut(duration: 0.15), value: coordinator.project.backgroundStyle.padding)
                        .animation(Animation.easeInOut(duration: 0.15), value: coordinator.project.backgroundStyle.cornerRadius)
                        .animation(Animation.easeInOut(duration: 0.15), value: coordinator.project.backgroundStyle.shadowEnabled)

                    if coordinator.isExporting {
                        exportOverlay
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                hairline(vertical: false)

                VStack(spacing: FamilyTheme.Space.s) {
                    EditorPlaybackControls(coordinator: coordinator)
                    EditorTimelineView(coordinator: coordinator)
                }
                .padding(.horizontal, FamilyTheme.Space.l)
                .padding(.vertical, FamilyTheme.Space.m)
                .frame(height: 226)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            hairline(vertical: true)

            EditorSettingsPanel(coordinator: coordinator)
                .frame(width: 280)
        }
        // Fester Fensterkörper aus dem Familien-Verlauf (keine vom Schreibtisch getönte Systemfläche).
        .background(FamilyTheme.backgroundGradient.ignoresSafeArea())
        .foregroundStyle(FamilyTheme.textPrimary)
    }

    /// Feine Trennlinie statt eigenem Streifen (Design-System, Flächen).
    private func hairline(vertical: Bool) -> some View {
        Rectangle()
            .fill(FamilyTheme.cardStroke)
            .frame(width: vertical ? 0.8 : nil, height: vertical ? nil : 0.8)
    }

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

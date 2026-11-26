import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SharedKit
import ExportKit

struct EditorPlaybackControls: View {
    @Bindable var coordinator: EditorCoordinator

    var body: some View {
        HStack(spacing: FamilyTheme.Space.m) {
            // Play/Pause: runder Knopf im Akzent (Hauptbedienung der Wiedergabe).
            Button(action: { coordinator.togglePlayback() }) {
                Image(systemName: coordinator.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FamilyTheme.onAccent)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(FamilyTheme.accentFill))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])

            // Time display
            Text(coordinator.formatTime(coordinator.currentTime))
                .font(FamilyTheme.font(12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(FamilyTheme.textPrimary)

            Text("/")
                .font(FamilyTheme.font(11))
                .foregroundStyle(FamilyTheme.textSecondary)

            Text(coordinator.formatTime(coordinator.project.effectiveDuration))
                .font(FamilyTheme.font(12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(FamilyTheme.textSecondary)

            Rectangle()
                .fill(FamilyTheme.cardStroke)
                .frame(width: 0.8, height: 20)

            Menu {
                Button {
                    coordinator.addCut(at: coordinator.currentTime)
                } label: {
                    Label("Cut", systemImage: "scissors")
                }

                Button {
                    coordinator.addZoomSegment(at: coordinator.currentTime)
                } label: {
                    Label("Zoom", systemImage: "magnifyingglass")
                }

                Button {
                    coordinator.addBlurEffect(at: coordinator.currentTime)
                } label: {
                    Label("Blur", systemImage: "drop.fill")
                }
            } label: {
                Label("Add Effect", systemImage: "plus")
                    .labelStyle(.titleAndIcon)
                    .font(FamilyTheme.font(12, weight: .medium))
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            if coordinator.isExporting {
                VStack(alignment: .trailing, spacing: FamilyTheme.Space.xs) {
                    Text(coordinator.exportStatusMessage ?? "Exporting…")
                        .font(FamilyTheme.font(11, weight: .medium))
                        .foregroundStyle(FamilyTheme.textSecondary)

                    HStack(spacing: FamilyTheme.Space.s) {
                        ProgressView(value: coordinator.exportProgress)
                            .progressViewStyle(.linear)
                            .tint(FamilyTheme.accent)
                            .frame(width: 160)
                            .controlSize(.small)
                        Text("\(Int(coordinator.exportProgress * 100))%")
                            .font(FamilyTheme.font(11))
                            .monospacedDigit()
                            .foregroundStyle(FamilyTheme.textSecondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            } else {
                Button(action: { exportToClipboard() }) {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(FamilyTheme.font(12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                // Hauptaktion rechts außen (macOS-Muster), Füllung aus accentFill.
                Button(action: { exportToFile() }) {
                    Label("Save", systemImage: "square.and.arrow.down")
                        .font(FamilyTheme.font(12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(FamilyTheme.accentFill)
                .controlSize(.regular)
            }
        }
    }

    private func exportToFile() {
        let outputFormat = coordinator.outputFormat
        let panel = NSSavePanel()
        panel.allowedContentTypes = [outputFormat.contentType]
        panel.nameFieldStringValue = outputFormat.defaultFilename
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            do {
                _ = try await coordinator.exportVideo(
                    format: outputFormat.exportFormat,
                    quality: .maximum,
                    destination: url
                )
                // Close the editor window on successful export
                coordinator.closeEditor()
            } catch {
                await showExportError(error)
            }
        }
    }

    private func exportToClipboard() {
        let outputFormat = coordinator.outputFormat
        // One fixed folder whose previous file is removed on the next Copy; the file
        // has to outlive this call because the clipboard only holds its URL. Before,
        // every Copy left a file in tmp (audit E23, 21.11.).
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("KnippiClipboardExport", isDirectory: true)
        try? FileManager.default.removeItem(at: tempDir)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempURL = tempDir
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(outputFormat.fileExtension)

        Task {
            do {
                let url = try await coordinator.exportVideo(
                    format: outputFormat.exportFormat,
                    quality: .maximum,
                    destination: tempURL
                )
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([url as NSURL])
                // Close the editor window on successful export
                coordinator.closeEditor()
            } catch {
                await showExportError(error)
            }
        }
    }

    @MainActor
    private func showExportError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Export Failed")
        // localizedDescription instead of the raw enum dump (audit E24, 21.11.).
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}

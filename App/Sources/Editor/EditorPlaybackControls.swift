import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SharedKit
import ExportKit

struct EditorPlaybackControls: View {
    @Bindable var coordinator: EditorCoordinator

    var body: some View {
        HStack(spacing: 12) {
            // Play/Pause
            Button(action: { coordinator.togglePlayback() }) {
                Image(systemName: coordinator.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 30, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])

            // Time display
            Text(coordinator.formatTime(coordinator.currentTime))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            Text("/")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Text(coordinator.formatTime(coordinator.project.effectiveDuration))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)

            Divider()
                .frame(height: 18)

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
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            if coordinator.isExporting {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(coordinator.exportStatusMessage ?? "Exporting…")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ProgressView(value: coordinator.exportProgress)
                            .progressViewStyle(.linear)
                            .frame(width: 160)
                            .controlSize(.small)
                        Text("\(Int(coordinator.exportProgress * 100))%")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            } else {
                Button(action: { exportToFile() }) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(action: { exportToClipboard() }) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
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

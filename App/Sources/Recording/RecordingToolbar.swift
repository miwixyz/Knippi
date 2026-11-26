// App/Sources/Recording/RecordingToolbar.swift
import SwiftUI
import AVFoundation
import SharedKit

enum RecordingFormatChoice: String, CaseIterable {
    case video
    case gif
}

/// Microphone choice shown in the recording toolbar, restored from settings.
struct RecordingMicSelection: Equatable {
    var enabled: Bool
    var deviceID: String?

    /// Restores the last microphone choice against the devices available now.
    /// - A remembered device that is still connected stays selected.
    /// - If it's gone, the mic stays on and the system default is marked.
    /// - With no microphones at all, the mic is turned off.
    static func restored(
        enabled: Bool,
        storedDeviceID: String?,
        availableDeviceIDs: [String],
        defaultDeviceID: String?
    ) -> RecordingMicSelection {
        guard enabled, !availableDeviceIDs.isEmpty else {
            return RecordingMicSelection(enabled: false, deviceID: nil)
        }
        if let storedDeviceID, availableDeviceIDs.contains(storedDeviceID) {
            return RecordingMicSelection(enabled: true, deviceID: storedDeviceID)
        }
        if let defaultDeviceID, availableDeviceIDs.contains(defaultDeviceID) {
            return RecordingMicSelection(enabled: true, deviceID: defaultDeviceID)
        }
        return RecordingMicSelection(enabled: true, deviceID: nil)
    }
}

/// Recording toolbar with a two-section layout: controls row + action rows.
struct RecordingToolbarView: View {
    let width: Int
    let height: Int
    @Binding var cameraEnabled: Bool
    @Binding var selectedCameraID: String?
    @Binding var micEnabled: Bool
    @Binding var systemAudioEnabled: Bool
    let settings: SharedKit.AppSettings
    let onRecordVideo: () -> Void
    let onRecordGIF: () -> Void
    let onChangeArea: () -> Void
    let onCancel: () -> Void
    let onCameraSettingsChanged: () -> Void

    @State private var selectedMicID: String?
    @State private var cameraMenuRevision = 0
    @State private var showCameraPanel = false

    var body: some View {
        VStack(spacing: 0) {
            // Top section: dimensions + controls
            VStack(spacing: 8) {
                // Dimensions display
                HStack(spacing: 6) {
                    Text("\(width)")
                        .font(FamilyTheme.font(13, weight: .medium).monospacedDigit())
                        .foregroundStyle(FamilyTheme.textPrimary)
                        .frame(minWidth: 48)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(FamilyTheme.textPrimary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    Text("\u{00D7}")
                        .font(FamilyTheme.font(13))
                        .foregroundStyle(FamilyTheme.textSecondary)

                    Text("\(height)")
                        .font(FamilyTheme.font(13, weight: .medium).monospacedDigit())
                        .foregroundStyle(FamilyTheme.textPrimary)
                        .frame(minWidth: 48)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(FamilyTheme.textPrimary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    Text("px")
                        .font(FamilyTheme.font(11, weight: .medium))
                        .foregroundStyle(FamilyTheme.textSecondary)
                }

                // Controls row
                HStack(spacing: 4) {
                    // Mic menu
                    micMenuButton

                    toolbarToggle(
                        icon: systemAudioEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                        isOn: $systemAudioEnabled,
                        tooltip: "System Audio"
                    )

                    // Camera menu
                    cameraMenuButton
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            hairline

            // Action rows
            VStack(spacing: 0) {
                // Record GIF
                Button(action: onRecordGIF) {
                    HStack(spacing: 10) {
                        // Neutrale Marke statt Lila: ein Akzent pro App (G2).
                        Text("GIF")
                            .font(FamilyTheme.font(10, weight: .bold))
                            .foregroundStyle(FamilyTheme.textPrimary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(FamilyTheme.textPrimary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                        Text("Record GIF")
                            .font(FamilyTheme.font(13, weight: .medium))
                            .foregroundStyle(FamilyTheme.textPrimary)

                        Spacer()

                        HStack(spacing: 2) {
                            shortcutKey("\u{2325}")  // Option
                            shortcutKey("\u{21A9}")  // Return
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                hairline

                // Record Video
                Button(action: onRecordVideo) {
                    HStack(spacing: 10) {
                        Image(systemName: "record.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(FamilyTheme.danger)

                        Text("Record Video")
                            .font(FamilyTheme.font(13, weight: .medium))
                            .foregroundStyle(FamilyTheme.textPrimary)

                        Spacer()

                        shortcutKey("\u{21A9}")  // Return
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                hairline

                Button(action: onChangeArea) {
                    HStack(spacing: 10) {
                        Image(systemName: "selection.pin.in.out")
                            .font(.system(size: 14))
                            .foregroundStyle(FamilyTheme.textSecondary)

                        Text("Change Area")
                            .font(FamilyTheme.font(13, weight: .medium))
                            .foregroundStyle(FamilyTheme.textPrimary)

                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 240)
        .clipShape(RoundedRectangle(cornerRadius: FamilyTheme.Floating.radius, style: .continuous))
        // Familien-Schwebefläche (getöntes Glas, Hell/Dunkel), Schatten im transparenten Fensterrand.
        .familyFloatingSurface(in: RoundedRectangle(cornerRadius: FamilyTheme.Floating.radius, style: .continuous))
        .onAppear { restoreMicSelection() }
    }

    // MARK: - Mic Menu

    private var micMenuButton: some View {
        Menu {
            Button {
                micEnabled = false
                selectedMicID = nil
                persistMicSelection()
            } label: {
                if !micEnabled {
                    Label("Do Not Record Microphone", systemImage: "checkmark")
                } else {
                    Text("Do Not Record Microphone")
                }
            }

            Divider()

            ForEach(micDevices(), id: \.uniqueID) { device in
                Button {
                    micEnabled = true
                    selectedMicID = device.uniqueID
                    persistMicSelection()
                } label: {
                    if micEnabled && selectedMicID == device.uniqueID {
                        Label(device.localizedName, systemImage: "checkmark")
                    } else {
                        Text(device.localizedName)
                    }
                }
            }
        } label: {
            Image(systemName: micEnabled ? "mic.fill" : "mic.slash.fill")
                .font(.system(size: 14))
                .foregroundStyle(micEnabled ? FamilyTheme.textPrimary : FamilyTheme.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 36, height: 30)
        .background(micEnabled ? FamilyTheme.textPrimary.opacity(0.1) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .help("Microphone")
        .accessibilityLabel("Microphone")
    }

    private func restoreMicSelection() {
        let selection = RecordingMicSelection.restored(
            enabled: settings.recordingMicEnabled,
            storedDeviceID: settings.recordingMicDeviceID,
            availableDeviceIDs: micDevices().map(\.uniqueID),
            defaultDeviceID: AVCaptureDevice.default(for: .audio)?.uniqueID
        )
        micEnabled = selection.enabled
        selectedMicID = selection.deviceID
    }

    private func persistMicSelection() {
        settings.recordingMicEnabled = micEnabled
        settings.recordingMicDeviceID = micEnabled ? selectedMicID : nil
    }

    // MARK: - Camera Settings

    /// A panel that stays open while settings change (a menu closed after
    /// every click, Michael 2026-11-21). Clicking outside closes it.
    private var cameraMenuButton: some View {
        Button {
            showCameraPanel.toggle()
        } label: {
            Image(systemName: cameraEnabled ? "camera.fill" : "camera")
                .font(.system(size: 14))
                .foregroundStyle(cameraEnabled ? FamilyTheme.textPrimary : FamilyTheme.textSecondary)
                .frame(width: 36, height: 30)
                .background(cameraEnabled ? FamilyTheme.textPrimary.opacity(0.1) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Camera")
        .accessibilityLabel("Camera")
        .popover(isPresented: $showCameraPanel, arrowEdge: .bottom) {
            cameraPanel
        }
    }

    private var cameraPanel: some View {
        let _ = cameraMenuRevision
        return VStack(alignment: .leading, spacing: 12) {
            Picker("Camera", selection: Binding<String?>(
                get: { cameraEnabled ? selectedCameraID : nil },
                set: { id in
                    cameraEnabled = id != nil
                    selectedCameraID = id
                }
            )) {
                Text("None").tag(String?.none)
                ForEach(cameraDevices(), id: \.uniqueID) { device in
                    Text(device.localizedName).tag(Optional(device.uniqueID))
                }
            }

            Picker("Shape", selection: Binding<CameraShape>(
                get: { settings.cameraShape },
                set: { settings.cameraShape = $0; cameraSettingsChanged() }
            )) {
                ForEach(CameraShape.allCases, id: \.rawValue) { shape in
                    Image(systemName: shape.iconName)
                        .help(shape.displayName)
                        .accessibilityLabel(Text(shape.displayName))
                        .tag(shape)
                }
            }
            .pickerStyle(.segmented)

            Picker("Size", selection: Binding<SharedKit.CameraSize>(
                get: { settings.cameraSize },
                set: { settings.cameraSize = $0; settings.cameraCustomSizePt = 0; cameraSettingsChanged() }
            )) {
                ForEach(SharedKit.CameraSize.allCases, id: \.rawValue) { size in
                    Text(size.displayName).tag(size)
                }
            }
            .pickerStyle(.segmented)

            Divider()

            Toggle("Mirror", isOn: Binding(
                get: { settings.cameraMirror },
                set: { settings.cameraMirror = $0; cameraSettingsChanged() }
            ))
            Toggle("Fade on Hover", isOn: Binding(
                get: { settings.cameraPiPFadeOnHover },
                set: { settings.cameraPiPFadeOnHover = $0; cameraSettingsChanged() }
            ))
            Toggle("Click Through PiP", isOn: Binding(
                get: { settings.cameraPiPClickThrough },
                set: { settings.cameraPiPClickThrough = $0; cameraSettingsChanged() }
            ))
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(14)
        .frame(width: 280)
    }

    private func cameraSettingsChanged() {
        cameraMenuRevision += 1
        onCameraSettingsChanged()
    }

    // MARK: - Helpers

    /// Feine Trennlinie im Familienton (Systemtrenner wirkt auf der dunklen Glastönung grell).
    private var hairline: some View {
        Rectangle().fill(FamilyTheme.cardStroke).frame(height: 1)
    }

    private func toolbarIcon(systemName: String, active: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14))
            .foregroundStyle(active ? FamilyTheme.textPrimary : FamilyTheme.textSecondary)
            .frame(width: 36, height: 30)
            .background(active ? FamilyTheme.textPrimary.opacity(0.1) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func toolbarToggle(icon: String, isOn: Binding<Bool>, tooltip: LocalizedStringKey) -> some View {
        Button(action: { isOn.wrappedValue.toggle() }) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(isOn.wrappedValue ? FamilyTheme.textPrimary : FamilyTheme.textSecondary)
                .frame(width: 36, height: 30)
                .background(isOn.wrappedValue ? FamilyTheme.textPrimary.opacity(0.1) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .accessibilityLabel(Text(tooltip))
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }

    private func shortcutKey(_ text: String) -> some View {
        Text(text)
            .font(FamilyTheme.font(10))
            .foregroundStyle(FamilyTheme.textSecondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(FamilyTheme.textPrimary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func micDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    private func cameraDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices
    }
}

private extension CameraShape {
    var displayName: LocalizedStringKey {
        switch self {
        case .circle: "Circle"
        case .square: "Square"
        case .landscape: "Landscape (16:9)"
        case .portrait: "Portrait (9:16)"
        }
    }

    var iconName: String {
        switch self {
        case .circle: "circle"
        case .square: "square"
        case .landscape: "rectangle"
        case .portrait: "rectangle.portrait"
        }
    }
}

private extension SharedKit.CameraSize {
    var displayName: LocalizedStringKey {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }
}

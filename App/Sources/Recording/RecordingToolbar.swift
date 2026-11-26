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
    @State private var appeared = false
    @State private var recordHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Sichtbare Insel; das Fenster ist ringsum um `Floating.edge` größer (Schattenrand).
    static let islandSize = CGSize(width: 240, height: 200)

    // Glas-Umbau Phase 3: eine schwebende Glas-Insel. Oben die Maße als Kapsel, darunter
    // Mikrofon/Systemton/Kamera als Glas-Pillen (an = Akzent), dann der Start-Knopf als
    // leuchtender Akzent-Kreis, unten GIF und „Bereich ändern“ als leise Kapseln.
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Text(verbatim: "\(width) × \(height)")
                    .font(FamilyTheme.font(13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(FamilyTheme.textPrimary)
                    .contentTransition(.numericText())
                Text(verbatim: "px")
                    .font(FamilyTheme.font(11, weight: .medium))
                    .foregroundStyle(FamilyTheme.textSecondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(Capsule().fill(FamilyTheme.textPrimary.opacity(0.07)))
            .accessibilityElement(children: .combine)

            HStack(spacing: 8) {
                micMenuButton
                toolbarToggle(
                    icon: systemAudioEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                    isOn: $systemAudioEnabled,
                    tooltip: "System Audio"
                )
                cameraMenuButton
            }
            .familyAnimation(FamilyTheme.Motion.select, value: micEnabled)
            .familyAnimation(FamilyTheme.Motion.select, value: systemAudioEnabled)
            .familyAnimation(FamilyTheme.Motion.select, value: cameraEnabled)

            recordButton

            HStack(spacing: 6) {
                Button(action: onRecordGIF) {
                    HStack(spacing: 6) {
                        Text(verbatim: "GIF")
                            .font(FamilyTheme.font(11, weight: .bold))
                            .foregroundStyle(FamilyTheme.textPrimary)
                        HStack(spacing: 2) {
                            CaptureShortcutKey(text: "\u{2325}")  // Option
                            CaptureShortcutKey(text: "\u{21A9}")  // Return
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Capsule().fill(FamilyTheme.textPrimary.opacity(0.07)))
                    .captureHoverLift()
                }
                .buttonStyle(.plain)
                .help("Record GIF")
                .accessibilityLabel(Text("Record GIF"))

                Button(action: onChangeArea) {
                    HStack(spacing: 5) {
                        Image(systemName: "selection.pin.in.out")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(FamilyTheme.textSecondary)
                        Text("Change Area")
                            .font(FamilyTheme.font(11, weight: .semibold))
                            .foregroundStyle(FamilyTheme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Capsule().fill(FamilyTheme.textPrimary.opacity(0.07)))
                    .captureHoverLift()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 14)
        .frame(width: Self.islandSize.width, height: Self.islandSize.height)
        .familyLiquidGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous),
                           tint: FamilyTheme.glassReadableTint)
        .captureAppear(appeared, reduceMotion: reduceMotion)
        .padding(FamilyTheme.Floating.edge)
        .onAppear {
            restoreMicSelection()
            withAnimation(reduceMotion ? FamilyTheme.Motion.reduced : FamilyTheme.Motion.appear) { appeared = true }
        }
    }

    /// Start: leuchtender Akzent-Kreis mit Aufnahmepunkt, daneben „Video aufnehmen ⏎“.
    private var recordButton: some View {
        Button(action: onRecordVideo) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(FamilyTheme.accentFill)
                        .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 0.8))
                        .shadow(color: FamilyTheme.accentFill.opacity(recordHovered ? 0.75 : 0.5),
                                radius: recordHovered ? 12 : 8, y: 1)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 15, height: 15)
                }
                .frame(width: 44, height: 44)
                .scaleEffect(recordHovered && !reduceMotion ? 1.06 : 1)

                Text("Record Video")
                    .font(FamilyTheme.font(13, weight: .semibold))
                    .foregroundStyle(FamilyTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                CaptureShortcutKey(text: "\u{21A9}")  // Return
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .frame(width: 216, height: 56)
            .background(Capsule().fill(FamilyTheme.textPrimary.opacity(recordHovered ? 0.08 : 0.04)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { recordHovered = $0 }
        .familyAnimation(FamilyTheme.Motion.hover, value: recordHovered)
        .help("Record Video")
        .accessibilityLabel(Text("Record Video"))
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
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(micEnabled ? Color.white : FamilyTheme.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        // Ein Menü-Etikett zeichnet keine eigene Fläche – die Pille liegt deshalb außen.
        .frame(width: 52, height: 30)
        .background {
            if micEnabled {
                CaptureAccentPill()
            } else {
                Capsule().fill(FamilyTheme.textPrimary.opacity(0.07))
            }
        }
        .captureHoverLift(isEnabled: !micEnabled)
        .help("Microphone")
        .accessibilityLabel("Microphone")
        .accessibilityValue(Text(micEnabled ? "On" : "Off"))
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
            togglePillFace(icon: cameraEnabled ? "camera.fill" : "camera", isOn: cameraEnabled)
        }
        .buttonStyle(.plain)
        .help("Camera")
        .accessibilityLabel("Camera")
        .accessibilityValue(Text(cameraEnabled ? "On" : "Off"))
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

    /// Schalter-Pille: an = leuchtende Akzent-Pille mit weißem Symbol, aus = leise Fläche
    /// (feste Fläche auf der Glas-Insel, kein Glas auf Glas). Farbe ist nicht das einzige
    /// Signal: das Symbol wechselt mit (durchgestrichen bzw. umrandet).
    private func togglePillFace(icon: String, isOn: Bool) -> some View {
        Image(systemName: icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isOn ? Color.white : FamilyTheme.textSecondary)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 52, height: 30)
            .background {
                if isOn {
                    CaptureAccentPill()
                } else {
                    Capsule().fill(FamilyTheme.textPrimary.opacity(0.07))
                }
            }
            .captureHoverLift(isEnabled: !isOn)
    }

    private func toolbarToggle(icon: String, isOn: Binding<Bool>, tooltip: LocalizedStringKey) -> some View {
        Button(action: { isOn.wrappedValue.toggle() }) {
            togglePillFace(icon: icon, isOn: isOn.wrappedValue)
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .accessibilityLabel(Text(tooltip))
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
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

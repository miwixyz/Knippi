// App/Sources/Preferences/Tabs/ScreenshotSettingsView.swift
import SwiftUI
import SharedKit

struct ScreenshotSettingsView: View {
    @Bindable var viewModel: PreferencesViewModel

    @State private var showingAddPreset = false
    @State private var newPresetType = 0  // 0 = aspect ratio, 1 = fixed size
    @State private var newWidth = ""
    @State private var newHeight = ""
    @State private var newName = ""
    /// Draft of the timestamp color: the setting normalizes every write, so binding
    /// the field directly turned "#F" into "#FFFFFF" mid-typing. Only a full,
    /// valid hex is written; Return on an invalid value restores the stored one.
    @State private var timestampColorDraft: String?
    @AppStorage(SensitiveSuggestionsModel.findFacesKey) private var findFaces = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Screenshots")
                .font(FamilyTheme.font(20, weight: .semibold))

            SettingGroup(title: "After Capture") {
                SettingCard {
                    SettingRow(label: "Behavior", sublabel: afterCaptureDescription) {
                        Picker("", selection: $viewModel.afterCaptureMode) {
                            Text("Show preview").tag(AfterCaptureMode.preview)
                            Text("Open editor").tag(AfterCaptureMode.editor)
                            Text("Silent").tag(AfterCaptureMode.silent)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    // The mode is the source of truth: the per-step toggles only apply to "Show preview"
                    // ("Open editor" skips them, "Silent" always copies and saves).
                    if viewModel.afterCaptureMode == .preview {
                        // Kein Doppel zum Modus: Im Modus „Vorschau zeigen“ schaltet dieser Schalter nur
                        // die Miniatur ab; Kopieren und Sichern laufen dann still nach den Schaltern unten
                        // (CaptureCoordinator, Fall .default). „Still“ dagegen kopiert und sichert immer.
                        SettingRow(
                            label: "Show Thumbnail",
                            sublabel: "Off: only copy or save as set below, without a thumbnail",
                            showDivider: true
                        ) {
                            Toggle("", isOn: $viewModel.screenshotShowPreview)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                        SettingRow(label: "Copy to Clipboard", sublabel: "Copy screenshot immediately", showDivider: true) {
                            Toggle("", isOn: $viewModel.screenshotAutoCopy)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                    }
                    SettingRow(
                        label: "Clipboard Content",
                        sublabel: clipboardContentDescription,
                        showDivider: true
                    ) {
                        Picker("", selection: $viewModel.screenshotClipboardContent) {
                            Text("Image").tag(ScreenshotClipboardContent.image)
                            Text("File Path").tag(ScreenshotClipboardContent.filePath)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    if viewModel.screenshotClipboardContent == .image {
                        SettingRow(
                            label: "Clipboard Format",
                            sublabel: "Used whenever a screenshot is copied",
                            showDivider: true
                        ) {
                            Picker("", selection: $viewModel.screenshotClipboardFormat) {
                                Text("PNG").tag(ScreenshotClipboardFormat.png)
                                Text("JPEG").tag(ScreenshotClipboardFormat.jpeg)
                                Text("TIFF").tag(ScreenshotClipboardFormat.tiff)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    if viewModel.afterCaptureMode == .preview {
                        SettingRow(label: "Auto Save", sublabel: "Save to file automatically", showDivider: true) {
                            Toggle("", isOn: $viewModel.screenshotAutoSave)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                    }
                }
            }

            SettingGroup(title: "Capture") {
                SettingCard {
                    SettingRow(label: "Show Cursor", sublabel: "Include the mouse pointer in screenshots") {
                        Toggle("", isOn: $viewModel.screenshotShowsCursor)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    SettingRow(label: "Capture Window Shadow", sublabel: "Include shadow in window captures", showDivider: true) {
                        Toggle("", isOn: $viewModel.captureWindowShadow)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    if viewModel.captureWindowShadow {
                        SettingRow(
                            label: "Window Background",
                            sublabel: "What surrounds a captured window",
                            showDivider: true
                        ) {
                            Picker("", selection: $viewModel.windowCaptureBackground) {
                                Text("Transparent with Shadow").tag(WindowCaptureBackground.transparentShadow)
                                Text("Frosted Glass").tag(WindowCaptureBackground.frostedGlass)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    SettingRow(label: "Pixel Magnifier", sublabel: "Show a magnified pixel view while selecting an area", showDivider: true) {
                        Toggle("", isOn: $viewModel.showMagnifier)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    SettingRow(label: "Color Format", sublabel: "Used when copying a picked color", showDivider: true) {
                        Picker("", selection: $viewModel.colorFormat) {
                            ForEach(ColorFormat.allCases, id: \.self) { format in
                                Text(verbatim: format.displayName).tag(format)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    // TODO: Re-enable rememberLastCaptureArea once implemented.
                }
            }

            SettingGroup(title: "Screenshot History") {
                SettingCard {
                    SettingRow(
                        label: "Keep History",
                        sublabel: "Recent screenshots from the export folder, searchable by the text in them. Off by default."
                    ) {
                        Picker("", selection: $viewModel.historyKeepCount) {
                            Text("Off").tag(0)
                            ForEach(AppSettings.historyKeepChoices, id: \.self) { count in
                                Text("\(count)").tag(count)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    SettingRow(
                        label: "Search Index",
                        sublabel: "The text Knippi read is kept unencrypted on this Mac, readable only by you, and may end up in backups. Deleting it removes that text; it is read again when you next open the history.",
                        showDivider: true
                    ) {
                        Button("Delete Index") { viewModel.deleteHistoryIndex() }
                    }
                }
            }

            SettingGroup(title: "Sensitive Data") {
                SettingCard {
                    SettingRow(
                        label: "Also Look for Faces",
                        sublabel: "Finds clearly visible faces. Small or partly hidden ones can be missed, so please check."
                    ) {
                        Toggle("", isOn: $findFaces)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }
            }

            SettingGroup(title: "Timestamp") {
                SettingCard {
                    SettingRow(label: "Add Timestamp", sublabel: "Draw the capture time onto screenshots") {
                        Toggle("", isOn: $viewModel.screenshotTimestampEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }

                    if viewModel.screenshotTimestampEnabled {
                        SettingRow(label: "Position", showDivider: true) {
                            Picker("", selection: $viewModel.screenshotTimestampPosition) {
                                ForEach(ScreenshotTimestampPosition.allCases, id: \.self) { position in
                                    Text(position.displayName).tag(position)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 150)
                        }

                        SettingRow(label: "Format", showDivider: true) {
                            Picker("", selection: $viewModel.screenshotTimestampFormat) {
                                ForEach(ScreenshotTimestampFormat.allCases, id: \.self) { format in
                                    Text(format.displayName).tag(format)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 150)
                        }

                        SettingRow(label: "Color", showDivider: true) {
                            TextField("#FFFFFF", text: Binding(
                                get: { timestampColorDraft ?? viewModel.screenshotTimestampColorHex },
                                set: { draft in
                                    timestampColorDraft = draft
                                    if let hex = ScreenshotTimestampOptions.normalizedColorHex(draft) {
                                        viewModel.screenshotTimestampColorHex = hex
                                    }
                                }
                            ))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 88)
                                .onSubmit { timestampColorDraft = nil }
                        }

                        SettingRow(label: "Font Size", showDivider: true) {
                            HStack(spacing: 8) {
                                Text("\(viewModel.screenshotTimestampFontSize) pt")
                                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                                    .frame(minWidth: 42, alignment: .trailing)
                                Stepper(
                                    "",
                                    value: $viewModel.screenshotTimestampFontSize,
                                    in: ScreenshotTimestampOptions.fontSizeRange
                                )
                                .labelsHidden()
                            }
                        }
                    }
                }
            }

            SettingGroup(title: "Beautify") {
                SettingCard {
                    SettingRow(
                        label: "Beautify Every Screenshot",
                        sublabel: "Uses the background, padding, corners and shadow last set in the editor's Beautify panel"
                    ) {
                        Toggle("", isOn: $viewModel.autoBeautifyScreenshots)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }
            }

            SettingGroup(title: "Self-Timer") {
                SettingCard {
                    SettingRow(
                        label: "Default Duration",
                        sublabel: "Delay before the screenshot fires"
                    ) {
                        HStack(spacing: 8) {
                            Text("\(viewModel.selfTimerDurationSeconds)s")
                                .font(.system(size: 13, weight: .medium).monospacedDigit())
                                .frame(minWidth: 32, alignment: .trailing)
                            Stepper(
                                "",
                                value: $viewModel.selfTimerDurationSeconds,
                                in: AppSettings.selfTimerDurationRange
                            )
                            .labelsHidden()
                        }
                    }
                    SettingRow(
                        label: "Tick Sound",
                        sublabel: "Play a sound on each second of the countdown",
                        showDivider: true
                    ) {
                        Toggle("", isOn: $viewModel.selfTimerPlayTickSound)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }

                Text("Useful for capturing menus, hover states, and other UI that disappears the moment you move the mouse.")
                    .font(FamilyTheme.font(11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

            SettingGroup(title: "Capture Presets") {
                SettingCard {
                    SettingRow(
                        label: "Capture Presets",
                        sublabel: "Constrain area capture to preset aspect ratios or fixed sizes"
                    ) {
                        Toggle("", isOn: $viewModel.capturePresetsEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }

                if viewModel.capturePresetsEnabled {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Press **R** to cycle presets during area capture", systemImage: "keyboard")
                        Label("**Right-click** to open the preset picker", systemImage: "cursorarrow.click.2")
                        Label("**Shift + R** to cycle in reverse", systemImage: "arrow.left.arrow.right")
                    }
                    .font(FamilyTheme.font(11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)

                    SettingCard {
                    // Built-in aspect ratios (skip .freeform)
                    let aspectRatios = CapturePreset.builtinAspectRatios.filter {
                        if case .freeform = $0 { return false }
                        return true
                    }
                    ForEach(Array(aspectRatios.enumerated()), id: \.element.id) { index, preset in
                        let isHidden = viewModel.hiddenBuiltinPresets.contains(preset)
                        SettingRow(
                            label: "\(Self.presetLabel(preset))",
                            showDivider: index > 0
                        ) {
                            Toggle("", isOn: Binding(
                                get: { !isHidden },
                                set: { isOn in
                                    if isOn {
                                        viewModel.hiddenBuiltinPresets.remove(preset)
                                    } else {
                                        viewModel.hiddenBuiltinPresets.insert(preset)
                                    }
                                }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }
                    }

                    // Built-in fixed sizes
                    ForEach(Array(CapturePreset.builtinFixedSizes.enumerated()), id: \.element.id) { index, preset in
                        let isHidden = viewModel.hiddenBuiltinPresets.contains(preset)
                        SettingRow(
                            label: "\(Self.presetLabel(preset))",
                            showDivider: true
                        ) {
                            Toggle("", isOn: Binding(
                                get: { !isHidden },
                                set: { isOn in
                                    if isOn {
                                        viewModel.hiddenBuiltinPresets.remove(preset)
                                    } else {
                                        viewModel.hiddenBuiltinPresets.insert(preset)
                                    }
                                }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }
                    }

                    // Custom presets
                    ForEach(viewModel.customCapturePresets) { preset in
                        SettingRow(
                            label: "\(preset.displayName)",
                            showDivider: true
                        ) {
                            Button {
                                viewModel.customCapturePresets.removeAll { $0.id == preset.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(FamilyTheme.danger)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                    Button("Add Custom Preset") {
                        showingAddPreset = true
                    }
                    .buttonStyle(.plain)
                    .font(FamilyTheme.font(13))
                    .foregroundStyle(FamilyTheme.accent)
                    .padding(.leading, 2)
                } // if capturePresetsEnabled
            }

        }
        .sheet(isPresented: $showingAddPreset) {
            addPresetSheet
        }
    }

    /// Anzeigename einer eingebauten Vorgabe. Der Name „Square“ stammt aus SharedKit
    /// (`CapturePreset.builtinAspectRatios`) und wäre sonst unübersetzt; eigene Vorgaben
    /// zeigen den Namen, den der Nutzer eingegeben hat.
    static func presetLabel(_ preset: CapturePreset) -> String {
        if case .aspectRatio(1, 1, .some("Square")) = preset {
            return String(localized: "1:1 (Square)", comment: "Built-in capture preset, square aspect ratio")
        }
        return preset.displayName
    }

    private var afterCaptureDescription: LocalizedStringKey {
        switch viewModel.afterCaptureMode {
        case .preview:
            "Show a thumbnail with quick actions"
        case .editor:
            "Open the annotation editor right away"
        case .silent:
            "Copy to the clipboard and save to the output folder, nothing else"
        }
    }

    private var clipboardContentDescription: LocalizedStringKey {
        switch viewModel.screenshotClipboardContent {
        case .image:
            "Copy image data to the clipboard"
        case .filePath:
            "Copy the saved path, or keep a temporary file for 24 hours"
        }
    }

    // MARK: - Add Preset Sheet

    @ViewBuilder
    private var addPresetSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add Custom Preset")
                .font(FamilyTheme.font(17, weight: .semibold))

            Picker("", selection: $newPresetType) {
                Text("Aspect Ratio").tag(0)
                Text("Fixed Size").tag(1)
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(newPresetType == 0 ? LocalizedStringKey("Width ratio") : LocalizedStringKey("Width (px)"))
                            .font(FamilyTheme.font(12))
                            .foregroundStyle(.secondary)
                        TextField("e.g. 16", text: $newWidth)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(newPresetType == 0 ? LocalizedStringKey("Height ratio") : LocalizedStringKey("Height (px)"))
                            .font(FamilyTheme.font(12))
                            .foregroundStyle(.secondary)
                        TextField("e.g. 9", text: $newHeight)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey("Name (optional)"))
                        .font(FamilyTheme.font(12))
                        .foregroundStyle(.secondary)
                    TextField("e.g. Widescreen", text: $newName)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Button("Cancel") {
                    showingAddPreset = false
                    resetNewPresetFields()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    addCustomPreset()
                    showingAddPreset = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(Int(newWidth) == nil || Int(newHeight) == nil)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    // MARK: - Helpers

    private func addCustomPreset() {
        guard let w = Int(newWidth), let h = Int(newHeight) else { return }
        let name: String? = newName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : newName.trimmingCharacters(in: .whitespaces)
        let preset: CapturePreset = newPresetType == 0
            ? .aspectRatio(width: w, height: h, name: name)
            : .fixedSize(width: w, height: h, name: name)
        viewModel.customCapturePresets.append(preset)
        resetNewPresetFields()
    }

    private func resetNewPresetFields() {
        newPresetType = 0
        newWidth = ""
        newHeight = ""
        newName = ""
    }
}

// App/Sources/AnnotationEditor/BeautifyPanel.swift
import SwiftUI
import UniformTypeIdentifiers

struct BeautifyPanel: View {
    @Binding var settings: BeautifySettings

    // Curated palette: 4 neutrals + 4 soft pastels. The full macOS colour
    // picker is still available next to the swatches for anything else.
    private let presetColors: [Color] = [
        .white,
        Color(nsColor: NSColor(calibratedWhite: 0.96, alpha: 1)),
        Color(nsColor: NSColor(calibratedWhite: 0.18, alpha: 1)),
        .black,
        Color(nsColor: NSColor(srgbRed: 0.729, green: 0.902, blue: 0.992, alpha: 1)), // sky blue
        Color(nsColor: NSColor(srgbRed: 0.996, green: 0.843, blue: 0.663, alpha: 1)), // peach
        Color(nsColor: NSColor(srgbRed: 0.733, green: 0.969, blue: 0.816, alpha: 1)), // mint
        Color(nsColor: NSColor(srgbRed: 0.867, green: 0.839, blue: 0.996, alpha: 1)), // lavender
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Enable background", isOn: $settings.isEnabled)

            if settings.isEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    // -- Appearance --
                    settingRow("Style") {
                        Picker("", selection: basicStyleBinding) {
                            ForEach(BasicStyle.allCases) { style in
                                Text(style.label).tag(Optional(style))
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }

                    settingRow("Gradients") {
                        HStack(spacing: FamilyTheme.Space.s) {
                            ForEach(BeautifyGradient.allCases) { gradient in
                                gradientTile(gradient)
                            }
                        }
                    }

                    settingRow("Image") {
                        customImageButton
                    }

                    if settings.backgroundStyle == .solid {
                        settingRow("Background") {
                            HStack(spacing: 4) {
                                ForEach(Array(presetColors.enumerated()), id: \.offset) { _, color in
                                    colorSwatch(color)
                                }
                                ColorPicker("", selection: $settings.backgroundColor, supportsOpacity: false)
                                    .labelsHidden()
                            }
                        }
                    }

                    settingRow("Format") {
                        Picker("", selection: $settings.aspect) {
                            ForEach(BeautifyAspect.allCases) { aspect in
                                Text(verbatim: aspect.label).tag(aspect)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }

                    Divider()
                        .padding(.vertical, 1)

                    // -- Dimensions --
                    sliderRow("Padding", value: $settings.padding, range: 0...80)
                    sliderRow("Corners", value: $settings.cornerRadius, range: 0...24)

                    Divider()
                        .padding(.vertical, 1)

                    // -- Shadow --
                    HStack(spacing: 8) {
                        Toggle(isOn: $settings.shadowEnabled) {
                            Text("Shadow")
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 80, alignment: .leading)

                        Slider(value: $settings.shadowRadius, in: 0...40, step: 1)
                            .disabled(!settings.shadowEnabled)

                        valueLabel(Int(settings.shadowRadius))
                    }
                    .opacity(settings.shadowEnabled ? 1 : 0.55)
                    .animation(.easeInOut(duration: 0.15), value: settings.shadowEnabled)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
        .animation(.easeInOut(duration: 0.2), value: settings.isEnabled)
        .animation(.easeInOut(duration: 0.15), value: settings.backgroundStyle)
    }

    // MARK: - Background choices

    /// The three plain styles; gradient and image are picked in their own row,
    /// so the segmented control shows no selection for them.
    private enum BasicStyle: CaseIterable, Identifiable {
        case solid, liquidGlass, none
        var id: Self { self }
        var label: LocalizedStringKey {
            switch self {
            case .solid: "Solid"
            case .liquidGlass: "Liquid Glass"
            case .none: "None"
            }
        }
        var style: BeautifyBackgroundStyle {
            switch self {
            case .solid: .solid
            case .liquidGlass: .liquidGlass
            case .none: .none
            }
        }
    }

    private var basicStyleBinding: Binding<BasicStyle?> {
        Binding(
            get: { BasicStyle.allCases.first { $0.style == settings.backgroundStyle } },
            set: { if let style = $0 { settings.backgroundStyle = style.style } }
        )
    }

    private func gradientTile(_ gradient: BeautifyGradient) -> some View {
        let selected = settings.backgroundStyle == .gradient(gradient)
        return Button {
            settings.backgroundStyle = .gradient(gradient)
        } label: {
            Group {
                if let preview = BeautifyGradients.image(gradient, width: 88, height: 56) {
                    Image(decorative: preview, scale: 2)
                        .resizable()
                } else {
                    Color.gray
                }
            }
            .frame(width: 44, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
            .padding(2)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(FamilyTheme.accent, lineWidth: selected ? 1.5 : 0)
            )
        }
        .buttonStyle(.plain)
        .help(gradient.label)
        .accessibilityLabel(Text(verbatim: gradient.label))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var customImageButton: some View {
        let selectedURL: URL? = if case .image(let url) = settings.backgroundStyle { url } else { nil }
        return Button(action: chooseCustomImage) {
            Label {
                Text(selectedURL.map { $0.lastPathComponent } ?? String(localized: "Custom Image…"))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 140)
            } icon: {
                Image(systemName: "photo")
            }
        }
        .controlSize(.small)
        .help(selectedURL?.path ?? String(localized: "Choose a picture as background"))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(FamilyTheme.accent, lineWidth: selectedURL != nil ? 1.5 : 0)
                .padding(-2)
        )
    }

    private func chooseCustomImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = String(localized: "Choose a picture as background")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.backgroundStyle = .image(url)
    }

    // MARK: - Reusable Components

    private func settingRow<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func sliderRow(
        _ title: LocalizedStringKey,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Slider(value: value, in: range, step: 1)
            valueLabel(Int(value.wrappedValue))
        }
    }

    private func valueLabel(_ value: Int) -> some View {
        Text("\(value)")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.tertiary)
            .frame(width: 28, alignment: .trailing)
    }

    private func colorSwatch(_ color: Color) -> some View {
        let selected = isColorMatch(color, settings.backgroundColor)
        return Button {
            settings.backgroundColor = color
        } label: {
            Circle()
                .fill(color)
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                .padding(2)
                .overlay(
                    Circle()
                        .strokeBorder(Color.accentColor, lineWidth: selected ? 1.5 : 0)
                )
        }
        .buttonStyle(.plain)
    }

    private func isColorMatch(_ a: Color, _ b: Color) -> Bool {
        guard let c1 = NSColor(a).usingColorSpace(.sRGB),
              let c2 = NSColor(b).usingColorSpace(.sRGB) else { return false }
        return abs(c1.redComponent - c2.redComponent) < 0.02
            && abs(c1.greenComponent - c2.greenComponent) < 0.02
            && abs(c1.blueComponent - c2.blueComponent) < 0.02
    }
}

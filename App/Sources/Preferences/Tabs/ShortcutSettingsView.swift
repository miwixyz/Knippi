// App/Sources/Preferences/Tabs/ShortcutSettingsView.swift
import SwiftUI
import AppKit
import KeyboardShortcuts
import SharedKit

extension KeyboardShortcuts.Name {
    static let captureAllInOne = Self("captureAllInOne")
    static let captureArea = Self("captureArea", initial: .init(.one, modifiers: [.option, .shift]))
    static let captureFullscreen = Self("captureFullscreen", initial: .init(.two, modifiers: [.option, .shift]))
    static let captureWindow = Self("captureWindow", initial: .init(.three, modifiers: [.option, .shift]))
    static let captureText = Self("captureText", initial: .init(.four, modifiers: [.option, .shift]))
    /// Keep the existing storage key so current users retain their recording shortcut.
    static let recordScreen = Self("recordScreen", initial: .init(.five, modifiers: [.option, .shift]))
    /// Opt-in to avoid adding another default global shortcut.
    static let recordFullscreen = Self("recordFullscreen")
    static let captureScrolling = Self("captureScrolling", initial: .init(.six, modifiers: [.option, .shift]))
    static let captureAreaToClipboard = Self("captureAreaToClipboard", initial: .init(.seven, modifiers: [.option, .shift]))
    static let captureAreaAndShare = Self("captureAreaAndShare", initial: .init(.zero, modifiers: [.option, .shift]))
    static let captureAreaAndAnnotate = Self("captureAreaAndAnnotate", initial: .init(.eight, modifiers: [.option, .shift]))
    static let captureAreaAndPin = Self("captureAreaAndPin")
    static let pickColor = Self("pickColor", initial: .init(.nine, modifiers: [.option, .shift]))
    static let pinFromClipboard = Self("pinFromClipboard")
    static let editClipboardImage = Self("editClipboardImage")
    /// No default binding — opt-in. Self-Timer is discoverable from the
    /// menu bar; shipping a default risks colliding with whatever the user
    /// has already bound in macOS or third-party apps.
    static let selfTimerCapture = Self("selfTimerCapture")
    /// Replays the last capture (area / window / fullscreen) without showing
    /// the selection overlay. Unbound by default — user must assign a key.
    static let captureLastArea = Self("captureLastArea")
    /// Unbound by default.
    static let togglePins = Self("togglePins")
    /// Opens the screenshot history. Opens a window only, so a default is harmless (option + shift + H).
    static let openHistory = Self("openHistory", initial: .init(.h, modifiers: [.option, .shift]))

    static let allKnippi: [Self] = [
        .captureAllInOne, .captureArea, .captureFullscreen, .captureWindow, .captureText, .recordScreen,
        .recordFullscreen, .captureScrolling, .captureAreaToClipboard, .captureAreaAndShare,
        .captureAreaAndAnnotate, .captureAreaAndPin, .pickColor, .pinFromClipboard, .editClipboardImage,
        .selfTimerCapture, .captureLastArea, .togglePins, .openHistory,
    ]
}

struct ShortcutSettingsView: View {
    @Bindable var viewModel: PreferencesViewModel
    private struct ContextualShortcut: Identifiable {
        let id: String
        let scope: LocalizedStringKey
        let action: LocalizedStringKey
        /// One or more keycaps to render for this action. `.copy` in
        /// All-in-One lists all three bindings (⌘C, Return, ⌘⇧C) so users
        /// discover Return and ⌘⇧C alongside ⌘C — see issue #237.
        let shortcuts: [String]
    }

    private let contextualShortcuts: [ContextualShortcut] = [
        ContextualShortcut(id: "all-in-one-copy", scope: "All-in-One", action: "Copy selected area", shortcuts: ["⌘C", "⏎", "⌘⇧C"]),
        ContextualShortcut(id: "all-in-one-save", scope: "All-in-One", action: "Save selected area", shortcuts: ["⌘S"]),
        ContextualShortcut(id: "all-in-one-pin", scope: "All-in-One", action: "Pin selected area", shortcuts: ["⌘P"]),
        ContextualShortcut(id: "all-in-one-cancel", scope: "All-in-One", action: "Cancel", shortcuts: ["Esc"]),
        ContextualShortcut(id: "window-multi-select", scope: "Window Capture", action: "Select multiple windows", shortcuts: [String(localized: "⇧ + click", comment: "Keycap: hold Shift and click")]),
        ContextualShortcut(id: "window-multi-confirm", scope: "Window Capture", action: "Capture selected windows", shortcuts: [String(localized: "Release ⇧", comment: "Keycap: let go of the Shift key")]),
        ContextualShortcut(id: "quick-access-copy", scope: "Quick Access", action: "Copy", shortcuts: ["⌘C"]),
        ContextualShortcut(id: "quick-access-save", scope: "Quick Access", action: "Save", shortcuts: ["⌘S"]),
        ContextualShortcut(id: "quick-access-annotate", scope: "Quick Access", action: "Annotate", shortcuts: ["⌘E"]),
        ContextualShortcut(id: "quick-access-pin", scope: "Quick Access", action: "Pin", shortcuts: ["⌘P"])
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PreferencesTabHeader(tab: .shortcuts)

            // Info banner
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(FamilyTheme.accent)
                Text("Click a customizable shortcut to record a new combination. Press Esc to cancel or Delete to remove. Contextual shortcuts are fixed and work only while that panel is active.")
                    .font(FamilyTheme.font(12))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FamilyTheme.accent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: FamilyTheme.Radius.field, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FamilyTheme.Radius.field, style: .continuous)
                    .stroke(FamilyTheme.accent.opacity(0.26), lineWidth: 0.5)
            )

            SystemScreenshotShortcutsCard()

            SettingGroup(title: "Customizable Shortcuts") {
                SettingCard {
                    shortcutRow("All-in-One", name: .captureAllInOne)
                    shortcutRow("Capture Area", name: .captureArea, showDivider: true)
                    shortcutRow("Capture Fullscreen", name: .captureFullscreen, showDivider: true)
                    shortcutRow("Capture Window", name: .captureWindow, showDivider: true)
                    shortcutRow("Capture Text (OCR)", name: .captureText, showDivider: true)
                    if FeatureFlags.scrollingCapture {
                        shortcutRow("Scrolling Capture", name: .captureScrolling, showDivider: true)
                    }
                    shortcutRow("Self-Timer", name: .selfTimerCapture, showDivider: true)
                    shortcutRow("Capture Area to Clipboard", name: .captureAreaToClipboard, showDivider: true)
                    shortcutRow("Capture and Share to Cloud", name: .captureAreaAndShare, showDivider: true)
                    shortcutRow("Capture Area & Annotate", name: .captureAreaAndAnnotate, showDivider: true)
                    shortcutRow("Capture Area & Pin", name: .captureAreaAndPin, showDivider: true)
                    shortcutRow(
                        "Pick Color",
                        name: .pickColor,
                        showDivider: true,
                        help: "Copy the color under the pointer, magnified pixel by pixel"
                    )
                    shortcutRow(
                        "Pin from Clipboard",
                        name: .pinFromClipboard,
                        showDivider: true,
                        help: "Float copied images, text, colors, or files above other windows"
                    )
                    shortcutRow(
                        "Edit Clipboard Image",
                        name: .editClipboardImage,
                        showDivider: true,
                        help: "Open the image currently copied to the clipboard in Annotate"
                    )
                    shortcutRow("Hide / Show All Pins", name: .togglePins, showDivider: true)
                    shortcutRow("Capture Previous Area", name: .captureLastArea, showDivider: true)
                    shortcutRow(
                        "Screenshot History",
                        name: .openHistory,
                        showDivider: true,
                        help: "Open the recent screenshots and search the text in them"
                    )
                    if FeatureFlags.screenRecording {
                        shortcutRow("Record Area", name: .recordScreen, showDivider: true)
                        shortcutRow("Record Full Screen", name: .recordFullscreen, showDivider: true)
                    }
                }
            }

            SettingGroup(title: "Contextual Shortcuts") {
                SettingCard {
                    centerLockRow
                    ForEach(Array(contextualShortcuts.enumerated()), id: \.element.id) { _, item in
                        contextualShortcutRow(item, showDivider: true)
                    }
                }
            }
        }
    }

    private var centerLockRow: some View {
        SettingRow(
            label: "Center 1:1 from click",
            sublabel: "Selection",
            showDivider: false
        ) {
            HStack(spacing: 6) {
                ShortcutKeycap(text: "⇧")
                Text("+")
                    .font(FamilyTheme.font(11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                SquareCenterLockKeyRecorder(shortcut: $viewModel.squareCenterLockShortcut)
            }
        }
        .help("Hold Shift for 1:1, then this extra key to grow from the click as the center. Shift cannot be changed.")
    }

    @ViewBuilder
    private func shortcutRow(
        _ label: LocalizedStringKey,
        name: KeyboardShortcuts.Name,
        showDivider: Bool = false,
        help: LocalizedStringKey? = nil
    ) -> some View {
        let row = SettingRow(label: label, showDivider: showDivider) {
            // Breit genug für den deutschen Platzhalter „Kurzbefehl aufnehmen“ (Paket: fest 130 pt).
            WideShortcutRecorder(name: name, width: 172)
        }

        if let help {
            row.help(help)
        } else {
            row
        }
    }

    private func contextualShortcutRow(_ item: ContextualShortcut, showDivider: Bool = false) -> some View {
        SettingRow(label: item.action, sublabel: item.scope, showDivider: showDivider) {
            HStack(spacing: 6) {
                ForEach(Array(item.shortcuts.enumerated()), id: \.offset) { _, shortcut in
                    ShortcutKeycap(text: shortcut)
                }
            }
        }
    }
}

/// `KeyboardShortcuts.Recorder` meldet fest 130 pt Breite (`RecorderCocoa.minimumWidth`), dann
/// wird „Kurzbefehl aufnehmen“ abgeschnitten. Gleiche Steuerung, nur mit eigener Breite.
private struct WideShortcutRecorder: NSViewRepresentable {
    let name: KeyboardShortcuts.Name
    let width: CGFloat

    func makeNSView(context: Context) -> KeyboardShortcuts.RecorderCocoa {
        let recorder = KeyboardShortcuts.RecorderCocoa(for: name)
        recorder.controlSize = .small
        recorder.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        recorder.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return recorder
    }

    func updateNSView(_ nsView: KeyboardShortcuts.RecorderCocoa, context: Context) {
        if nsView.shortcutName != name { nsView.shortcutName = name }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: KeyboardShortcuts.RecorderCocoa, context: Context) -> CGSize? {
        CGSize(width: width, height: nsView.intrinsicContentSize.height)
    }
}

private struct SquareCenterLockKeyRecorder: View {
    @Binding var shortcut: SquareCenterLockShortcut
    @State private var isRecording = false

    var body: some View {
        Button {
            isRecording.toggle()
        } label: {
            Text(isRecording ? "…" : shortcut.displayCharacter)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(isRecording ? FamilyTheme.accent : Color.secondary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(
                    Color.primary.opacity(isRecording ? 0.12 : 0.08),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            isRecording ? FamilyTheme.accent : Color.primary.opacity(0.10),
                            lineWidth: isRecording ? 1.5 : 0.5
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Extra key for centered 1:1")
        .accessibilityValue(shortcut.displayCharacter)
        .help("Click to record a different extra key")
        .background {
            if isRecording {
                CenterLockKeyCapture { event in
                    if event.keyCode == 53 {
                        isRecording = false
                        return
                    }
                    if let recorded = SquareCenterLockShortcut(event: event) {
                        shortcut = recorded
                        isRecording = false
                    }
                }
            }
        }
        // Stop listening when the window loses focus or the tab goes away, so the
        // monitor never keeps swallowing keys in the background.
        .onDisappear { isRecording = false }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            isRecording = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            isRecording = false
        }
    }
}

/// Local key-down monitor used only while the extra-key recorder is listening.
private struct CenterLockKeyCapture: NSViewRepresentable {
    var onKeyDown: (NSEvent) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onKeyDown: onKeyDown)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.install()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onKeyDown = onKeyDown
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator {
        var onKeyDown: (NSEvent) -> Void
        private var monitor: Any?

        init(onKeyDown: @escaping (NSEvent) -> Void) {
            self.onKeyDown = onKeyDown
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                // ⌘ combinations (⌘W, ⌘Q, ⌘,) keep working while recording.
                if event.modifierFlags.contains(.command) { return event }
                self?.onKeyDown(event)
                return nil
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

private struct ShortcutKeycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(FamilyTheme.font(11, weight: .semibold))
            .foregroundStyle(FamilyTheme.textSecondary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
            )
    }
}

/// Helps hand ⇧⌘3 / ⇧⌘4 / ⇧⌘5 over from the macOS screenshot tool to Knippi.
private struct SystemScreenshotShortcutsCard: View {
    @State private var systemShortcutsOn = SystemScreenshotShortcuts.areEnabled
    @State private var knippiUsesAny = Self.knippiUsesAnySystemKey

    private static let assignments: [(KeyboardShortcuts.Name, KeyboardShortcuts.Key)] = [
        (.captureFullscreen, .three), (.captureArea, .four), (.captureAllInOne, .five),
    ]

    /// Once any Knippi action uses one of these keys, the user has set them up themselves.
    private static var knippiUsesAnySystemKey: Bool {
        let systemKeys = assignments.map { KeyboardShortcuts.Shortcut($0.1, modifiers: [.command, .shift]) }
        return KeyboardShortcuts.Name.allKnippi.contains { name in
            KeyboardShortcuts.getShortcut(for: name).map(systemKeys.contains) ?? false
        }
    }

    var body: some View {
        Group {
            if systemShortcutsOn {
                banner(
                    icon: "exclamationmark.triangle",
                    tint: FamilyTheme.warning,
                    text: "macOS still uses ⇧⌘3, ⇧⌘4 and ⇧⌘5 for its own screenshots. To use them for Knippi, turn off the shortcuts under Keyboard Shortcuts → Screenshots."
                ) {
                    Button("Open Keyboard Settings") { NSWorkspace.shared.open(SystemScreenshotShortcuts.settingsURL) }
                }
            } else if !knippiUsesAny {
                banner(
                    icon: "keyboard",
                    tint: FamilyTheme.accent,
                    text: "The macOS screenshot shortcuts are off. Knippi can take them over: ⇧⌘3 Capture Fullscreen, ⇧⌘4 Capture Area, ⇧⌘5 All-in-One."
                ) {
                    Button("Use ⇧⌘3 / ⇧⌘4 / ⇧⌘5") {
                        for (name, key) in Self.assignments {
                            KeyboardShortcuts.setShortcut(.init(key, modifiers: [.command, .shift]), for: name)
                        }
                        knippiUsesAny = true
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            systemShortcutsOn = SystemScreenshotShortcuts.areEnabled
            knippiUsesAny = Self.knippiUsesAnySystemKey
        }
    }

    private func banner(icon: String, tint: Color, text: LocalizedStringKey, @ViewBuilder action: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                    .font(FamilyTheme.font(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                action()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.2), lineWidth: 0.5))
    }
}

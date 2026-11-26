// App/Sources/Preferences/PreferencesView.swift
import Combine
import SharedKit
import SwiftUI
import Observation

enum PreferencesTab: String, CaseIterable, Sendable {
    case general
    case permissions
    case screenshots
    case recording
    case quickAccess
    case cloudShare
    case export
    case ocr
    case shortcuts

    /// Tabs shown in the sidebar; Recording is hidden in phase 1.
    static var visibleCases: [PreferencesTab] {
        allCases.filter { $0 != .recording || FeatureFlags.screenRecording }
    }

    var title: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .permissions: "Permissions"
        case .screenshots: "Screenshots"
        case .recording: "Recording"
        case .quickAccess: "Quick Access"
        case .cloudShare: "Cloud Share"
        case .export: "Export"
        case .ocr: "Text Recognition"
        case .shortcuts: "Shortcuts"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .permissions: "lock.shield"
        case .screenshots: "camera"
        case .recording: "record.circle"
        case .quickAccess: "bolt"
        case .cloudShare: "icloud"
        case .export: "folder"
        case .ocr: "text.viewfinder"
        case .shortcuts: "keyboard"
        }
    }
}

/// Gemeinsame Auswahl von Seitenleiste und Inhalt (zwei getrennte Hosting-Controller im
/// NSSplitViewController, siehe PreferencesWindow).
@MainActor
@Observable
final class PreferencesNavigation {
    var selectedTab: PreferencesTab
    init(selectedTab: PreferencesTab = .general) { self.selectedTab = selectedTab }
}

/// Ganzes Einstellungsfenster als eine SwiftUI-Ansicht (Seitenleiste + Inhalt). Das echte Fenster
/// setzt beide Teile in einen NSSplitViewController, damit macOS 26 die Seitenleiste als
/// schwebendes Liquid Glass zeichnet; diese Ansicht dient Offscreen-Snapshots und Vorschauen.
struct PreferencesView: View {
    /// Seitenleiste breit genug für die längste deutsche Bezeichnung („Bildschirmfotos“,
    /// „Berechtigungen“, „Cloud-Freigabe“) samt Symbolkachel in einer Zeile.
    static let sidebarWidth: CGFloat = 220
    /// Fenstergröße: Inhaltsbereich ≈ 560 pt breit, deutsche Bezeichnungen passen.
    static let windowSize = CGSize(width: 780, height: 560)

    @State private var navigation: PreferencesNavigation
    let viewModel: PreferencesViewModel
    let updateManager: UpdateManager?

    init(viewModel: PreferencesViewModel, updateManager: UpdateManager?, initialTab: PreferencesTab? = nil) {
        self.viewModel = viewModel
        self.updateManager = updateManager
        self._navigation = State(initialValue: PreferencesNavigation(selectedTab: initialTab ?? .general))
    }

    var body: some View {
        HStack(spacing: 0) {
            PreferencesSidebarView(navigation: navigation)
                .frame(width: Self.sidebarWidth)
                .background(FamilyTheme.backgroundMiddle)
            PreferencesDetailView(navigation: navigation, viewModel: viewModel, updateManager: updateManager)
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
    }
}

/// Echte macOS-Seitenleiste: `List` + `.sidebar`. Im NSSplitViewController zeichnet macOS 26
/// darunter die schwebende Liquid-Glass-Fläche (Finder-Muster; Design-System erlaubt Glas hier).
struct PreferencesSidebarView: View {
    @Bindable var navigation: PreferencesNavigation

    var body: some View {
        List(selection: Binding<PreferencesTab?>(
            get: { navigation.selectedTab },
            set: { if let tab = $0 { navigation.selectedTab = tab } }
        )) {
            ForEach(PreferencesTab.visibleCases, id: \.self) { tab in
                SidebarRow(tab: tab, isSelected: navigation.selectedTab == tab)
                    .tag(tab)
            }
        }
        .listStyle(.sidebar)
        .scrollDisabled(true)
    }
}

/// Inhalt rechts: ruhiger Familien-Verlauf, feste Karten (Regel G1), weicher Wechsel.
struct PreferencesDetailView: View {
    @Bindable var navigation: PreferencesNavigation
    let viewModel: PreferencesViewModel
    let updateManager: UpdateManager?

    var body: some View {
        let tab = navigation.selectedTab
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch tab {
                case .general:
                    GeneralSettingsView(viewModel: viewModel, updateManager: updateManager)
                case .permissions:
                    PermissionSettingsView(viewModel: viewModel)
                case .screenshots:
                    ScreenshotSettingsView(viewModel: viewModel)
                case .recording:
                    RecordingSettingsView(viewModel: viewModel)
                case .quickAccess:
                    QuickAccessSettingsView(viewModel: viewModel)
                case .cloudShare:
                    CloudShareSettingsView(viewModel: viewModel)
                case .export:
                    ExportSettingsView(viewModel: viewModel)
                case .ocr:
                    OCRSettingsView(viewModel: viewModel)
                case .shortcuts:
                    ShortcutSettingsView(viewModel: viewModel)
                }
            }
            .id(tab)
            .transition(.opacity)
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .familyAnimation(.easeOut(duration: 0.18), value: tab)
        .background(FamilyTheme.calmGradient.ignoresSafeArea())
        .onReceive(NotificationCenter.default.publisher(for: .openScreenshotSettings)) { notification in
            navigation.selectedTab = (notification.object as? PreferencesTab) ?? .screenshots
        }
        .onReceive(NotificationCenter.default.publisher(for: .preferencesSwitchTab)) { notification in
            if let tab = notification.object as? PreferencesTab {
                navigation.selectedTab = tab
            }
        }
    }
}

/// Seitenleisten-Eintrag wie in den Systemeinstellungen: SF-Symbol in kleiner Kachel.
/// Kachel im Familien-Akzent (keine Regenbogen-Palette). Auf der kräftigen Auswahl (Fenster
/// aktiv) wird alles weiß, sonst bleibt die Schrift in Textfarbe.
private struct SidebarRow: View {
    let tab: PreferencesTab
    let isSelected: Bool
    @Environment(\.backgroundProminence) private var prominence
    @Environment(\.controlActiveState) private var activeState

    /// Kräftige Akzent-Auswahl liegt nur im aktiven Fenster unter der Zeile (sonst grau).
    private var onSelection: Bool {
        isSelected && (prominence == .increased || activeState == .key)
    }

    var body: some View {
        Label {
            Text(tab.title)
                .font(FamilyTheme.font(13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(onSelection ? Color.white : FamilyTheme.textPrimary)
                .lineLimit(1)
        } icon: {
            Image(systemName: tab.icon)
                .font(.system(size: 11.5, weight: .semibold))
                // accentFill ist für weiße Schrift gerechnet (≥ 4,6 : 1 hell und dunkel).
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(onSelection ? AnyShapeStyle(Color.white.opacity(0.22))
                                          : AnyShapeStyle(FamilyTheme.accentFill.gradient))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                )
        }
        .padding(.vertical, 3)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

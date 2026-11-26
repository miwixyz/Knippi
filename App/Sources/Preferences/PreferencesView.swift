// App/Sources/Preferences/PreferencesView.swift
import AppKit
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

    /// Kurzer Untertitel unter der großen Überschrift des Tabs.
    var subtitle: LocalizedStringKey {
        switch self {
        case .general: "Startup, sounds and automation"
        case .permissions: "What Knippi may access on this Mac"
        case .screenshots: "What happens during and after a capture"
        case .recording: "Cursor, behavior and format of recordings"
        case .quickAccess: "Where the preview card appears and when it closes"
        case .cloudShare: "Share links through your own storage"
        case .export: "Quality, save location and file names"
        case .ocr: "Copy text straight from a capture"
        case .shortcuts: "Keys for every capture mode"
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

/// Gemeinsame Auswahl von Seitenleiste und Inhalt.
@MainActor
@Observable
final class PreferencesNavigation {
    var selectedTab: PreferencesTab
    init(selectedTab: PreferencesTab = .general) { self.selectedTab = selectedTab }
}

/// Ganzes Einstellungsfenster (Glas-Umbau Phase 2): lebender Hintergrund über die ganze Fläche,
/// links eine selbst gebaute schwebende Liquid-Glass-Insel als Seitenleiste (macOS 27 zeichnet
/// die System-Seitenleiste auf diesem Mac flach), rechts feste Karten (Regel G1).
struct PreferencesView: View {
    static let sidebarWidth: CGFloat = 224
    /// Abstand der Insel zum Fensterrand.
    static let islandInset: CGFloat = 10
    static let windowSize = CGSize(width: 820, height: 600)

    @State private var navigation: PreferencesNavigation
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
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
                .frame(maxHeight: .infinity)
                .padding(Self.islandInset)
            PreferencesDetailView(navigation: navigation, viewModel: viewModel, updateManager: updateManager)
        }
        .background {
            ZStack(alignment: .topLeading) {
                AmbientBackdrop(glow: 1.3)
                if !reduceTransparency && contrast != .increased {
                    // Weiches Akzent-Licht hinter der Insel und ein kühler Gegenpol unten rechts:
                    // das Glas hat etwas zum Brechen, die Fläche bekommt Tiefe statt grau auf grau.
                    // Hell kräftiger (Phase 3): dort wirkte die Insel milchig, das Licht kam kaum durch.
                    let light = colorScheme == .light
                    Ellipse()
                        .fill(FamilyTheme.accent.opacity(light ? 0.66 : 0.46))
                        .frame(width: 280, height: 500)
                        .blur(radius: light ? 60 : 80)
                        .offset(x: -50, y: 50)
                    Ellipse()
                        .fill(FamilyTheme.iris.opacity(light ? 0.46 : 0.30))
                        .frame(width: 260, height: 260)
                        .blur(radius: 70)
                        .offset(x: 20, y: 400)
                    Ellipse()
                        .fill(FamilyTheme.iris.opacity(light ? 0.26 : 0.24))
                        .frame(width: 420, height: 300)
                        .blur(radius: 100)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .offset(x: 120, y: 90)
                }
            }
            .accessibilityHidden(true)
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .onAppear { SichttestHooksGlas2.preferencesAppeared(viewModel: viewModel) }
        .frame(minWidth: Self.windowSize.width, idealWidth: Self.windowSize.width, maxWidth: .infinity,
               minHeight: Self.windowSize.height, idealHeight: Self.windowSize.height, maxHeight: .infinity)
    }
}

/// Schwebende Glas-Insel: oben Knippis Symbol mit Name (unter den Ampelknöpfen), darunter die
/// Einträge. Auswahl als Akzent-Pille mit leichtem Glühen, die zwischen den Einträgen gleitet.
/// Tastatur: Pfeil hoch/runter wechselt den Tab, sobald die Leiste den Fokus hat.
struct PreferencesSidebarView: View {
    @Bindable var navigation: PreferencesNavigation
    @Namespace private var selectionSpace
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let radius: CGFloat = 22

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            // Platz für die Ampelknöpfe, die über der Insel liegen.
            Color.clear.frame(height: 40)
            appHeader
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            VStack(spacing: 2) {
                ForEach(PreferencesTab.visibleCases, id: \.self) { tab in
                    SidebarRow(tab: tab, isSelected: navigation.selectedTab == tab,
                               selectionSpace: selectionSpace) {
                        select(tab)
                    }
                }
            }
            .padding(.horizontal, 8)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .floatingGlassIsland(in: shape)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { move(by: 1) }
        .onKeyPress(.upArrow) { move(by: -1) }
        .onAppear { isFocused = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Settings"))
    }

    private var appHeader: some View {
        HStack(spacing: 9) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
                .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
            Text(verbatim: "Knippi")
                .font(FamilyTheme.font(15, weight: .semibold))
                .foregroundStyle(FamilyTheme.textPrimary)
        }
        .accessibilityHidden(true)
    }

    private func select(_ tab: PreferencesTab) {
        guard tab != navigation.selectedTab else { return }
        withAnimation(reduceMotion ? FamilyTheme.Motion.reduced : FamilyTheme.Motion.select) {
            navigation.selectedTab = tab
        }
    }

    private func move(by step: Int) -> KeyPress.Result {
        let tabs = PreferencesTab.visibleCases
        guard let index = tabs.firstIndex(of: navigation.selectedTab) else { return .ignored }
        let next = index + step
        guard tabs.indices.contains(next) else { return .handled }
        select(tabs[next])
        return .handled
    }
}

/// Inhalt rechts: große Überschrift je Tab (in den Tabs über `PreferencesTabHeader`), feste
/// Karten mit weicher Tiefe, Tab-Wechsel mit Feder (leichtes Hochgleiten + Einblenden).
struct PreferencesDetailView: View {
    @Bindable var navigation: PreferencesNavigation
    let viewModel: PreferencesViewModel
    let updateManager: UpdateManager?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .transition(reduceMotion
                        ? .opacity
                        : .asymmetric(insertion: .opacity.combined(with: .offset(y: 14)), removal: .opacity))
            .padding(.leading, 26)
            .padding(.trailing, 34)
            .padding(.top, 40)
            .padding(.bottom, 34)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .familyAnimation(FamilyTheme.Motion.appear, value: tab)
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

/// Große Überschrift mit kurzem Untertitel oben in jedem Tab.
struct PreferencesTabHeader: View {
    let tab: PreferencesTab

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tab.title)
                .font(FamilyTheme.font(28, weight: .semibold, relativeTo: .largeTitle))
                .foregroundStyle(FamilyTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(tab.subtitle)
                .font(FamilyTheme.font(13, relativeTo: .subheadline))
                .foregroundStyle(FamilyTheme.textSecondary)
        }
        .padding(.bottom, 6)
    }
}

/// Seitenleisten-Eintrag: Symbol + Name. Aktiv: Akzent-Pille (accentFill, weiß gerechnet) mit
/// leichtem Glühen, die per matchedGeometryEffect hinübergleitet. Hover: leise neutrale Fläche.
private struct SidebarRow: View {
    let tab: PreferencesTab
    let isSelected: Bool
    let selectionSpace: Namespace.ID
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 20)
                Text(tab.title)
                    .font(FamilyTheme.font(13, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.white : FamilyTheme.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(FamilyTheme.accentFill.gradient)
                        .overlay(Capsule().strokeBorder(.white.opacity(contrast == .increased ? 0.6 : 0.22),
                                                        lineWidth: 0.6))
                        .shadow(color: FamilyTheme.accentFill.opacity(0.45), radius: 8, y: 2)
                        .matchedGeometryEffect(id: "selection", in: selectionSpace)
                } else if isHovered {
                    Capsule(style: .continuous).fill(FamilyTheme.textPrimary.opacity(0.07))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovered = $0 }
        .familyAnimation(FamilyTheme.Motion.hover, value: isHovered)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// App/Sources/History/HistoryView.swift
//
// Glas-Umbau Phase 2: ruhig lebender Hintergrund (AmbientBackdrop), unsichtbare Titelleiste,
// oben eine schwebende Liquid-Glass-Suchkapsel, darunter feste Bildkarten nach Tagen gruppiert.
// Glas nur für Schwebendes (Kapsel, Hover-Knöpfe, Hinweis), Inhalte auf festen Karten (Regel G1).
import AppKit
import OCRKit
import SwiftUI

/// Recent screenshots from the export folder, searchable by the text in them.
struct HistoryView: View {
    @Bindable var store: HistoryStore

    /// Height of the invisible title bar band (unified toolbar): the search capsule sits in it.
    static let topBand: CGFloat = 52

    var body: some View {
        ZStack(alignment: .top) {
            AmbientBackdrop(glow: 1).ignoresSafeArea()
            if store.isOn {
                content
                    .ignoresSafeArea(edges: .top)
                searchCapsule
                    .padding(.leading, 84)          // clear of the window buttons
                    .padding(.trailing, FamilyTheme.Space.l)
                    .padding(.top, (Self.topBand - 38) / 2)
                    .ignoresSafeArea(edges: .top)
            } else {
                centerState(
                    symbol: "clock.arrow.circlepath",
                    title: String(localized: "History is off."),
                    message: String(localized: "When on, Knippi reads the text in your last \(HistoryStore.defaultKeepCount) saved screenshots and keeps it in a search index on this Mac. You can change the number or delete the index in Settings."),
                    primary: (String(localized: "Turn On History"), { store.enableHistory() }),
                    secondary: (String(localized: "Open Settings…"), {
                        NotificationCenter.default.post(name: .openScreenshotSettings, object: nil)
                    }))
            }
        }
        .overlay(alignment: .bottom) { noticeToast }
        .familyAnimation(FamilyTheme.Motion.appear, value: store.notice)
        .onChange(of: store.matches.count) {
            // Messhilfe der Testkopie (nur von SichttestHooks gesetzt).
            if let index = HistoryDebug.selectIndex, store.matches.indices.contains(index) {
                store.click(store.matches[index], extend: false)
                HistoryDebug.selectIndex = nil
            }
        }
        .frame(minWidth: 540, minHeight: 440)
    }

    // MARK: Search capsule

    private var searchCapsule: some View {
        HStack(spacing: FamilyTheme.Space.s) {
            Image(systemName: "magnifyingglass")
                .font(FamilyTheme.font(13, weight: .medium))
                .foregroundStyle(FamilyTheme.textSecondary)
                .accessibilityHidden(true)
            TextField(String(localized: "Search text in screenshots"), text: $store.query)
                .onSubmit { store.copyFirstMatch() }
                .textFieldStyle(.plain)
                .font(FamilyTheme.font(.body))
                .foregroundStyle(FamilyTheme.textPrimary)
            if !store.query.isEmpty {
                Button { store.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(FamilyTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Clear search"))
            }
            status
            Menu {
                Button(String(localized: "Undo Move to Trash")) { store.undoTrash() }
                    .disabled(!store.canUndoTrash)
                Button(String(localized: "Select All")) { store.selectAll() }
                Divider()
                Button(String(localized: "Delete Index")) { store.deleteStoredText() }
                Button(String(localized: "Turn Off History")) { store.turnOff() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(FamilyTheme.font(13, weight: .semibold))
                    .foregroundStyle(FamilyTheme.textPrimary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(FamilyTheme.textPrimary.opacity(0.07)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(String(localized: "History options"))
        }
        .padding(.leading, FamilyTheme.Space.m + 2)
        .padding(.trailing, 6)
        .frame(height: 38)
        .frame(maxWidth: 620)
        .familyLiquidGlass(in: Capsule(), tint: FamilyTheme.glassLightTint)
        .shadow(color: FamilyTheme.Floating.shadowColor, radius: 12, y: 5)
        .frame(maxWidth: .infinity)
    }

    /// Count or reading progress inside the capsule.
    @ViewBuilder
    private var status: some View {
        Group {
            if store.isIndexing {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text("Reading text…")
                }
            } else if !store.items.isEmpty {
                Text(String(localized: "\(store.matches.count) of \(store.items.count) screenshots"))
            }
        }
        .font(FamilyTheme.font(.caption, weight: .medium))
        .foregroundStyle(FamilyTheme.textSecondary)
        .lineLimit(1)
        .fixedSize()
    }

    // MARK: Grid

    private let columns = [GridItem(.adaptive(minimum: 184), spacing: FamilyTheme.Space.l)]

    @ViewBuilder
    private var content: some View {
        if store.items.isEmpty {
            centerState(
                symbol: "photo.on.rectangle.angled",
                title: String(localized: "No saved screenshots yet."),
                message: store.autoSaveIsOff
                    ? String(localized: "History shows the screenshots saved in your export folder. Auto save is off, so none are kept.")
                    : nil,
                primary: autoSaveAction,
                secondary: nil)
        } else if store.matches.isEmpty {
            centerState(symbol: "text.magnifyingglass",
                        title: String(localized: "No screenshot contains that text."),
                        message: nil, primary: nil, secondary: nil)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: FamilyTheme.Space.xl) {
                    if store.autoSaveIsOff { autoSaveNotice }
                    ForEach(Self.sections(for: store.matches), id: \.day) { section in
                        VStack(alignment: .leading, spacing: FamilyTheme.Space.m) {
                            sectionHeader(section)
                            LazyVGrid(columns: columns, spacing: FamilyTheme.Space.l) {
                                ForEach(section.items) { item in card(item) }
                            }
                        }
                    }
                }
                .padding(.horizontal, FamilyTheme.Space.xl)
                .padding(.top, Self.topBand + FamilyTheme.Space.l)
                .padding(.bottom, FamilyTheme.Space.xxl + FamilyTheme.Space.l)
            }
            .modifier(SoftTopEdge())
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(phases: .down) { press in handleKey(press) }
        }
    }

    private var autoSaveAction: (String, () -> Void)? {
        guard store.autoSaveIsOff else { return nil }
        return (String(localized: "Turn On Auto Save"), { store.enableAutoSave() })
    }

    private func card(_ item: HistoryScanner.Item) -> some View {
        HistoryCell(
            item: item,
            isSelected: store.selected.contains(item.url),
            forceHover: HistoryDebug.forceHoverIndex != nil && store.matches.first == item,
            onOpen: { store.open(item) },
            onCopy: { store.copy(store.targets(for: item)) },
            onReveal: { store.reveal(item) },
            onTrash: { store.moveToTrash(store.targets(for: item)) })
            .onTapGesture(count: 2) { store.open(item) }
            .onTapGesture {
                let extend = !NSEvent.modifierFlags.intersection([.command, .shift]).isEmpty
                store.click(item, extend: extend)
            }
            .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
            .contextMenu {
                let targets = store.targets(for: item)
                Button(String(localized: "Copy")) { store.copy(targets) }
                Button(String(localized: "Quick Look")) { store.quickLook(item) }
                Button(String(localized: "Share…")) { store.share(targets) }
                Divider()
                Button(String(localized: "Open")) { store.open(item) }
                Button(String(localized: "Open in Editor")) { store.openInEditor(item) }
                Button(String(localized: "Show in Finder")) { store.reveal(item) }
                Divider()
                Button(String(localized: "Move to Trash")) { store.moveToTrash(targets) }
            }
    }

    private func sectionHeader(_ section: DaySection) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: FamilyTheme.Space.s) {
            Text(section.title)
                .font(FamilyTheme.font(.title3, weight: .semibold))
                .foregroundStyle(FamilyTheme.textPrimary)
            Text(verbatim: "\(section.items.count)")
                .font(FamilyTheme.font(.caption, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(FamilyTheme.textSecondary)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(FamilyTheme.textPrimary.opacity(0.07)))
                .accessibilityHidden(true)
        }
        .padding(.leading, 2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var autoSaveNotice: some View {
        HStack(spacing: FamilyTheme.Space.m) {
            Image(systemName: "exclamationmark.circle")
                .font(FamilyTheme.font(15, weight: .medium))
                .foregroundStyle(FamilyTheme.accent)
                .accessibilityHidden(true)
            Text("Auto save is off, so new screenshots are not kept in the folder and will not appear here.")
                .font(FamilyTheme.font(.callout))
                .foregroundStyle(FamilyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(String(localized: "Turn On Auto Save")) { store.enableAutoSave() }
                .buttonStyle(AccentCapsuleButtonStyle(compact: true))
        }
        .padding(FamilyTheme.Space.m)
        .background(RoundedRectangle(cornerRadius: FamilyTheme.Radius.field, style: .continuous)
            .fill(FamilyTheme.card))
        .overlay(RoundedRectangle(cornerRadius: FamilyTheme.Radius.field, style: .continuous)
            .strokeBorder(FamilyTheme.accent.opacity(0.26), lineWidth: 1))
    }

    // MARK: Day sections

    struct DaySection: Equatable {
        let day: Date
        let title: String
        let items: [HistoryScanner.Item]
    }

    /// Groups the screenshots (newest first) by calendar day, keeping their order.
    static func sections(for items: [HistoryScanner.Item], now: Date = Date(), calendar: Calendar = .current) -> [DaySection] {
        var result: [DaySection] = []
        for item in items {
            let day = calendar.startOfDay(for: item.modified)
            if let last = result.last, last.day == day {
                result[result.count - 1] = DaySection(day: day, title: last.title, items: last.items + [item])
            } else {
                result.append(DaySection(day: day, title: title(for: day, now: now, calendar: calendar), items: [item]))
            }
        }
        return result
    }

    static func title(for day: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return String(localized: "Today") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) { return String(localized: "Yesterday") }
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now)
        return sameYear
            ? day.formatted(.dateTime.weekday(.wide).day().month(.wide))
            : day.formatted(.dateTime.day().month(.wide).year())
    }

    // MARK: Keys

    /// Keys on the grid: Space Quick Look, Delete to the Trash, Esc clears the choice (or closes the window without one),
    /// ⌘A chooses all, ⌘Z puts the last move to the Trash back, ⌘C or Return copies the choice.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        let command = press.modifiers.contains(.command)
        switch press.key {
        case .space:
            store.quickLook()
            return .handled
        case .return:
            guard !store.selected.isEmpty else { return .ignored }
            store.copySelection()
            return .handled
        case .delete, .deleteForward:
            guard !store.selected.isEmpty else { return .ignored }
            store.moveToTrash(store.selectedItems)
            return .handled
        case .escape:
            if store.selected.isEmpty {
                // Nothing chosen: Esc closes the history window (the grid has focus, so it is the key window).
                NSApp.keyWindow?.performClose(nil)
            } else {
                store.clearSelection()
            }
            return .handled
        default:
            if command, press.characters == "a" { store.selectAll(); return .handled }
            if command, press.characters == "c", !store.selected.isEmpty { store.copySelection(); return .handled }
            if command, press.characters == "z", store.canUndoTrash { store.undoTrash(); return .handled }
            return .ignored
        }
    }

    // MARK: Empty, off and notices

    private func centerState(symbol: String, title: String, message: String?,
                             primary: (String, () -> Void)?, secondary: (String, () -> Void)?) -> some View {
        VStack(spacing: FamilyTheme.Space.l) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [FamilyTheme.accent.opacity(0.35), FamilyTheme.accent.opacity(0)],
                                         center: .center, startRadius: 10, endRadius: 90))
                    .frame(width: 180, height: 180)
                Image(systemName: symbol)
                    .font(FamilyTheme.font(34, weight: .light))
                    .foregroundStyle(FamilyTheme.accent)
                    .frame(width: 92, height: 92)
                    .familyLiquidGlass(in: Circle(), tint: FamilyTheme.glassLightTint)
                    .shadow(color: FamilyTheme.Floating.shadowColor, radius: 14, y: 6)
            }
            .frame(height: 120)
            .accessibilityHidden(true)
            Text(title)
                .font(FamilyTheme.font(.title2, weight: .semibold))
                .foregroundStyle(FamilyTheme.textPrimary)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(FamilyTheme.font(.body))
                    .foregroundStyle(FamilyTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if primary != nil || secondary != nil {
                HStack(spacing: FamilyTheme.Space.m) {
                    if let secondary {
                        Button(secondary.0, action: secondary.1)
                            .buttonStyle(.familyGlass(.capsule, size: 34))
                            .font(FamilyTheme.font(.body, weight: .medium))
                    }
                    if let primary {
                        Button(primary.0, action: primary.1)
                            .buttonStyle(AccentCapsuleButtonStyle())
                    }
                }
                .padding(.top, FamilyTheme.Space.xs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(FamilyTheme.Space.xl)
        .padding(.top, Self.topBand / 2)
    }

    /// "Copied", "Moved to Trash. Press ⌘Z to undo." … as a small glass capsule at the bottom.
    @ViewBuilder
    private var noticeToast: some View {
        if let notice = store.notice {
            HStack(spacing: FamilyTheme.Space.s) {
                Image(systemName: notice.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(notice.isError ? FamilyTheme.danger : FamilyTheme.success)
                    .accessibilityHidden(true)
                Text(notice.text)
                    .foregroundStyle(notice.isError ? FamilyTheme.danger : FamilyTheme.textPrimary)
            }
            .font(FamilyTheme.font(.callout, weight: .medium))
            .padding(.horizontal, FamilyTheme.Space.l)
            .frame(height: 34)
            .familyLiquidGlass(in: Capsule(), tint: FamilyTheme.glassReadableTint)
            .shadow(color: FamilyTheme.Floating.shadowColor, radius: 10, y: 4)
            .padding(.bottom, FamilyTheme.Space.l)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

/// macOS 26: content fades softly under the floating search capsule.
private struct SoftTopEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

private struct HistoryCell: View {
    let item: HistoryScanner.Item
    let isSelected: Bool
    var forceHover = false
    let onOpen: () -> Void
    let onCopy: () -> Void
    let onReveal: () -> Void
    let onTrash: () -> Void
    @State private var image: NSImage?
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let radius: CGFloat = 16
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Self.radius, style: .continuous) }
    private var lifted: Bool { hovering || forceHover }

    private var dateText: String { item.modified.formatted(date: .abbreviated, time: .shortened) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Rectangle().fill(FamilyTheme.canvasBackdrop)
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .accessibilityHidden(true)
                }
                if lifted {
                    // Soft shade at the top so the glass buttons stay visible on white screenshots.
                    LinearGradient(colors: [.black.opacity(0.28), .black.opacity(0)], startPoint: .top, endPoint: .center)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                    hoverActions.transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topTrailing)))
                }
            }
            .frame(height: 128)
            .clipped()
            HStack(spacing: FamilyTheme.Space.s) {
                Text(item.modified.formatted(date: .omitted, time: .shortened))
                    .font(FamilyTheme.font(.callout, weight: .medium))
                    .foregroundStyle(FamilyTheme.textPrimary)
                    .monospacedDigit()
                Text(item.url.deletingPathExtension().lastPathComponent)
                    .font(FamilyTheme.font(.caption))
                    .foregroundStyle(FamilyTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(FamilyTheme.font(15, weight: .semibold))
                        .foregroundStyle(FamilyTheme.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, FamilyTheme.Space.m)
            .frame(height: 36)
        }
        .background(FamilyTheme.card)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(isSelected ? FamilyTheme.accent : FamilyTheme.cardStroke,
                               lineWidth: isSelected ? 2 : 0.8)
        }
        .shadow(color: isSelected ? FamilyTheme.accent.opacity(0.42) : FamilyTheme.Floating.shadowColor.opacity(lifted ? 0.9 : 0.45),
                radius: isSelected ? 14 : (lifted ? 16 : 6), y: lifted ? 9 : 3)
        .scaleEffect(lifted && !reduceMotion ? 1.02 : 1)
        .offset(y: lifted && !reduceMotion ? -3 : 0)
        .contentShape(shape)
        .onHover { hovering = $0 }
        .familyAnimation(FamilyTheme.Motion.hover, value: lifted)
        .familyAnimation(FamilyTheme.Motion.select, value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Screenshot, \(dateText)"))
        .accessibilityHint(String(localized: "Double-click to open"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { onOpen() }
        .accessibilityAction(named: String(localized: "Copy"), onCopy)
        .accessibilityAction(named: String(localized: "Show in Finder"), onReveal)
        .accessibilityAction(named: String(localized: "Move to Trash"), onTrash)
        .task(id: item) {
            image = await HistoryThumbnails.image(for: item.url, modified: item.modified)
        }
    }

    private var hoverActions: some View {
        HStack(spacing: 6) {
            glassButton("doc.on.doc", String(localized: "Copy"), onCopy)
            glassButton("folder", String(localized: "Show in Finder"), onReveal)
            glassButton("trash", String(localized: "Move to Trash"), onTrash)
        }
        .padding(8)
    }

    private func glassButton(_ symbol: String, _ label: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol)
                .font(FamilyTheme.font(12, weight: .semibold))
                .foregroundStyle(FamilyTheme.textPrimary)
                .frame(width: 30, height: 30)
                .familyLiquidGlass(in: Circle(), tint: FamilyTheme.glassReadableTint, interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(PressFeedbackStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Own window for the history (pattern: `HelpWindow`). The store only reads the
/// folder while this window is open.
@MainActor
final class HistoryWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let store: HistoryStore

    init(store: HistoryStore) { self.store = store }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            store.activate()
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 580),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.identifier = DockPresenceController.windowIdentifier
        // Title stays for the Window menu, Mission Control and VoiceOver, it is just not drawn.
        window.title = String(localized: "Screenshot History")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // An empty unified toolbar makes the title bar band 52 pt high, so the window buttons sit
        // centred next to the floating search capsule.
        let toolbar = NSToolbar(identifier: "KnippiHistory")
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 540, height: 440)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: HistoryView(store: store))
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        store.activate()
    }

    func windowWillClose(_ notification: Notification) {
        store.deactivate()
    }

    func windowDidMiniaturize(_ notification: Notification) {
        store.deactivate()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        store.activate()
    }
}

// App/Sources/MenuBar/MenuBarPopover.swift
//
// Menüleisten-Fenster (Glas-Umbau Phase 2): Linksklick auf das Symbol öffnet diese schwebende
// Glasfläche mit den Hauptaktionen, den letzten Bildschirmfotos und einer schlanken Fußzeile.
// Das vollständige klassische Menü bleibt per Rechtsklick (oder ⌥-/⌃-Klick) und über „Mehr“.
//
// Design-System „Menüleisten-Popover (Mac)“: Glas mit Schiefer-Tönung, darin feste Elemente.
// Bedienungshilfen: „Transparenz reduzieren“ → feste Fläche, „Bewegung reduzieren“ → nur Überblenden.
import AppKit
import OCRKit
import SwiftUI

// MARK: - Keyboard focus (pure logic, tested)

/// Something in the popover the keyboard can reach.
enum PopoverFocusID: Hashable {
    case update
    case recording(Int)
    case action(Int)
    case recent(Int)
    case recentsButton
    case footer(Int)
}

/// Rows of focusable things in reading order. Tab and the left/right arrows walk through all of
/// them in order (wrapping), up/down jump to the row above/below at about the same place.
struct PopoverFocusGrid: Equatable {
    enum Move { case next, previous, left, right, up, down }

    var rows: [[PopoverFocusID]]

    init(rows: [[PopoverFocusID]]) { self.rows = rows.filter { !$0.isEmpty } }

    private var flat: [PopoverFocusID] { rows.flatMap { $0 } }

    private func position(of id: PopoverFocusID) -> (row: Int, column: Int)? {
        for (r, row) in rows.enumerated() {
            if let c = row.firstIndex(of: id) { return (r, c) }
        }
        return nil
    }

    func move(from current: PopoverFocusID?, _ move: Move) -> PopoverFocusID? {
        let all = flat
        guard !all.isEmpty else { return nil }
        guard let current, let pos = position(of: current), let index = all.firstIndex(of: current) else {
            // Nothing focused yet: the first key press lands on the first (or, backwards, the last) item.
            return (move == .previous || move == .up) ? all.last : all.first
        }
        switch move {
        case .next, .right:
            return all[(index + 1) % all.count]
        case .previous, .left:
            return all[(index - 1 + all.count) % all.count]
        case .up, .down:
            let target = pos.row + (move == .down ? 1 : -1)
            guard rows.indices.contains(target) else { return current }
            let from = rows[pos.row], to = rows[target]
            let fraction = from.count > 1 ? Double(pos.column) / Double(from.count - 1) : 0
            let column = Int((fraction * Double(to.count - 1)).rounded())
            return to[min(max(column, 0), to.count - 1)]
        }
    }
}

// MARK: - Model

@MainActor
private final class Once { var done = false }

@MainActor
@Observable
final class MenuBarPopoverModel {
    struct Action: Identifiable {
        let id: Int
        let title: String
        /// Spoken by VoiceOver and shown as tooltip (the long menu title, e.g. "Capture Area").
        let detail: String
        let symbol: String
        /// The one main action carries the accent (design system G2).
        var isPrimary = false
        var isEnabled = true
        let run: () -> Void
    }

    struct FooterItem: Identifiable {
        let id: Int
        let title: String
        let symbol: String
        var help: String? = nil
        let run: () -> Void
    }

    struct Recording: Equatable {
        var elapsed: TimeInterval
        var isPaused: Bool
    }

    /// How many recent screenshots the popover shows.
    nonisolated static let recentCount = 6

    var actions: [Action] = []
    var footer: [FooterItem] = []
    private(set) var recents: [HistoryScanner.Item] = []
    private(set) var historyIsOn = false
    var pendingUpdate: String?
    var focus: PopoverFocusID?
    /// Drives the appear animation (set right after the panel is on screen).
    var isShown = false
    /// Shows the hover look on one action and the focus ring without a pointer (test copy photos only).
    var debugHoverAction: Int?

    @ObservationIgnored var currentRecording: () -> Recording? = { nil }
    @ObservationIgnored var onTogglePause: () -> Void = {}
    @ObservationIgnored var onStop: () -> Void = {}
    @ObservationIgnored var onUpdate: () -> Void = {}
    @ObservationIgnored var onOpenRecent: (URL) -> Void = { _ in }
    @ObservationIgnored var onShowHistory: () -> Void = {}
    @ObservationIgnored var onTurnOnHistory: () -> Void = {}
    @ObservationIgnored var onClose: () -> Void = {}
    @ObservationIgnored var onRecentsChanged: () -> Void = {}
    @ObservationIgnored private var loading: Task<Void, Never>?

    var focusGrid: PopoverFocusGrid {
        var rows: [[PopoverFocusID]] = []
        if pendingUpdate != nil { rows.append([.update]) }
        if currentRecording() != nil { rows.append([.recording(0), .recording(1)]) }
        rows.append(actions.filter(\.isEnabled).map { .action($0.id) })
        if historyIsOn {
            let ids = recents.indices.map { PopoverFocusID.recent($0) }
            rows.append(contentsOf: stride(from: 0, to: ids.count, by: 3).map { Array(ids[$0..<min($0 + 3, ids.count)]) })
            if !recents.isEmpty { rows.append([.recentsButton]) }
        } else {
            rows.append([.recentsButton])
        }
        rows.append(footer.map { .footer($0.id) })
        return PopoverFocusGrid(rows: rows)
    }

    /// Reads the newest screenshots from the export folder. Nothing is read while the history is off.
    /// `then` runs once the list is read, or after 0.3 s at the latest (a slow folder must not
    /// hold the popover back; the list then fills in and the panel grows downwards).
    func reloadRecents(historyKeepCount: Int, folder: URL, then: @escaping () -> Void = {}) {
        historyIsOn = historyKeepCount > 0
        loading?.cancel()
        guard historyIsOn else {
            recents = []
            then()
            return
        }
        let once = Once()
        let finish = { if !once.done { once.done = true; then() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { MainActor.assumeIsolated { finish() } }
        loading = Task { [weak self] in
            let found = await Task.detached(priority: .userInitiated) {
                HistoryScanner.scan(folder: folder, limit: Self.recentCount)
            }.value
            guard !Task.isCancelled, let self else { return }
            let changed = found != self.recents
            self.recents = found
            if once.done, changed { self.onRecentsChanged() }
            finish()
        }
    }

    /// Arrow keys, Tab, Return and Space. Returns false for keys the popover does not use.
    func handleKey(keyCode: UInt16, shift: Bool) -> Bool {
        let move: PopoverFocusGrid.Move?
        switch keyCode {
        case 48: move = shift ? .previous : .next   // Tab
        case 123: move = .left
        case 124: move = .right
        case 125: move = .down
        case 126: move = .up
        case 36, 76, 49:                            // Return, Enter, Space
            guard let focus else { return false }
            activate(focus)
            return true
        default: move = nil
        }
        guard let move else { return false }
        focus = focusGrid.move(from: focus, move)
        return true
    }

    func activate(_ id: PopoverFocusID) {
        switch id {
        case .update: onUpdate()
        case .recording(0): onTogglePause()
        case .recording: onStop()
        case .action(let i): if let action = actions.first(where: { $0.id == i }), action.isEnabled { action.run() }
        case .recent(let i): if recents.indices.contains(i) { onOpenRecent(recents[i].url) }
        case .recentsButton: historyIsOn ? onShowHistory() : onTurnOnHistory()
        case .footer(let i): footer.first { $0.id == i }?.run()
        }
    }

    func copy(_ url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }
}

// MARK: - View

struct MenuBarPopoverView: View {
    @Bindable var model: MenuBarPopoverModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    static let width: CGFloat = 428
    private static let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: FamilyTheme.Space.l) {
            if let version = model.pendingUpdate { updateRow(version) }
            if model.currentRecording() != nil { recordingBlock }
            actionRow
            recentsSection
            hairline
            footerRow
        }
        .padding(.horizontal, FamilyTheme.Space.l + 2)
        .padding(.top, FamilyTheme.Space.l + 2)
        .padding(.bottom, FamilyTheme.Space.m + 2)
        .frame(width: Self.width)
        .background(alignment: .top) { glow }
        .modifier(PopoverSurface(shape: Self.shape))
        .scaleEffect(model.isShown || reduceMotion ? 1 : 0.94, anchor: .top)
        .offset(y: model.isShown || reduceMotion ? 0 : -10)
        .opacity(model.isShown ? 1 : 0)
        .familyAnimation(FamilyTheme.Motion.appear, value: model.isShown)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: "Knippi"))
    }

    /// A soft accent light behind the action row: depth without a second colour.
    @ViewBuilder
    private var glow: some View {
        if !reduceTransparency && contrast != .increased {
            RadialGradient(colors: [FamilyTheme.accent.opacity(0.30), FamilyTheme.accent.opacity(0)],
                           center: .top, startRadius: 0, endRadius: 280)
                .frame(height: 220)
                .clipShape(Self.shape)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(FamilyTheme.cardStroke)
            .frame(height: 0.8)
            .padding(.horizontal, -2)
            .accessibilityHidden(true)
    }

    // MARK: Update

    private func updateRow(_ version: String) -> some View {
        Button { model.onUpdate() } label: {
            HStack(spacing: FamilyTheme.Space.s) {
                Image(systemName: "arrow.down.circle.fill").accessibilityHidden(true)
                Text(String(localized: "Update to \(version) Available…"))
                    .font(FamilyTheme.font(.callout, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(FamilyTheme.accent)
            .padding(.horizontal, FamilyTheme.Space.m)
            .padding(.vertical, FamilyTheme.Space.s)
            .background(RoundedRectangle(cornerRadius: FamilyTheme.Radius.field, style: .continuous)
                .fill(FamilyTheme.accent.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: FamilyTheme.Radius.field, style: .continuous)
                .strokeBorder(FamilyTheme.accent.opacity(0.26), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressFeedbackStyle())
        .focusRing(model.focus == .update, shape: RoundedRectangle(cornerRadius: FamilyTheme.Radius.field + 3, style: .continuous))
    }

    // MARK: Recording

    private var recordingBlock: some View {
        HStack(spacing: FamilyTheme.Space.m) {
            PulsingDot(isPaused: model.currentRecording()?.isPaused ?? false)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.currentRecording()?.isPaused == true ? String(localized: "Paused") : String(localized: "Recording"))
                    .font(FamilyTheme.font(.caption, weight: .semibold))
                    .foregroundStyle(FamilyTheme.danger)
                    .textCase(.uppercase)
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    Text(Self.clock(model.currentRecording()?.elapsed ?? 0))
                        .font(FamilyTheme.font(22, weight: .light, relativeTo: .title))
                        .monospacedDigit()
                        .foregroundStyle(FamilyTheme.textPrimary)
                        .contentTransition(.numericText())
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            let paused = model.currentRecording()?.isPaused == true
            roundButton(symbol: paused ? "play.fill" : "pause.fill",
                        label: paused ? String(localized: "Resume Recording") : String(localized: "Pause Recording"),
                        focused: model.focus == .recording(0), filled: false) { model.onTogglePause() }
            roundButton(symbol: "stop.fill", label: String(localized: "Stop Recording"),
                        focused: model.focus == .recording(1), filled: true) { model.onStop() }
        }
        .padding(FamilyTheme.Space.m)
        .background(RoundedRectangle(cornerRadius: FamilyTheme.Radius.tile, style: .continuous).fill(FamilyTheme.card))
        .overlay(RoundedRectangle(cornerRadius: FamilyTheme.Radius.tile, style: .continuous)
            .strokeBorder(FamilyTheme.danger.opacity(0.35), lineWidth: 1))
        .shadow(color: FamilyTheme.danger.opacity(0.18), radius: 10, y: 3)
    }

    private func roundButton(symbol: String, label: String, focused: Bool, filled: Bool, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol)
                .font(FamilyTheme.font(14, weight: .semibold))
                .foregroundStyle(filled ? FamilyTheme.onAccent : FamilyTheme.textPrimary)
                .frame(width: 38, height: 38)
                .background(Circle().fill(filled ? AnyShapeStyle(FamilyTheme.danger) : AnyShapeStyle(FamilyTheme.backgroundMiddle)))
                .contentShape(Circle())
        }
        .buttonStyle(PressFeedbackStyle())
        .focusRing(focused, shape: Circle())
        .accessibilityLabel(label)
        .help(label)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    // MARK: Actions

    private var actionRow: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(model.actions) { action in
                PopoverActionButton(action: action,
                                    focused: model.focus == .action(action.id),
                                    forceHover: model.debugHoverAction == action.id)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Recent screenshots

    private let columns = Array(repeating: GridItem(.flexible(), spacing: FamilyTheme.Space.s + 2), count: 3)

    @ViewBuilder
    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: FamilyTheme.Space.s + 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "Recent Screenshots"))
                    .font(FamilyTheme.font(.headline))
                    .foregroundStyle(FamilyTheme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if model.historyIsOn && !model.recents.isEmpty {
                    Button { model.onShowHistory() } label: {
                        HStack(spacing: 3) {
                            Text(String(localized: "Show All"))
                            Image(systemName: "chevron.right").font(FamilyTheme.font(9, weight: .bold)).accessibilityHidden(true)
                        }
                        .font(FamilyTheme.font(.callout, weight: .medium))
                        .foregroundStyle(FamilyTheme.accent)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(PressFeedbackStyle())
                    .focusRing(model.focus == .recentsButton, shape: Capsule())
                }
            }
            if !model.historyIsOn {
                hintCard(symbol: "clock.arrow.circlepath",
                         text: String(localized: "History is off. Turn it on to see your latest screenshots here."),
                         button: String(localized: "Turn On"))
            } else if model.recents.isEmpty {
                hintCard(symbol: "photo.on.rectangle.angled",
                         text: String(localized: "No saved screenshots yet."), button: nil)
            } else {
                LazyVGrid(columns: columns, spacing: FamilyTheme.Space.s + 2) {
                    ForEach(Array(model.recents.enumerated()), id: \.element.id) { index, item in
                        RecentTile(item: item, focused: model.focus == .recent(index),
                                   onOpen: { model.onOpenRecent(item.url) },
                                   onCopy: { model.copy(item.url); model.onClose() },
                                   onReveal: { model.onClose(); NSWorkspace.shared.activateFileViewerSelecting([item.url]) })
                    }
                }
            }
        }
    }

    private func hintCard(symbol: String, text: String, button: String?) -> some View {
        HStack(spacing: FamilyTheme.Space.m) {
            Image(systemName: symbol)
                .font(FamilyTheme.font(18, weight: .regular))
                .foregroundStyle(FamilyTheme.accent)
                .frame(width: 38, height: 38)
                .background(Circle().fill(FamilyTheme.accent.opacity(0.12)))
                .accessibilityHidden(true)
            Text(text)
                .font(FamilyTheme.font(.callout))
                .foregroundStyle(FamilyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let button {
                Button(button) { model.onTurnOnHistory() }
                    .buttonStyle(AccentCapsuleButtonStyle(compact: true))
                    .focusRing(model.focus == .recentsButton, shape: Capsule())
            }
        }
        .padding(FamilyTheme.Space.m)
        .background(RoundedRectangle(cornerRadius: FamilyTheme.Radius.field, style: .continuous).fill(FamilyTheme.card))
        .overlay(RoundedRectangle(cornerRadius: FamilyTheme.Radius.field, style: .continuous)
            .strokeBorder(FamilyTheme.cardStroke, lineWidth: 0.8))
    }

    // MARK: Footer

    private var footerRow: some View {
        HStack(spacing: 2) {
            ForEach(model.footer) { item in
                FooterButton(item: item, focused: model.focus == .footer(item.id),
                             iconOnly: item.id >= model.footer.count - 2)
                if item.id == model.footer.count - 3 { Spacer(minLength: 0) }
            }
        }
    }
}

// MARK: - Parts

/// Glass with the slate tint for the whole popover; a fixed surface under "Reduce Transparency".
private struct PopoverSurface<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(shape.fill(FamilyTheme.backgroundTop))
                .overlay(shape.stroke(FamilyTheme.cardStroke, lineWidth: 1))
                .compositingGroup()
                .shadow(color: FamilyTheme.Floating.shadowColor,
                        radius: FamilyTheme.Floating.shadowRadius, y: FamilyTheme.Floating.shadowY)
                .padding(FamilyTheme.Floating.edge)
        } else {
            content
                .familyFloatingSurface(in: shape)
                .overlay {
                    if contrast == .increased {
                        shape.stroke(FamilyTheme.cardStroke, lineWidth: 1).padding(FamilyTheme.Floating.edge)
                    }
                }
        }
    }
}

/// Large round glass button with a short label. Hover lifts it; the main action is filled with the accent.
private struct PopoverActionButton: View {
    let action: MenuBarPopoverModel.Action
    let focused: Bool
    var forceHover = false
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lifted: Bool { (hovering || forceHover) && action.isEnabled }

    var body: some View {
        Button(action: action.run) {
            VStack(spacing: 7) {
                icon
                    .scaleEffect(lifted && !reduceMotion ? 1.08 : 1)
                    .offset(y: lifted && !reduceMotion ? -2 : 0)
                    .shadow(color: FamilyTheme.Floating.shadowColor.opacity(lifted ? 1 : 0.5),
                            radius: lifted ? 9 : 4, y: lifted ? 5 : 2)
                    .focusRing(focused, shape: Circle())
                Text(action.title)
                    .font(FamilyTheme.font(.callout, weight: .medium))
                    .foregroundStyle(lifted ? FamilyTheme.textPrimary : FamilyTheme.textSecondary)
                    .lineLimit(1)
                    // May reach a little into the gap next to it instead of being cut ("Text erkennen").
                    .fixedSize()
            }
            .opacity(action.isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressFeedbackStyle())
        .disabled(!action.isEnabled)
        .onHover { hovering = $0 }
        .familyAnimation(FamilyTheme.Motion.hover, value: lifted)
        .accessibilityLabel(action.detail)
        .help(action.detail)
    }

    @ViewBuilder
    private var icon: some View {
        let symbol = Image(systemName: action.symbol)
            .font(FamilyTheme.font(19, weight: .medium))
            .frame(width: 54, height: 54)
        if action.isPrimary {
            symbol
                .foregroundStyle(FamilyTheme.onAccent)
                .background(Circle().fill(FamilyTheme.accent))
                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.8))
                .shadow(color: FamilyTheme.accent.opacity(0.45), radius: 10, y: 4)
        } else {
            symbol
                .foregroundStyle(FamilyTheme.textPrimary)
                .familyLiquidGlass(in: Circle(), tint: FamilyTheme.card.opacity(lifted ? 0.55 : 0.35), interactive: true)
        }
    }
}

/// A recent screenshot: fixed tile, click opens it in the editor, drag takes the file along.
private struct RecentTile: View {
    let item: HistoryScanner.Item
    let focused: Bool
    let onOpen: () -> Void
    let onCopy: () -> Void
    let onReveal: () -> Void
    @State private var image: NSImage?
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                Self.shape.fill(FamilyTheme.canvasBackdrop)
                if let image {
                    Image(nsImage: image).resizable().scaledToFill().accessibilityHidden(true)
                }
            }
            .frame(height: 74)
            .clipShape(Self.shape)
            .overlay(Self.shape.strokeBorder(FamilyTheme.cardStroke, lineWidth: 0.8))
            .scaleEffect(hovering && !reduceMotion ? 1.04 : 1)
            .offset(y: hovering && !reduceMotion ? -2 : 0)
            .shadow(color: FamilyTheme.Floating.shadowColor.opacity(hovering ? 1 : 0.45),
                    radius: hovering ? 8 : 3, y: hovering ? 4 : 1)
            .focusRing(focused, shape: RoundedRectangle(cornerRadius: 15, style: .continuous))
            Text(item.modified.formatted(.relative(presentation: .named)))
                .font(FamilyTheme.font(.caption))
                .foregroundStyle(FamilyTheme.textSecondary)
                .lineLimit(1)
                .padding(.leading, 2)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .familyAnimation(FamilyTheme.Motion.hover, value: hovering)
        .onTapGesture { onOpen() }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button(String(localized: "Open in Editor"), action: onOpen)
            Button(String(localized: "Copy"), action: onCopy)
            Button(String(localized: "Show in Finder"), action: onReveal)
        }
        .help(String(localized: "Open in Editor"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Screenshot, \(item.modified.formatted(date: .abbreviated, time: .shortened))"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen() }
        .accessibilityAction(named: String(localized: "Copy"), onCopy)
        .accessibilityAction(named: String(localized: "Show in Finder"), onReveal)
        .task(id: item) {
            image = await HistoryThumbnails.image(for: item.url, modified: item.modified, maxPixels: 300)
        }
    }
}

private struct FooterButton: View {
    let item: MenuBarPopoverModel.FooterItem
    let focused: Bool
    let iconOnly: Bool
    @State private var hovering = false

    var body: some View {
        Button(action: item.run) {
            HStack(spacing: 5) {
                Image(systemName: item.symbol)
                    .font(FamilyTheme.font(12, weight: .medium))
                    .accessibilityHidden(true)
                if !iconOnly {
                    Text(item.title).font(FamilyTheme.font(.callout, weight: .medium))
                }
            }
            .foregroundStyle(hovering ? FamilyTheme.textPrimary : FamilyTheme.textSecondary)
            .padding(.horizontal, iconOnly ? 8 : 9)
            .frame(height: 28)
            .background(Capsule().fill(FamilyTheme.textPrimary.opacity(hovering ? 0.08 : 0)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressFeedbackStyle())
        .focusRing(focused, shape: Capsule())
        .onHover { hovering = $0 }
        .familyAnimation(FamilyTheme.Motion.hover, value: hovering)
        .accessibilityLabel(item.title)
        .help(item.help ?? item.title)
    }
}

/// Recording indicator: a red dot that breathes (still while paused or with "Reduce Motion").
private struct PulsingDot: View {
    let isPaused: Bool
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(FamilyTheme.danger.opacity(0.28))
                .frame(width: 26, height: 26)
                .scaleEffect(pulse && !isPaused && !reduceMotion ? 1.25 : 0.8)
                .opacity(pulse && !isPaused && !reduceMotion ? 0 : 1)
            Circle()
                .fill(isPaused ? FamilyTheme.textSecondary : FamilyTheme.danger)
                .frame(width: 12, height: 12)
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

/// Plain button with a gentle press dimming (no Apple glass style, design system "Verbote").
struct PressFeedbackStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// Filled accent capsule for the one main action on a surface: `accent` with `onAccent` text (G2),
/// dark text on the light dark-mode accent instead of white on `accentFill` (only 3 : 1 there).
struct AccentCapsuleButtonStyle: ButtonStyle {
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FamilyTheme.font(compact ? .callout : .body, weight: .semibold))
            .foregroundStyle(FamilyTheme.onAccent)
            .padding(.horizontal, compact ? 12 : 18)
            .frame(minHeight: compact ? 28 : 34)
            .background(Capsule().fill(FamilyTheme.accent))
            .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.8))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .shadow(color: FamilyTheme.accent.opacity(0.28), radius: 8, y: 3)
            .contentShape(Capsule())
    }
}

extension View {
    /// Keyboard focus ring in the accent (only drawn while the item has the popover's keyboard focus).
    func focusRing<S: Shape>(_ focused: Bool, shape: S) -> some View {
        overlay {
            if focused {
                shape.stroke(FamilyTheme.accent, lineWidth: 2.5).padding(-3.5).allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Panel

/// Borderless, non-activating panel that can still take keys (like Spotlight).
final class MenuBarPopoverPanel: NSPanel {
    var onKey: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey?(event) == true { return }
        super.sendEvent(event)
    }
}

/// Shows and hides the popover below the status item and closes it on Esc or a click elsewhere.
@MainActor
final class MenuBarPopoverController {
    let model = MenuBarPopoverModel()
    private var panel: MenuBarPopoverPanel?
    private var hosting: NSHostingView<MenuBarPopoverView>?
    private var monitors: [Any] = []
    private var resignObserver: NSObjectProtocol?
    private weak var anchorButton: NSStatusBarButton?
    private var hideWork: DispatchWorkItem?

    var isShown: Bool { panel?.isVisible == true && model.isShown }

    init() {
        model.onClose = { [weak self] in self?.close(animated: true) }
        model.onRecentsChanged = { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.relayout() } }
        }
    }

    func show(below button: NSStatusBarButton) {
        hideWork?.cancel()
        anchorButton = button
        let panel = self.panel ?? makePanel()
        model.focus = nil
        model.isShown = false
        guard let hosting else { return }
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        panel.setFrame(frame(for: size, below: button), display: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        button.highlight(true)
        installMonitors()
        DispatchQueue.main.async { [weak self] in self?.model.isShown = true }
    }

    /// Test copies only (`SichttestHooks`): clicks elsewhere do not close it, so it can be photographed.
    var ignoresOutsideClicks = false

    func close(animated: Bool) {
        guard let panel, panel.isVisible else { return }
        removeMonitors()
        anchorButton?.highlight(false)
        model.isShown = false
        hideWork?.cancel()
        if animated {
            let work = DispatchWorkItem { [weak panel] in panel?.orderOut(nil) }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: work)
        } else {
            panel.orderOut(nil)
        }
    }

    /// A capture shortcut while the popover is open (or still fading out): gone at once, and
    /// the window server has a frame without it before the desktop is sampled (same wait as
    /// for the Quick Access cards in `CaptureCoordinator.withQuickAccessHidden`).
    func closeBeforeCapture() {
        guard panel?.isVisible == true else { return }
        close(animated: false)
        CATransaction.flush()
        Thread.sleep(forTimeInterval: 1.0 / 60.0)
    }

    /// Resize after the content changed (for example a recording started while open).
    func relayout() {
        guard let panel, panel.isVisible, let hosting, let button = anchorButton else { return }
        hosting.layoutSubtreeIfNeeded()
        panel.setFrame(frame(for: hosting.fittingSize, below: button), display: true)
    }

    private func makePanel() -> MenuBarPopoverPanel {
        let panel = MenuBarPopoverPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Glass is half transparent: shadow drawn in the view (design system "Verbote").
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        // Never part of a screenshot or screen recording, also not of other apps' captures.
        panel.sharingType = .none
        panel.title = "Knippi"
        panel.setAccessibilityRole(.popover)
        let hosting = NSHostingView(rootView: MenuBarPopoverView(model: model))
        // Intrinsic size only: `fittingSize` works (measured 26.11.: with no options it was 0 × 0),
        // the panel's frame stays ours (anchored at the top under the icon).
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
        panel.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        self.panel = panel
        self.hosting = hosting
        return panel
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 { close(animated: true); return true }   // Esc
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            if event.charactersIgnoringModifiers == "w" { close(animated: true); return true }
            return false
        }
        return model.handleKey(keyCode: event.keyCode, shift: flags.contains(.shift))
    }

    private func frame(for size: CGSize, below button: NSStatusBarButton) -> NSRect {
        let edge = FamilyTheme.Floating.edge
        var anchor = NSRect.zero
        var screen = NSScreen.main
        if let window = button.window, window.isVisible, let own = window.screen {
            anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
            screen = own
        }
        // The icon can be hidden (crowded menu bar, or not allowed in Control Center's menu bar
        // settings): then the popover opens at the top right of the main screen instead of off screen.
        // (A hidden item's window was measured parked at the bottom left of the screen, 26.11.)
        if let frame = screen?.frame,
           !frame.intersects(anchor) || anchor.isEmpty || anchor.minY < (screen?.visibleFrame.maxY ?? frame.maxY) - 4 {
            screen = NSScreen.screens.first ?? screen      // the screen with the menu bar
            let visible = screen?.visibleFrame ?? frame
            anchor = NSRect(x: visible.maxX - 220, y: visible.maxY, width: 22, height: 0)
        }
        let visible = screen?.visibleFrame ?? anchor
        var x = anchor.midX - size.width / 2
        // The transparent shadow margin may hang over the screen edge, the glass itself not.
        x = min(max(x, visible.minX - edge + 6), visible.maxX - size.width + edge - 6)
        let y = anchor.minY - size.height + edge - 6
        return NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }

    private func installMonitors() {
        removeMonitors()
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated {
                guard self?.ignoresOutsideClicks != true else { return }
                self?.close(animated: true)
            }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, !self.ignoresOutsideClicks else { return }
                // Clicks on the status item itself toggle (handled there); clicks in other own windows close.
                if event.window !== self.panel, event.window !== self.anchorButton?.window {
                    self.close(animated: true)
                }
            }
            return event
        }) { monitors.append(local) }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // A context menu or a drag keeps the panel; anything else taking the keys closes it.
                guard self?.ignoresOutsideClicks != true,
                      NSApp.keyWindow != nil, NSApp.keyWindow !== self?.panel else { return }
                self?.close(animated: true)
            }
        }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
    }
}

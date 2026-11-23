// App/Sources/History/HistoryView.swift
import AppKit
import OCRKit
import SwiftUI

/// Recent screenshots from the export folder, searchable by the text in them.
struct HistoryView: View {
    @Bindable var store: HistoryStore
    @State private var selection: URL?

    private let columns = [GridItem(.adaptive(minimum: 170), spacing: FamilyTheme.Space.m)]

    var body: some View {
        Group {
            if store.isOn {
                VStack(spacing: FamilyTheme.Space.m) {
                    searchField
                    if store.autoSaveIsOff && !store.items.isEmpty { autoSaveNotice }
                    content
                    footer
                }
            } else {
                offState
            }
        }
        .padding(FamilyTheme.Space.l)
        .frame(minWidth: 540, minHeight: 440)
        .familyBackground()
    }

    // MARK: Parts

    private var searchField: some View {
        HStack(spacing: FamilyTheme.Space.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(FamilyTheme.textSecondary)
                .accessibilityHidden(true)
            TextField(String(localized: "Search text in screenshots"), text: $store.query)
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
        }
        .padding(.horizontal, FamilyTheme.Space.m)
        .padding(.vertical, FamilyTheme.Space.s + 2)
        .background {
            RoundedRectangle(cornerRadius: FamilyTheme.Radius.field, style: .continuous)
                .fill(FamilyTheme.card)
                .overlay {
                    RoundedRectangle(cornerRadius: FamilyTheme.Radius.field, style: .continuous)
                        .strokeBorder(FamilyTheme.cardStroke, lineWidth: 0.8)
                }
        }
    }

    private var autoSaveNotice: some View {
        HStack(spacing: FamilyTheme.Space.m) {
            Text("Auto save is off, so new screenshots are not kept in the folder and will not appear here.")
                .font(FamilyTheme.font(.footnote))
                .foregroundStyle(FamilyTheme.textSecondary)
            Spacer(minLength: 0)
            Button(String(localized: "Turn On Auto Save")) { store.enableAutoSave() }
                .buttonStyle(.familyGlass)
        }
        .padding(FamilyTheme.Space.m)
        .familyCard(radius: FamilyTheme.Radius.field)
    }

    @ViewBuilder
    private var content: some View {
        if store.items.isEmpty {
            emptyState(
                store.autoSaveIsOff
                    ? String(localized: "History shows the screenshots saved in your export folder. Auto save is off, so none are kept.")
                    : String(localized: "No saved screenshots yet."),
                offerAutoSave: store.autoSaveIsOff)
        } else if store.matches.isEmpty {
            emptyState(String(localized: "No screenshot contains that text."), offerAutoSave: false)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: FamilyTheme.Space.m) {
                    ForEach(store.matches) { item in
                        HistoryCell(
                            item: item,
                            isSelected: selection == item.url,
                            onOpen: { store.open(item) })
                            .onTapGesture(count: 2) { store.open(item) }
                            .onTapGesture {
                                selection = item.url
                                store.copy(item)
                            }
                            .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
                            .contextMenu {
                                Button(String(localized: "Copy")) { store.copy(item) }
                                Button(String(localized: "Open")) { store.open(item) }
                                Button(String(localized: "Open in Editor")) { store.openInEditor(item) }
                                Button(String(localized: "Show in Finder")) { store.reveal(item) }
                                Divider()
                                Button(String(localized: "Move to Trash")) { trash(item) }
                            }
                    }
                }
                .padding(2)
            }
            .focusable()
            .onKeyPress(keys: [.delete, .deleteForward]) { _ in
                guard let selection, let item = store.matches.first(where: { $0.url == selection }) else { return .ignored }
                trash(item)
                return .handled
            }
        }
    }

    private func trash(_ item: HistoryScanner.Item) {
        if selection == item.url { selection = nil }
        store.moveToTrash(item)
    }

    private var offState: some View {
        VStack(spacing: FamilyTheme.Space.m) {
            Text("History is off.")
                .font(FamilyTheme.font(.headline))
                .foregroundStyle(FamilyTheme.textPrimary)
            Text(String(localized: "When on, Knippi reads the text in your last \(HistoryStore.defaultKeepCount) saved screenshots and keeps it in a search index on this Mac. You can change the number or delete the index in Settings."))
                .font(FamilyTheme.font(.body))
                .foregroundStyle(FamilyTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button(String(localized: "Turn On History")) { store.enableHistory() }
                .buttonStyle(.familyGlass)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(FamilyTheme.Space.xl)
    }

    private func emptyState(_ message: String, offerAutoSave: Bool) -> some View {
        VStack(spacing: FamilyTheme.Space.m) {
            Text(message)
                .font(FamilyTheme.font(.body))
                .foregroundStyle(FamilyTheme.textSecondary)
                .multilineTextAlignment(.center)
            if offerAutoSave {
                Button(String(localized: "Turn On Auto Save")) { store.enableAutoSave() }
                    .buttonStyle(.familyGlass)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(FamilyTheme.Space.xl)
    }

    private var footer: some View {
        HStack(spacing: FamilyTheme.Space.s) {
            if let notice = store.notice {
                Text(notice.text)
                    .foregroundStyle(notice.isError ? FamilyTheme.danger : FamilyTheme.textPrimary)
            } else if store.isIndexing {
                ProgressView().controlSize(.small)
                Text("Reading text…")
            } else if !store.items.isEmpty {
                Text(String(localized: "\(store.matches.count) of \(store.items.count) screenshots"))
            }
            Spacer(minLength: 0)
        }
        .font(FamilyTheme.font(.caption))
        .foregroundStyle(FamilyTheme.textSecondary)
        .frame(minHeight: 16)
    }
}

private struct HistoryCell: View {
    let item: HistoryScanner.Item
    let isSelected: Bool
    let onOpen: () -> Void
    @State private var image: NSImage?

    private var dateText: String { item.modified.formatted(date: .abbreviated, time: .shortened) }

    var body: some View {
        VStack(alignment: .leading, spacing: FamilyTheme.Space.xs) {
            ZStack {
                RoundedRectangle(cornerRadius: FamilyTheme.Radius.field, style: .continuous)
                    .fill(FamilyTheme.card)
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: FamilyTheme.Radius.field, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FamilyTheme.Radius.field, style: .continuous)
                    .strokeBorder(isSelected ? FamilyTheme.accent : FamilyTheme.cardStroke,
                                  lineWidth: isSelected ? 2 : 0.8)
            }
            Text(dateText)
                .font(FamilyTheme.font(.caption))
                .foregroundStyle(FamilyTheme.textSecondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Screenshot, \(dateText)"))
        .accessibilityHint(String(localized: "Double-click to open"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen() }
        .task(id: item) {
            image = await HistoryThumbnails.image(for: item.url, modified: item.modified)
        }
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
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false)
        window.identifier = DockPresenceController.windowIdentifier
        window.title = String(localized: "Screenshot History")
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

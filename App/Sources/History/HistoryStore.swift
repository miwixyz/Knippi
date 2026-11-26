// App/Sources/History/HistoryStore.swift
import AppKit
import Observation
import OCRKit
import SharedKit

extension Notification.Name {
    /// Posted with the file's URL when the editor replaced an auto-saved original (for example
    /// after redacting). The index drops what it read from the old file at once.
    static let screenshotFileReplaced = Notification.Name("knippi.screenshotFileReplaced")
    /// Posted by the settings after "Keep History" changed.
    static let historySettingsChanged = Notification.Name("knippi.historySettingsChanged")
    /// Posted by the settings: remove the text read from screenshots.
    static let historyIndexDeleteRequested = Notification.Name("knippi.historyIndexDeleteRequested")
}

/// The screenshots in the export folder and their searchable text.
///
/// Off by default (`AppSettings.historyKeepCount == 0`): then nothing is scanned or read and no
/// index file exists. Switched on, nothing runs while the history window is closed either:
/// opening the window starts the reading, closing it stops it. The text stays in the index file
/// (see `SearchIndex`). The history is the folder itself, not a second copy of the images.
@MainActor
@Observable
final class HistoryStore {
    /// A short message under the grid ("Copied", or why something did not work).
    struct Notice: Equatable {
        let text: String
        let isError: Bool
    }

    /// A file that went to the Trash: where it was and where it is now.
    struct TrashedFile: Equatable {
        let original: URL
        let trashed: URL
    }

    /// What "Turn On History" switches to.
    nonisolated static let defaultKeepCount = 50

    private(set) var items: [HistoryScanner.Item] = []
    private(set) var matches: [HistoryScanner.Item] = []
    private(set) var isIndexing = false
    private(set) var autoSaveIsOff = true
    private(set) var keepCount: Int
    private(set) var notice: Notice?
    /// Screenshots chosen in the grid (by file).
    private(set) var selected: Set<URL> = []

    var isOn: Bool { keepCount > 0 }

    var canUndoTrash: Bool { !undoStack.isEmpty }

    /// The chosen screenshots, in the order of the grid.
    var selectedItems: [HistoryScanner.Item] { matches.filter { selected.contains($0.url) } }

    var query: String = "" {
        didSet { if query != oldValue { runSearch() } }
    }

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let index: SearchIndex
    @ObservationIgnored private let pasteboard: NSPasteboard
    @ObservationIgnored private let trash: (URL) throws -> URL?
    @ObservationIgnored private let restore: (URL, URL) throws -> Void
    /// Batches moved to the Trash, newest last, so "Undo" can put them back.
    @ObservationIgnored private var undoStack: [[TrashedFile]] = []
    @ObservationIgnored private let editor: @MainActor (URL) -> Void
    @ObservationIgnored private var windowOpen = false
    @ObservationIgnored private var polling: Task<Void, Never>?
    @ObservationIgnored private var indexing: Task<Void, Never>?
    @ObservationIgnored private var searching: Task<Void, Never>?
    @ObservationIgnored private var noticeClearing: Task<Void, Never>?
    /// Tells a finishing read whether it is still the current one (the window may have been
    /// closed and opened again while it ran).
    @ObservationIgnored private var indexRun = 0

    init(
        settings: AppSettings,
        index: SearchIndex = SearchIndex(),
        pasteboard: NSPasteboard = .general,
        trash: @escaping (URL) throws -> URL? = {
            var result: NSURL?
            try FileManager.default.trashItem(at: $0, resultingItemURL: &result)
            return result as URL?
        },
        restore: @escaping (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) },
        openInEditor: @escaping @MainActor (URL) -> Void = { _ in }
    ) {
        self.settings = settings
        self.index = index
        self.pasteboard = pasteboard
        self.trash = trash
        self.restore = restore
        self.editor = openInEditor
        self.keepCount = settings.historyKeepCount
        // No deinit: the store lives as long as the menu bar controller, and the observers hold `self` weakly.
        let center = NotificationCenter.default
        center.addObserver(forName: .screenshotFileReplaced, object: nil, queue: .main) { [weak self] note in
            guard let url = note.object as? URL else { return }
            MainActor.assumeIsolated { self?.forget(url) }
        }
        center.addObserver(forName: .historySettingsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        }
        center.addObserver(forName: .historyIndexDeleteRequested, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.deleteIndex() }
        }
    }

    // MARK: Window open / closed

    /// The window is visible: look at the folder now and every few seconds (only when the history is on).
    func activate() {
        windowOpen = true
        keepCount = settings.historyKeepCount
        guard isOn, polling == nil else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    /// The window is closed: stop scanning and reading.
    func deactivate() {
        windowOpen = false
        stopWork()
    }

    private func stopWork() {
        polling?.cancel(); polling = nil
        indexing?.cancel(); indexing = nil
        indexRun += 1
        isIndexing = false
    }

    // MARK: Switching on and off

    /// "Turn On History": the user's explicit choice. Picks the default count.
    func enableHistory() {
        settings.historyKeepCount = Self.defaultKeepCount
        keepCount = settings.historyKeepCount
        if windowOpen { activate() }
    }

    func enableAutoSave() {
        settings.screenshotAutoSave = true
        autoSaveIsOff = false
    }

    private func settingsChanged() {
        keepCount = settings.historyKeepCount
        if isOn {
            if windowOpen {
                stopWork()
                activate()
            }
        } else {
            // Off means the stored text goes too, not just the view.
            stopWork()
            items = []
            matches = []
            deleteIndex()
        }
    }

    private func deleteIndex() {
        Task { [index] in await index.removeAll() }
    }

    /// "Delete Index" in the history window.
    func deleteStoredText() {
        deleteIndex()
        show(String(localized: "Index deleted"), isError: false)
    }

    /// "Turn Off History" in the history window: same as "Off" in the settings.
    func turnOff() {
        settings.historyKeepCount = 0
        settingsChanged()
    }

    // MARK: Actions on a screenshot

    func open(_ item: HistoryScanner.Item) {
        NSWorkspace.shared.open(item.url)
    }

    func openInEditor(_ item: HistoryScanner.Item) {
        editor(item.url)
    }

    func reveal(_ item: HistoryScanner.Item) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    // MARK: Selection

    /// Click on a screenshot. Plain: choose only this one. With ⇧ or ⌘: add it to the choice or
    /// take it out again. A click never copies: overwriting the clipboard just by choosing was a
    /// surprise. Copy is ⌘C, Return or "Copy" in the menu.
    func click(_ item: HistoryScanner.Item, extend: Bool) {
        if extend {
            if selected.contains(item.url) { selected.remove(item.url) } else { selected.insert(item.url) }
        } else {
            selected = [item.url]
        }
    }

    /// ⌘C or Return on the grid: copy the chosen screenshots.
    func copySelection() {
        guard !selectedItems.isEmpty else { return }
        copy(selectedItems)
    }

    /// What a menu or key acts on for this screenshot: the whole choice when it is part of it, else just it.
    func targets(for item: HistoryScanner.Item) -> [HistoryScanner.Item] {
        selected.contains(item.url) ? selectedItems : [item]
    }

    func selectAll() { selected = Set(matches.map(\.url)) }
    func clearSelection() { selected = [] }

    // MARK: Actions on screenshots

    /// Puts the image on the clipboard and says so.
    func copy(_ item: HistoryScanner.Item) { copy([item]) }

    /// Puts several images on the clipboard, one item each.
    func copy(_ targets: [HistoryScanner.Item]) {
        let images = targets.compactMap { NSImage(contentsOf: $0.url) }
        guard !targets.isEmpty, images.count == targets.count else {
            show(String(localized: "Couldn't copy the screenshot."), isError: true)
            return
        }
        pasteboard.clearContents()
        guard pasteboard.writeObjects(images) else {
            show(String(localized: "Couldn't copy the screenshot."), isError: true)
            return
        }
        show(images.count == 1 ? String(localized: "Copied")
                               : String(localized: "\(images.count) screenshots copied"),
             isError: false)
    }

    /// Return in the search field: copy the newest match.
    func copyFirstMatch() {
        guard let first = matches.first else { return }
        selected = [first.url]
        copy(first)
    }

    /// Moves the file to the Trash (it can be put back from there or with Undo) and drops its text.
    func moveToTrash(_ item: HistoryScanner.Item) { moveToTrash([item]) }

    func moveToTrash(_ targets: [HistoryScanner.Item]) {
        var done: [TrashedFile] = []
        var failed = 0
        for item in targets {
            do {
                if let result = try trash(item.url) {
                    done.append(TrashedFile(original: item.url, trashed: result))
                } else {
                    // Moved, but the Trash did not say where: it cannot be undone from here.
                    done.append(TrashedFile(original: item.url, trashed: item.url))
                }
            } catch {
                failed += 1
            }
        }
        let gone = Set(done.map(\.original))
        items.removeAll { gone.contains($0.url) }
        matches.removeAll { gone.contains($0.url) }
        selected.subtract(gone)
        gone.forEach(forget)
        let undoable = done.filter { $0.trashed != $0.original }
        if !undoable.isEmpty {
            undoStack.append(undoable)
            if undoStack.count > 20 { undoStack.removeFirst() }
        }
        if failed > 0 {
            show(String(localized: "Couldn't move the screenshot to the Trash."), isError: true)
        } else if !done.isEmpty {
            show(String(localized: "Moved to Trash. Press ⌘Z to undo."), isError: false)
        }
    }

    /// Puts the last batch from the Trash back. Never overwrites a file that is there again.
    func undoTrash() {
        guard let batch = undoStack.popLast() else { return }
        var failed: [TrashedFile] = []
        var restored: Set<URL> = []
        for file in batch {
            guard !FileManager.default.fileExists(atPath: file.original.path) else {
                failed.append(file)
                continue
            }
            do {
                try restore(file.trashed, file.original)
                restored.insert(file.original)
            } catch {
                failed.append(file)
            }
        }
        if failed.isEmpty {
            show(String(localized: "Restored"), isError: false)
        } else {
            undoStack.append(failed)
            show(String(localized: "Couldn't restore the screenshot."), isError: true)
        }
        selected = restored
        if windowOpen { Task { await refresh() } }
    }

    // MARK: Quick Look and sharing

    /// Space: Quick Look at the chosen screenshots, or at the first one when none is chosen.
    /// The arrow keys then go through the whole list.
    func quickLookTargets() -> (urls: [URL], index: Int)? {
        let urls = matches.map(\.url)
        guard !urls.isEmpty else { return nil }
        let index = selectedItems.first.flatMap { first in urls.firstIndex(of: first.url) } ?? 0
        return (urls, index)
    }

    func quickLook() {
        guard let target = quickLookTargets() else { return }
        HistoryQuickLook.shared.show(target.urls, at: target.index)
    }

    /// "Quick Look" in a screenshot's menu: show that one, leave the choice as it is.
    func quickLook(_ item: HistoryScanner.Item) {
        let urls = matches.map(\.url)
        guard let index = urls.firstIndex(of: item.url) else { return }
        HistoryQuickLook.shared.show(urls, at: index)
    }

    /// The macOS share menu for these screenshots, below the top edge of the history window.
    func share(_ targets: [HistoryScanner.Item]) {
        guard !targets.isEmpty, let view = NSApp.keyWindow?.contentView else {
            show(String(localized: "Couldn't open the share menu."), isError: true)
            return
        }
        let anchor = NSRect(x: view.bounds.midX - 1, y: view.bounds.maxY - 8, width: 2, height: 2)
        SystemShare.present(fileURLs: targets.map(\.url), relativeTo: anchor, of: view)
    }

    private func show(_ text: String, isError: Bool) {
        notice = Notice(text: text, isError: isError)
        noticeClearing?.cancel()
        noticeClearing = Task { [weak self] in
            try? await Task.sleep(for: .seconds(isError ? 5 : 1.5))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    // MARK: Keeping up with the folder

    private func refresh() async {
        keepCount = settings.historyKeepCount
        guard isOn else { return }
        autoSaveIsOff = !settings.screenshotAutoSave
        let folder = settings.exportLocation
        let limit = keepCount
        let found = await Task.detached(priority: .utility) {
            HistoryScanner.scan(folder: folder, limit: limit)
        }.value
        guard isOn else { return }
        if found != items {
            items = found
            selected.formIntersection(Set(found.map(\.url)))
            runSearch()
        }
        startIndexingIfNeeded()
    }

    private func startIndexingIfNeeded() {
        guard indexing == nil else { return }
        let urls = items.map(\.url)
        indexRun += 1
        let run = indexRun
        indexing = Task { [weak self, index] in
            let pending = await index.pendingCount(urls)
            guard let self, self.indexRun == run else { return }
            guard pending > 0, !Task.isCancelled else {
                self.indexing = nil
                return
            }
            self.isIndexing = true
            await index.update(urls)
            guard self.indexRun == run else { return }
            self.isIndexing = false
            self.indexing = nil
            self.runSearch()
        }
    }

    private func forget(_ url: URL) {
        Task { [index] in await index.forget(url) }
    }

    // MARK: Search

    private func runSearch() {
        searching?.cancel()
        let words = SearchIndex.words(query)
        if words.isEmpty {
            matches = items
            return
        }
        let current = items
        let text = query
        searching = Task { [weak self, index] in
            let hits = Set(await index.search(text, in: current.map(\.url)))
            guard !Task.isCancelled, let self, self.query == text else { return }
            self.matches = current.filter { hits.contains($0.url) }
        }
    }
}

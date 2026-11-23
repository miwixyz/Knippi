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

    /// What "Turn On History" switches to.
    nonisolated static let defaultKeepCount = 50

    private(set) var items: [HistoryScanner.Item] = []
    private(set) var matches: [HistoryScanner.Item] = []
    private(set) var isIndexing = false
    private(set) var autoSaveIsOff = true
    private(set) var keepCount: Int
    private(set) var notice: Notice?

    var isOn: Bool { keepCount > 0 }

    var query: String = "" {
        didSet { if query != oldValue { runSearch() } }
    }

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let index: SearchIndex
    @ObservationIgnored private let pasteboard: NSPasteboard
    @ObservationIgnored private let trash: (URL) throws -> Void
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
        trash: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
        openInEditor: @escaping @MainActor (URL) -> Void = { _ in }
    ) {
        self.settings = settings
        self.index = index
        self.pasteboard = pasteboard
        self.trash = trash
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

    /// Puts the image on the clipboard and says so.
    func copy(_ item: HistoryScanner.Item) {
        guard let image = NSImage(contentsOf: item.url) else {
            show(String(localized: "Couldn't copy the screenshot."), isError: true)
            return
        }
        pasteboard.clearContents()
        if pasteboard.writeObjects([image]) {
            show(String(localized: "Copied"), isError: false)
        } else {
            show(String(localized: "Couldn't copy the screenshot."), isError: true)
        }
    }

    /// Moves the file to the Trash (it can be put back from there) and drops its text.
    func moveToTrash(_ item: HistoryScanner.Item) {
        do {
            try trash(item.url)
        } catch {
            show(String(localized: "Couldn't move the screenshot to the Trash."), isError: true)
            return
        }
        items.removeAll { $0.url == item.url }
        matches.removeAll { $0.url == item.url }
        forget(item.url)
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

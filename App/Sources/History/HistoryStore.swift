// App/Sources/History/HistoryStore.swift
import AppKit
import Observation
import OCRKit
import SharedKit

extension Notification.Name {
    /// Posted with the file's URL when the editor replaced an auto-saved original (for example
    /// after redacting). The index drops what it read from the old file at once.
    static let screenshotFileReplaced = Notification.Name("knippi.screenshotFileReplaced")
}

/// The screenshots in the export folder and their searchable text.
///
/// Nothing runs while the history window is closed: no folder scan, no text reading.
/// Opening the window is what starts the reading, and the text stays in the index file
/// (see `SearchIndex`). The history is the folder itself, not a second copy of the images.
@MainActor
@Observable
final class HistoryStore {
    /// Fixed for now; the "keep" setting (25 / 50 / 100 / off) comes with the settings step.
    nonisolated static let limit = 100

    private(set) var items: [HistoryScanner.Item] = []
    private(set) var matches: [HistoryScanner.Item] = []
    private(set) var isIndexing = false
    private(set) var autoSaveIsOff = true

    var query: String = "" {
        didSet { if query != oldValue { runSearch() } }
    }

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let index: SearchIndex
    @ObservationIgnored private var polling: Task<Void, Never>?
    @ObservationIgnored private var indexing: Task<Void, Never>?
    /// Tells a finishing read whether it is still the current one (the window may have been
    /// closed and opened again while it ran).
    @ObservationIgnored private var indexRun = 0
    @ObservationIgnored private var searching: Task<Void, Never>?

    init(settings: AppSettings, index: SearchIndex = SearchIndex()) {
        self.settings = settings
        self.index = index
        NotificationCenter.default.addObserver(
            forName: .screenshotFileReplaced, object: nil, queue: .main
        ) { [weak self] note in
            guard let url = note.object as? URL else { return }
            MainActor.assumeIsolated { self?.forget(url) }
        }
    }

    // No deinit: the store lives as long as the menu bar controller, and the observer holds `self` weakly.

    // MARK: Window open / closed

    /// The window is visible: look at the folder now and every few seconds.
    func activate() {
        guard polling == nil else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    /// The window is closed: stop scanning and reading.
    func deactivate() {
        polling?.cancel(); polling = nil
        indexing?.cancel(); indexing = nil
        indexRun += 1
        isIndexing = false
    }

    // MARK: Actions

    func enableAutoSave() {
        settings.screenshotAutoSave = true
        autoSaveIsOff = false
    }

    func open(_ item: HistoryScanner.Item) {
        NSWorkspace.shared.open(item.url)
    }

    func reveal(_ item: HistoryScanner.Item) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    // MARK: Keeping up with the folder

    private func refresh() async {
        autoSaveIsOff = !settings.screenshotAutoSave
        let folder = settings.exportLocation
        let found = await Task.detached(priority: .utility) {
            HistoryScanner.scan(folder: folder, limit: HistoryStore.limit)
        }.value
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

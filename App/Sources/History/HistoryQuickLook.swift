// App/Sources/History/HistoryQuickLook.swift
import AppKit
import Quartz

/// The same Quick Look window Finder shows, for the history: Space on the grid. The arrow keys
/// go through the list, Space or Escape closes it.
@MainActor
final class HistoryQuickLook: NSObject, @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    static let shared = HistoryQuickLook()

    private var urls: [URL] = []

    func show(_ urls: [URL], at index: Int) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        self.urls = urls
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = min(max(index, 0), urls.count - 1)
        panel.makeKeyAndOrderFront(nil)
    }

    // MARK: QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        urls.indices.contains(index) ? urls[index] as NSURL : nil
    }

    // MARK: QLPreviewPanelDelegate

    /// Left and right go to the screenshot before or after it.
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown, let panel else { return false }
        let step: Int
        switch Int(event.keyCode) {
        case 123: step = -1   // left arrow
        case 124: step = 1    // right arrow
        default: return false
        }
        let next = panel.currentPreviewItemIndex + step
        if urls.indices.contains(next) { panel.currentPreviewItemIndex = next }
        return true
    }
}

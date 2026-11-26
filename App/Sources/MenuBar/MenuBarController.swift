// App/Sources/MenuBar/MenuBarController.swift
import AppKit
import SharedKit
import KeyboardShortcuts

extension Notification.Name {
    /// Posted when `AppSettings.showMenuBarIcon` changes so the menu bar can show/hide live.
    static let menuBarVisibilityChanged = Notification.Name("menuBarVisibilityChanged")
}

@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private let settings: AppSettings
    private let captureCoordinator: CaptureCoordinator
    private let recordingCoordinator: RecordingCoordinator
    private let ocrCoordinator: OCRCoordinator
    private let desktopIconsCover: DesktopIconsCover
    private let onShowPreferences: () -> Void
    private let updateManager: UpdateManager?
    private let helpWindow = HelpWindow()
    private let historyWindow: HistoryWindow
    /// Left click: the glass popover. Right click (or ⌥/⌃ click) and "More": the full classic menu.
    let popover = MenuBarPopoverController()
    private var classicMenu: NSMenu?

    init(settings: AppSettings, captureCoordinator: CaptureCoordinator, recordingCoordinator: RecordingCoordinator, ocrCoordinator: OCRCoordinator, desktopIconsCover: DesktopIconsCover, updateManager: UpdateManager? = nil, onShowPreferences: @escaping () -> Void) {
        self.settings = settings
        self.captureCoordinator = captureCoordinator
        self.recordingCoordinator = recordingCoordinator
        self.ocrCoordinator = ocrCoordinator
        self.desktopIconsCover = desktopIconsCover
        self.onShowPreferences = onShowPreferences
        self.updateManager = updateManager
        self.historyWindow = HistoryWindow(store: HistoryStore(
            settings: settings,
            openInEditor: { [captureCoordinator] url in _ = captureCoordinator.openImageFiles([url]) }))
        super.init()
        configurePopover()
        applyVisibility()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVisibilityChange),
            name: .menuBarVisibilityChanged,
            object: nil
        )
        SichttestHooks.menuBarReady(self, settings: settings)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleVisibilityChange() {
        applyVisibility()
    }

    /// Installs or removes the status item based on `settings.showMenuBarIcon`.
    private func applyVisibility() {
        if settings.showMenuBarIcon {
            guard statusItem == nil else { return }
            setupStatusItem()
        } else {
            guard let item = statusItem else { return }
            popover.close(animated: false)
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(named: "MenuBarIcon")
            button.image?.size = NSSize(width: 18, height: 18)
            button.image?.isTemplate = true
            // VoiceOver otherwise reads the image name ("MenuBarIcon").
            button.setAccessibilityLabel("Knippi")
            button.toolTip = String(localized: "Knippi: click for the main actions, right-click for all functions")
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
        // Not assigned to `statusItem.menu`: that would open it on every click. It is shown on demand.
        classicMenu = buildMenu()
    }

    // MARK: Click on the status item

    /// What a click on the menu bar icon opens.
    enum ClickTarget: Equatable { case popover, classicMenu }

    /// Right click, ⌥ click and ⌃ click open the full classic menu, a plain left click the popover.
    nonisolated static func clickTarget(isRightClick: Bool, modifiers: NSEvent.ModifierFlags) -> ClickTarget {
        if isRightClick { return .classicMenu }
        return modifiers.intersection([.option, .control]).isEmpty ? .popover : .classicMenu
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let target = Self.clickTarget(isRightClick: event?.type == .rightMouseDown,
                                      modifiers: event?.modifierFlags ?? [])
        switch target {
        case .classicMenu: showClassicMenu()
        case .popover:
            if popover.isShown { popover.close(animated: true) } else { showPopover() }
        }
    }

    /// Opens the full menu under the icon (validation and `menuWillOpen` as before).
    func showClassicMenu() {
        guard let statusItem, let classicMenu else { return }
        popover.close(animated: false)
        statusItem.menu = classicMenu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    func showPopover() {
        guard let button = statusItem?.button else { return }
        refreshPopover { [weak self] in self?.popover.show(below: button) }
    }

    /// Runs a popover action after the panel is gone, so it never ends up in a screenshot.
    private func fromPopover(_ work: @escaping @MainActor () -> Void) -> () -> Void {
        { [weak self] in
            self?.popover.close(animated: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { MainActor.assumeIsolated { work() } }
        }
    }

    private func configurePopover() {
        let model = popover.model
        var actions: [MenuBarPopoverModel.Action] = [
            .init(id: 0, title: String(localized: "Area"), detail: String(localized: "Capture Area"),
                  symbol: "viewfinder", isPrimary: true, run: fromPopover { [weak self] in self?.captureArea() }),
            .init(id: 1, title: String(localized: "Full Screen"), detail: String(localized: "Capture Fullscreen"),
                  symbol: "inset.filled.rectangle", run: fromPopover { [weak self] in self?.captureFullscreen() }),
            .init(id: 2, title: String(localized: "Window"), detail: String(localized: "Capture Window"),
                  symbol: "macwindow", run: fromPopover { [weak self] in self?.captureWindow() }),
        ]
        if FeatureFlags.scrollingCapture {
            actions.append(.init(id: 3, title: String(localized: "Scroll"), detail: String(localized: "Scrolling Capture"),
                                 symbol: "arrow.up.and.down.text.horizontal",
                                 run: fromPopover { [weak self] in self?.captureScrolling() }))
        }
        actions.append(.init(id: 4, title: String(localized: "Read Text"), detail: String(localized: "Capture Text (OCR)"),
                             symbol: "text.viewfinder", run: fromPopover { [weak self] in self?.captureText() }))
        if FeatureFlags.screenRecording {
            actions.append(.init(id: 5, title: String(localized: "Video"), detail: String(localized: "Record Area"),
                                 symbol: "record.circle", run: fromPopover { [weak self] in self?.recordArea() }))
        }
        model.actions = actions
        model.footer = [
            .init(id: 0, title: String(localized: "History"), symbol: "clock.arrow.circlepath",
                  run: fromPopover { [weak self] in self?.showHistory() }),
            .init(id: 1, title: String(localized: "Settings"), symbol: "gearshape",
                  run: fromPopover { [weak self] in self?.openPreferences() }),
            .init(id: 2, title: String(localized: "Help"), symbol: "questionmark.circle",
                  run: fromPopover { [weak self] in self?.openHelp() }),
            .init(id: 3, title: String(localized: "More"), symbol: "ellipsis.circle",
                  help: String(localized: "All functions (also with a right-click on the menu bar icon)"),
                  run: { [weak self] in self?.showClassicMenu() }),
            .init(id: 4, title: String(localized: "Quit Knippi"), symbol: "power",
                  run: { NSApp.terminate(nil) }),
        ]
        model.currentRecording = { [weak self] in
            guard let self, self.recordingCoordinator.isCapturingVideo else { return nil }
            return .init(elapsed: self.recordingCoordinator.recorder.elapsedTime,
                         isPaused: self.recordingCoordinator.isRecordingPaused)
        }
        model.onTogglePause = { [weak self] in self?.recordingCoordinator.togglePause() }
        model.onStop = fromPopover { [weak self] in self?.recordingCoordinator.stopRecording() }
        model.onUpdate = fromPopover { [weak self] in self?.updateManager?.checkForUpdatesInteractively() }
        model.onOpenRecent = { [weak self] url in
            self?.popover.close(animated: false)
            _ = self?.captureCoordinator.openImageFiles([url])
        }
        model.onShowHistory = fromPopover { [weak self] in self?.showHistory() }
        model.onTurnOnHistory = { [weak self] in
            guard let self else { return }
            self.settings.historyKeepCount = HistoryStore.defaultKeepCount
            NotificationCenter.default.post(name: .historySettingsChanged, object: nil)
            // Grow only once the list is loaded (it loads asynchronously).
            self.refreshPopover { [weak self] in self?.popover.relayout() }
        }
    }

    /// Fresh state each time the popover opens: video button, update hint, recent screenshots.
    private func refreshPopover(then: @escaping () -> Void = {}) {
        let model = popover.model
        let recording = recordingCoordinator.isCapturingVideo
        for index in model.actions.indices where model.actions[index].id == 5 {
            model.actions[index].isEnabled = !recording
        }
        model.pendingUpdate = updateManager?.pendingUpdateVersion
        model.reloadRecents(historyKeepCount: settings.historyKeepCount, folder: settings.exportLocation, then: then)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        // Gentle update reminder: only visible while a scheduled check found an update.
        let pendingUpdate = menuItem("", action: #selector(showPendingUpdate))
        pendingUpdate.isHidden = true
        menu.addItem(pendingUpdate)
        let pendingUpdateSeparator = NSMenuItem.separator()
        pendingUpdateSeparator.tag = Self.pendingUpdateSeparatorTag
        pendingUpdateSeparator.isHidden = true
        menu.addItem(pendingUpdateSeparator)

        // Recording controls: only visible while a video is being recorded (see `menuWillOpen`).
        if FeatureFlags.screenRecording {
            let stopRecording = menuItem(String(localized: "Stop Recording"), action: #selector(stopRecording))
            stopRecording.isHidden = true
            menu.addItem(stopRecording)
            let pauseRecording = menuItem(String(localized: "Pause Recording"), action: #selector(togglePauseRecording))
            pauseRecording.isHidden = true
            menu.addItem(pauseRecording)
            let recordingSeparator = NSMenuItem.separator()
            recordingSeparator.tag = Self.recordingSeparatorTag
            recordingSeparator.isHidden = true
            menu.addItem(recordingSeparator)
        }

        // Screenshots
        let captureAllInOne = menuItem(String(localized: "All-in-One"), action: #selector(captureAllInOne))
        captureAllInOne.setShortcut(for: .captureAllInOne)
        captureAllInOne.toolTip = String(localized: "Choose an area and copy, save or edit it right there")
        menu.addItem(captureAllInOne)

        menu.addItem(.separator())

        let captureArea = menuItem(String(localized: "Capture Area"), action: #selector(captureArea))
        captureArea.setShortcut(for: .captureArea)
        menu.addItem(captureArea)

        let captureFullscreen = menuItem(String(localized: "Capture Fullscreen"), action: #selector(captureFullscreen))
        captureFullscreen.setShortcut(for: .captureFullscreen)
        menu.addItem(captureFullscreen)

        let captureWindow = menuItem(String(localized: "Capture Window"), action: #selector(captureWindow))
        captureWindow.setShortcut(for: .captureWindow)
        menu.addItem(captureWindow)

        if FeatureFlags.scrollingCapture {
            let captureScrolling = menuItem(String(localized: "Scrolling Capture"), action: #selector(captureScrolling))
            captureScrolling.setShortcut(for: .captureScrolling)
            menu.addItem(captureScrolling)
        }

        let selfTimer = selfTimerMenuItem()
        menu.addItem(selfTimer)

        menu.addItem(menuItem(String(localized: "Save All in Quick Access"), action: #selector(saveAllQuickAccess)))
        menu.addItem(menuItem(String(localized: "Close Quick Access"), action: #selector(closeAllQuickAccess)))
        menu.addItem(menuItem(String(localized: "Reopen Last Closed Screenshot"), action: #selector(reopenQuickAccess)))

        // Video
        if FeatureFlags.screenRecording {
            menu.addItem(.separator())

            let recordArea = menuItem(String(localized: "Record Area"), action: #selector(recordArea))
            recordArea.setShortcut(for: .recordScreen)
            menu.addItem(recordArea)

            let recordFullscreen = menuItem(String(localized: "Record Full Screen"), action: #selector(recordFullscreen))
            recordFullscreen.setShortcut(for: .recordFullscreen)
            menu.addItem(recordFullscreen)
        }

        menu.addItem(.separator())

        // Tools: color, text, pins, clipboard
        let pickColor = menuItem(String(localized: "Pick Color"), action: #selector(pickColor))
        pickColor.setShortcut(for: .pickColor)
        menu.addItem(pickColor)
        let recentColors = NSMenuItem(title: String(localized: "Recent Colors"), action: nil, keyEquivalent: "")
        recentColors.submenu = NSMenu(title: String(localized: "Recent Colors"))
        recentColors.tag = Self.recentColorsTag
        refreshRecentColors(recentColors)
        menu.addItem(recentColors)

        let captureText = menuItem(String(localized: "Capture Text (OCR)"), action: #selector(captureText))
        captureText.setShortcut(for: .captureText)
        menu.addItem(captureText)

        let pinFromClipboard = menuItem(String(localized: "Pin from Clipboard"), action: #selector(pinFromClipboard))
        pinFromClipboard.setShortcut(for: .pinFromClipboard)
        pinFromClipboard.toolTip = String(localized: "Float copied images, text, colors, or files above other windows")
        menu.addItem(pinFromClipboard)
        let togglePins = menuItem(String(localized: "Hide All Pins"), action: #selector(togglePins))
        togglePins.setShortcut(for: .togglePins)
        menu.addItem(togglePins)

        let editClipboardImage = menuItem(String(localized: "Edit Clipboard Image"), action: #selector(editClipboardImage))
        editClipboardImage.setShortcut(for: .editClipboardImage)
        editClipboardImage.toolTip = String(localized: "Open the image currently copied to the clipboard in Annotate")
        menu.addItem(editClipboardImage)

        let openImageFile = menuItem(String(localized: "Open Image…"), action: #selector(openImageFile), key: "o", modifiers: [.command])
        openImageFile.toolTip = String(localized: "Open an image file in Annotate")
        menu.addItem(openImageFile)

        menu.addItem(menuItem(String(localized: "Hide Desktop Icons"), action: #selector(toggleDesktopIcons)))

        menu.addItem(.separator())

        // History
        let history = menuItem(String(localized: "Screenshot History…"), action: #selector(openHistory))
        history.setShortcut(for: .openHistory)
        menu.addItem(history)

        menu.addItem(.separator())

        menu.addItem(menuItem(String(localized: "Settings…"), action: #selector(openPreferences), key: ",", modifiers: [.command]))
        menu.addItem(menuItem(String(localized: "Knippi Help"), action: #selector(openHelp), key: "?", modifiers: [.command]))
        menu.addItem(menuItem(String(localized: "Get Stream Deck Plugin…"), action: #selector(getStreamDeckPlugin)))
        menu.addItem(menuItem(String(localized: "About Knippi"), action: #selector(openAbout)))
        if updateManager != nil {
            menu.addItem(menuItem(String(localized: "Check for Updates…"), action: #selector(checkForUpdates)))
        }
        menu.addItem(.separator())
        menu.addItem(menuItem(String(localized: "Quit Knippi"), action: #selector(quitApp), key: "q", modifiers: [.command]))

        return menu
    }

    private func menuItem(_ title: String, action: Selector?, key: String = "", modifiers: NSEvent.ModifierFlags = []) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        return item
    }

    /// Self-Timer menu row. Title is "Self-Timer" with the saved duration
    /// rendered in tertiary color as a trailing tag (e.g. "Self-Timer  5s").
    /// Refreshed in `menuWillOpen` so the tag stays in sync with Preferences.
    private func selfTimerMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "", action: #selector(captureSelfTimer), keyEquivalent: "")
        item.target = self
        refreshSelfTimerTitle(item)
        item.setShortcut(for: .selfTimerCapture)
        return item
    }

    private func refreshSelfTimerTitle(_ item: NSMenuItem) {
        let label = String(localized: "Self-Timer")
        let duration = "\(settings.selfTimerDurationSeconds)\u{202F}s"
        let attributed = NSMutableAttributedString(
            string: label,
            attributes: [.font: NSFont.safeMenuFont(ofSize: 0)]
        )
        attributed.append(NSAttributedString(
            string: "   \(duration)",
            attributes: [
                .font: NSFont.safeMenuFont(ofSize: 0),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
        ))
        item.attributedTitle = attributed
    }

    private static let recentColorsTag = 4_711
    private static let pendingUpdateSeparatorTag = 4_712
    private static let recordingSeparatorTag = 4_713

    /// Rebuilds the "Recent Colors" submenu: swatch + value in the current format.
    private func refreshRecentColors(_ item: NSMenuItem) {
        guard let submenu = item.submenu else { return }
        submenu.removeAllItems()
        let colors = settings.recentColors.items
        guard !colors.isEmpty else {
            let empty = NSMenuItem(title: String(localized: "No colors yet"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
            return
        }
        let format = settings.colorFormat
        for (index, color) in colors.enumerated() {
            let entry = menuItem(format.string(for: color), action: #selector(copyRecentColor(_:)))
            entry.tag = index
            // Swatch inside the title, not as `image`: the image column didn't show up in
            // the status menu (Michael, 21.11.: "neben dem Farbcode muss die Farbe stehen").
            let attachment = NSTextAttachment()
            attachment.image = Self.swatch(for: color)
            attachment.bounds = CGRect(x: 0, y: -2, width: 14, height: 14)
            let title = NSMutableAttributedString(attachment: attachment)
            title.append(NSAttributedString(
                string: "  " + format.string(for: color),
                attributes: [.font: NSFont.safeMenuFont(ofSize: 0)]
            ))
            entry.attributedTitle = title
            submenu.addItem(entry)
        }
    }

    private static func swatch(for color: SharedKit.RGBColor) -> NSImage {
        let size = NSSize(width: 14, height: 14)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            NSColor(srgbRed: CGFloat(color.r) / 255, green: CGFloat(color.g) / 255,
                    blue: CGFloat(color.b) / 255, alpha: 1).setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
            path.stroke()
            return true
        }
        return image
    }

    @objc private func pickColor() {
        captureCoordinator.pickColor()
    }

    @objc private func copyRecentColor(_ sender: NSMenuItem) {
        let colors = settings.recentColors.items
        guard colors.indices.contains(sender.tag) else { return }
        captureCoordinator.copyColor(colors[sender.tag])
    }

    @objc private func captureArea() {
        captureCoordinator.captureArea()
    }

    @objc private func captureAllInOne() {
        captureCoordinator.captureAllInOne()
    }

    @objc private func captureFullscreen() {
        captureCoordinator.captureFullscreen()
    }

    @objc private func captureWindow() {
        captureCoordinator.captureWindow()
    }

    @objc private func pinFromClipboard() {
        captureCoordinator.pinFromClipboard()
    }

    @objc private func editClipboardImage() {
        captureCoordinator.editClipboardImage()
    }

    @objc private func openImageFile() {
        captureCoordinator.openImageFilesWithPanel()
    }

    @objc private func captureText() {
        ocrCoordinator.startInstantOCR()
    }

    @objc private func captureScrolling() {
        captureCoordinator.captureScrolling()
    }

    @objc private func captureSelfTimer() {
        captureCoordinator.captureAreaWithSelfTimer()
    }

    @objc private func recordArea() {
        recordingCoordinator.startRecordingFlow()
    }

    @objc private func recordFullscreen() {
        recordingCoordinator.startFullScreenRecordingFlow()
    }

    @objc private func stopRecording() {
        recordingCoordinator.stopRecording()
    }

    @objc private func togglePauseRecording() {
        recordingCoordinator.togglePause()
    }

    @objc private func openPreferences() {
        onShowPreferences()
    }

    @objc private func showPendingUpdate() {
        updateManager?.checkForUpdatesInteractively()
    }

    @objc private func checkForUpdates() {
        updateManager?.checkForUpdatesInteractively()
    }

    @objc private func openHistory() {
        showHistory()
    }

    /// Opens the screenshot history (menu, shortcut and `knippi://grab/history`).
    func showHistory() {
        historyWindow.show()
    }

    /// The plugin is a separate file on the GitHub release page, not part of the app. The browser
    /// downloads it (Knippi itself sends nothing), a double click installs it in the Stream Deck app.
    static let streamDeckPluginURL = URL(string: "https://github.com/miwixyz/Knippi/releases/latest/download/Knippi.streamDeckPlugin")!

    @objc private func getStreamDeckPlugin() {
        NSWorkspace.shared.open(Self.streamDeckPluginURL)
    }

    @objc private func openHelp() {
        helpWindow.show()
    }

    @objc private func openAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func togglePins() {
        captureCoordinator.togglePinsVisibility()
    }

    @objc private func saveAllQuickAccess() {
        captureCoordinator.saveAllQuickAccess()
    }

    @objc private func closeAllQuickAccess() {
        captureCoordinator.closeAllQuickAccess()
    }

    @objc private func reopenQuickAccess() {
        captureCoordinator.reopenQuickAccess()
    }

    @objc private func toggleDesktopIcons() {
        desktopIconsCover.setHiddenManually(!desktopIconsCover.isHiddenManually)
    }
}

// MARK: - Update shortcut display when menu opens

extension MenuBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        // Refresh shortcut display from KeyboardShortcuts in case user changed them
        let pendingVersion = updateManager?.pendingUpdateVersion
        let recording = recordingCoordinator.isCapturingVideo
        for item in menu.items {
            switch item.action {
            case #selector(stopRecording): item.isHidden = !recording
            case #selector(togglePauseRecording):
                item.isHidden = !recording
                item.title = recordingCoordinator.isRecordingPaused
                    ? String(localized: "Resume Recording")
                    : String(localized: "Pause Recording")
            case #selector(showPendingUpdate):
                item.isHidden = pendingVersion == nil
                if let pendingVersion {
                    item.title = String(localized: "Update to \(pendingVersion) Available…")
                }
            case #selector(toggleDesktopIcons): item.state = desktopIconsCover.isHiddenManually ? .on : .off
            case #selector(togglePins):
                item.title = captureCoordinator.arePinsHidden
                    ? String(localized: "Show All Pins")
                    : String(localized: "Hide All Pins")
                item.isHidden = !captureCoordinator.hasPins
                item.setShortcut(for: .togglePins)
            case #selector(saveAllQuickAccess), #selector(closeAllQuickAccess):
                item.isHidden = !captureCoordinator.hasQuickAccess
            case #selector(reopenQuickAccess): item.isHidden = !captureCoordinator.canReopenQuickAccess
            case #selector(captureAllInOne): item.setShortcut(for: .captureAllInOne)
            case #selector(captureArea): item.setShortcut(for: .captureArea)
            case #selector(captureFullscreen): item.setShortcut(for: .captureFullscreen)
            case #selector(captureWindow): item.setShortcut(for: .captureWindow)
            case #selector(pickColor): item.setShortcut(for: .pickColor)
            case #selector(pinFromClipboard): item.setShortcut(for: .pinFromClipboard)
            case #selector(editClipboardImage): item.setShortcut(for: .editClipboardImage)
            case #selector(captureText): item.setShortcut(for: .captureText)
            case #selector(openHistory): item.setShortcut(for: .openHistory)
            case #selector(recordArea): item.setShortcut(for: .recordScreen)
            case #selector(recordFullscreen): item.setShortcut(for: .recordFullscreen)
            case #selector(captureScrolling): item.setShortcut(for: .captureScrolling)
            case #selector(captureSelfTimer):
                item.setShortcut(for: .selfTimerCapture)
                refreshSelfTimerTitle(item)
            default:
                if item.tag == Self.recentColorsTag { refreshRecentColors(item) }
                if item.tag == Self.pendingUpdateSeparatorTag { item.isHidden = pendingVersion == nil }
                if item.tag == Self.recordingSeparatorTag { item.isHidden = !recording }
            }
        }
    }
}

// MARK: - Grey out the video start items while a video is being recorded

extension MenuBarController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(recordArea), #selector(recordFullscreen):
            return !recordingCoordinator.isCapturingVideo
        default:
            return true
        }
    }
}

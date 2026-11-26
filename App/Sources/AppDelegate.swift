// App/Sources/AppDelegate.swift
import AppKit
import AnnotationKit
import os
import SharedKit
import ShareKit
import OCRKit
import KeyboardShortcuts
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Static reference to the live AppDelegate. Use this instead of
    /// `NSApp.delegate as? AppDelegate`, which fails under SwiftUI's
    /// `@NSApplicationDelegateAdaptor` proxy wrapping.
    static private(set) var shared: AppDelegate?

    private var menuBarController: MenuBarController?
    let settings = AppSettings()
    let permissionManager = PermissionManager()
    private var pixelateFailureToast: ToastWindow?
    private var lastPixelateToast: Date?
    private(set) var captureCoordinator: CaptureCoordinator?
    private(set) var recordingCoordinator: RecordingCoordinator?
    let desktopIconsCover = DesktopIconsCover()
    private(set) var ocrCoordinator: OCRCoordinator?
    private(set) var shareCoordinator: ShareCoordinator?
    private var preferencesWindow: PreferencesWindow?
    private var dockPresenceController: DockPresenceController?
    private var automationURLRequestBuffer = AutomationURLRequestBuffer()
    private var imageFileOpenBuffer = ImageFileOpenBuffer()
    /// Sparkle update coordinator used by preferences and manual update checks.
    /// Lazy: built after the test-host check in applicationDidFinishLaunching, so a test run
    /// never starts the real updater with its network check (audit P14).
    lazy var updateManager = UpdateManager()

    func showPixelateFailureToast() {
        // draw(_:) kann den Fehler mit bis zu 60 Hz melden; Hinweis höchstens alle 3 s.
        if let last = lastPixelateToast, Date().timeIntervalSince(last) < 3 { return }
        lastPixelateToast = Date()
        pixelateFailureToast?.orderOut(nil)
        pixelateFailureToast = ToastWindow(
            message: String(localized: "Pixelation failed – area was blacked out."),
            icon: "exclamationmark.triangle.fill",
            iconColor: .systemOrange
        )
        pixelateFailureToast?.show(autoDismissAfter: 3)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A hosted unit-test bundle only needs the AppKit run loop. Avoid
        // registering global shortcuts, touching real settings, or starting
        // coordinators in the separate test-host process.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }

        FamilyTheme.app = .knippi
        if !FamilyTheme.registerFonts(bundle: .main) {
            Logger(subsystem: "dev.mwlr.knippi", category: "theme").error("Plus Jakarta Sans nicht registriert – Systemschrift aktiv")
        }

        Self.shared = self
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleReopen(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEReopenApplication)
        )
        DiagnosticLogger.installUncaughtExceptionHandler()

        // Show tooltips faster (default is ~2s, reduce to 0.3s)
        UserDefaults.standard.set(300, forKey: "NSInitialToolTipDelay")

        // Fail-closed-Hinweis: der Filter ist gescheitert, der Bereich wurde schwarz gefüllt.
        PixelateObject.reportFailure = {
            Task { @MainActor in
                AppDelegate.shared?.showPixelateFailureToast()
            }
        }

        captureCoordinator = CaptureCoordinator(settings: settings)
        recordingCoordinator = RecordingCoordinator(settings: settings)
        ocrCoordinator = OCRCoordinator(settings: settings)
        shareCoordinator = makeShareCoordinator(settings: settings)
        captureCoordinator!.ocrCoordinator = ocrCoordinator
        captureCoordinator!.recordingCoordinator = recordingCoordinator
        captureCoordinator!.shareCoordinator = shareCoordinator
        captureCoordinator!.rebuildShareCoordinator = { [weak self] in
            guard let self else { return nil }
            self.refreshShareCoordinator()
            return self.shareCoordinator
        }
        recordingCoordinator!.desktopIconsCover = desktopIconsCover
        if FeatureFlags.screenRecording {
            recordingCoordinator!.recoverInterruptedRecording()
        }
        preferencesWindow = PreferencesWindow(settings: settings, permissionManager: permissionManager, updateManager: updateManager)
        dockPresenceController = DockPresenceController()
        if settings.diagnosticLoggingEnabled {
            DiagnosticLogger.append(
                "App launched version=\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown") build=\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown")",
                category: "App"
            )
        }
        menuBarController = MenuBarController(
            settings: settings,
            captureCoordinator: captureCoordinator!,
            recordingCoordinator: recordingCoordinator!,
            ocrCoordinator: ocrCoordinator!,
            desktopIconsCover: desktopIconsCover,
            updateManager: updateManager,
            onShowPreferences: { [weak self] in self?.showPreferences() }
        )
        registerGlobalShortcuts()
        performPendingAutomationURLAction()
        performPendingImageFileOpen()
        SichttestHooks.apply(captureCoordinator: captureCoordinator)
        SichttestHooks.demoCaptureSurfaces(settings: settings)

        NotificationCenter.default.addObserver(
            forName: .openScreenshotSettings,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let tabRaw = (notification.object as? PreferencesTab)?.rawValue
            MainActor.assumeIsolated {
                let tab = tabRaw.flatMap(PreferencesTab.init(rawValue:)) ?? .screenshots
                self?.preferencesWindow?.show(tab: tab)
            }
        }
        NotificationCenter.default.addObserver(
            forName: .openPreferencesTab,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let tabRaw = (notification.object as? PreferencesTab)?.rawValue
            MainActor.assumeIsolated {
                let tab = tabRaw.flatMap(PreferencesTab.init(rawValue:)) ?? .general
                self?.preferencesWindow?.show(tab: tab)
            }
        }
        Task {
            await permissionManager.checkScreenRecordingPermission()
        }
        // Load Vision's OCR models off the critical path so the first
        // "Capture Text" of a session doesn't stall on one-time model setup.
        if !OCRProcessFallback.shouldSkipPrewarm {
            Task.detached(priority: .utility) {
                await TextRecognizer.prewarm()
            }
        }
    }

    private func registerGlobalShortcuts() {
        onCaptureKeyDown(for: .captureArea) { [weak self] in
            self?.captureCoordinator?.captureArea()
        }
        onCaptureKeyDown(for: .captureAllInOne) { [weak self] in
            self?.captureCoordinator?.captureAllInOne()
        }
        onCaptureKeyDown(for: .captureFullscreen) { [weak self] in
            // Not while a selection is on screen: the capture would contain the dimmed
            // overlay (audit C3, 21.11.).
            guard let coordinator = self?.captureCoordinator, !coordinator.isCaptureSelectionActive else { return }
            coordinator.captureFullscreen()
        }
        onCaptureKeyDown(for: .captureWindow) { [weak self] in
            // Not while a selection is on screen: the capture would contain the dimmed
            // overlay (audit C3, 21.11.).
            guard let coordinator = self?.captureCoordinator, !coordinator.isCaptureSelectionActive else { return }
            coordinator.captureWindow()
        }
        onCaptureKeyDown(for: .captureText) { [weak self] in
            self?.ocrCoordinator?.startInstantOCR()
        }
        KeyboardShortcuts.onKeyDown(for: .openHistory) { [weak self] in
            self?.menuBarController?.showHistory()
        }
        if FeatureFlags.screenRecording {
            onCaptureKeyDown(for: .recordScreen) { [weak self] in
                // Only the shortcut toggles: a repeated automation URL must not stop a recording.
                self?.recordingCoordinator?.startRecordingFlow(togglesStop: true)
            }
            onCaptureKeyDown(for: .recordFullscreen) { [weak self] in
                self?.recordingCoordinator?.startFullScreenRecordingFlow()
            }
        }
        if FeatureFlags.scrollingCapture {
            onCaptureKeyDown(for: .captureScrolling) { [weak self] in
                self?.captureCoordinator?.captureScrolling()
            }
        }
        onCaptureKeyDown(for: .selfTimerCapture) { [weak self] in
            self?.captureCoordinator?.captureAreaWithSelfTimer()
        }
        onCaptureKeyDown(for: .captureAreaToClipboard) { [weak self] in
            self?.captureCoordinator?.captureAreaToClipboard()
        }
        onCaptureKeyDown(for: .captureAreaAndShare) { [weak self] in
            self?.captureCoordinator?.captureAreaAndShare()
        }
        onCaptureKeyDown(for: .captureAreaAndAnnotate) { [weak self] in
            self?.captureCoordinator?.captureAreaAndAnnotate()
        }
        onCaptureKeyDown(for: .captureAreaAndPin) { [weak self] in
            self?.captureCoordinator?.captureAreaAndPin()
        }
        onCaptureKeyDown(for: .pickColor) { [weak self] in
            self?.captureCoordinator?.pickColor()
        }
        KeyboardShortcuts.onKeyDown(for: .pinFromClipboard) { [weak self] in
            self?.captureCoordinator?.pinFromClipboard()
        }
        KeyboardShortcuts.onKeyDown(for: .togglePins) { [weak self] in
            self?.captureCoordinator?.togglePinsVisibility()
        }
        KeyboardShortcuts.onKeyDown(for: .editClipboardImage) { [weak self] in
            self?.captureCoordinator?.editClipboardImage()
        }
        onCaptureKeyDown(for: .captureLastArea) { [weak self] in
            // Not while a selection is on screen: the capture would contain the dimmed
            // overlay (audit C3, 21.11.).
            guard let coordinator = self?.captureCoordinator, !coordinator.isCaptureSelectionActive else { return }
            coordinator.replayLastCapture()
        }
    }

    /// Capture shortcuts first close the glass popover without its fade, so it never lands
    /// in the screenshot (audit 26.11.: the panel was in the image when it was open).
    private func onCaptureKeyDown(for name: KeyboardShortcuts.Name, action: @escaping () -> Void) {
        KeyboardShortcuts.onKeyDown(for: name) { [weak self] in
            self?.menuBarController?.popover.closeBeforeCapture()
            action()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Longest a quit waits for a running recording to be stopped and saved.
    static let terminationRecordingTimeout: Duration = .seconds(10)
    private var isTerminatingAfterRecording = false

    /// Quitting during a recording (menu, Cmd-Q, logout, Sparkle's install-and-relaunch)
    /// first stops and saves it; otherwise the file stayed unfinished and up to the last
    /// 5 s were lost. After `terminationRecordingTimeout` the app quits anyway; the
    /// recovery marker then brings back what was written on the next launch.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isTerminatingAfterRecording { return .terminateLater }
        // An open editor holds unsaved work: a recording editor keeps the only copy of
        // the recording in tmp (no recovery marker), a screenshot editor its annotations.
        // AppKit does not close windows on quit, so the editors' own prompts never run.
        // Asked also while a recording runs: that one gets saved, but an editor opened
        // for an earlier recording would still be lost without a word.
        if !confirmQuitWithOpenEditors() {
            return .terminateCancel
        }
        guard let coordinator = recordingCoordinator, coordinator.isCapturingVideo else {
            return .terminateNow
        }
        isTerminatingAfterRecording = true

        coordinator.stopRecording(forTermination: true) { [weak self] _ in
            self?.replyToPendingTermination()
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.terminationRecordingTimeout)
            self?.replyToPendingTermination()
        }
        return .terminateLater
    }

    /// Asks before quitting while an editor has unsaved work. `true` = quit.
    private func confirmQuitWithOpenEditors() -> Bool {
        let recordingOpen = recordingCoordinator?.hasOpenEditor ?? false
        // Every screenshot editor, not only the newest: older ones can stay open.
        let screenshotEditors = NSApp.windows.compactMap { $0 as? AnnotationEditorWindow }
        let screenshotOpen = screenshotEditors.contains { $0.isVisible && $0.hasUnsavedWork }
        guard recordingOpen || screenshotOpen else { return true }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Quit and discard unsaved work?")
        alert.informativeText = recordingOpen
            ? String(localized: "A recording is still open in the editor and has not been saved. It will be lost.")
            : String(localized: "The screenshot in the editor has unsaved changes. They will be lost.")
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.addButton(withTitle: String(localized: "Quit"))
        let quit = alert.runModal() == .alertSecondButtonReturn
        if !quit {
            recordingCoordinator?.showOpenEditors()
            screenshotEditors.filter { $0.isVisible && $0.hasUnsavedWork }
                .forEach { $0.makeKeyAndOrderFront(nil) }
        }
        return quit
    }

    /// Answers the `.terminateLater` exactly once (save finished or timeout, whichever first).
    private func replyToPendingTermination() {
        guard isTerminatingAfterRecording else { return }
        isTerminatingAfterRecording = false
        NSApp.reply(toApplicationShouldTerminate: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let (imageFiles, remainder) = ImageFileOpenRequest.partition(urls: urls)

        // Opening image files is never gated by the Automation URLs toggle —
        // that setting only governs the `knippi://` automation scheme.
        if !imageFiles.isEmpty {
            imageFileOpenBuffer.enqueue(imageFiles)
            performPendingImageFileOpen()
        }

        guard !remainder.isEmpty else { return }

        guard let actionURL = remainder.first(where: { AutomationURLAction(url: $0) != nil }),
              let action = AutomationURLAction(url: actionURL) else {
            logAutomationURL("Ignored unsupported request")
            return
        }
        // Asked before = the user already decided; a fresh "Don't Allow" needs no toast.
        let alreadyAsked = settings.automationURLsAsked
        guard settings.automationURLsEnabled || askToAllowAutomationURLs(for: actionURL) else {
            logAutomationURL("Ignored request because Automation URLs are disabled")
            if alreadyAsked { showAutomationBlockedNotice() }
            return
        }

        // A request during an open selection is dropped by the buffer; say so in the log
        // instead of the command just vanishing (audit P16).
        if captureCoordinator?.isCaptureSelectionActive == true {
            logAutomationURL("Ignored request: a capture selection is open")
        }
        automationURLRequestBuffer.enqueue(action)
        performPendingAutomationURLAction()
    }

    /// Asks once whether other apps may control Knippi. Returns whether to run the command.
    private func askToAllowAutomationURLs(for url: URL) -> Bool {
        guard !settings.automationURLsAsked else { return false }
        settings.automationURLsAsked = true

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Another app wants to control Knippi")
        alert.informativeText = String(localized: "It sent this command:\n\(url.absoluteString)\n\nAllow other apps to start captures with Knippi? You can change this later in Settings → General.")
        // "Don't Allow" first = default button: a page that says "press Return" must not get
        // permanent control of Knippi that way (audit P1, 21.11.).
        alert.addButton(withTitle: String(localized: "Don't Allow"))
        alert.addButton(withTitle: String(localized: "Allow"))
        alert.buttons.first?.keyEquivalent = "\r"
        alert.buttons.last?.keyEquivalent = ""
        let allowed = alert.runModal() == .alertSecondButtonReturn
        settings.automationURLsEnabled = allowed
        // An open Settings window keeps its view model: tell it, or the switch shows the old
        // state (audit P3).
        NotificationCenter.default.post(name: .knippiAutomationURLsSettingChanged, object: nil)
        return allowed
    }

    private func performPendingImageFileOpen() {
        guard let urls = imageFileOpenBuffer.takeIfReady(coordinatorIsReady: captureCoordinator != nil) else {
            return
        }
        captureCoordinator?.openImageFiles(urls)
    }

    private func performPendingAutomationURLAction() {
        let selectionIsActive = captureCoordinator?.isCaptureSelectionActive ?? false
        guard let action = automationURLRequestBuffer.takeIfReady(
            coordinatorIsReady: captureCoordinator != nil,
            captureSelectionIsActive: selectionIsActive
        ), let captureCoordinator else {
            return
        }

        switch action {
        case .captureArea:
            captureCoordinator.captureArea()
        case .captureFullscreen:
            guard captureCoordinator.markNextCaptureAsAutomated() else {
                return logAutomationURL("Ignored request: automated captures too close together")
            }
            captureCoordinator.captureFullscreen()
        case .captureWindow:
            captureCoordinator.captureWindow()
        case .captureAllInOne:
            captureCoordinator.captureAllInOne()
        case .captureScrolling:
            guard FeatureFlags.scrollingCapture else {
                showFeatureUnavailableNotice(action)
                return
            }
            captureCoordinator.captureScrolling()
        case .captureSelfTimer:
            captureCoordinator.captureAreaWithSelfTimer()
        case .captureLastArea:
            guard captureCoordinator.markNextCaptureAsAutomated() else {
                return logAutomationURL("Ignored request: automated captures too close together")
            }
            captureCoordinator.replayLastCapture()
        case .captureAreaToClipboard:
            captureCoordinator.captureAreaToClipboard()
        case .captureAreaAndShare:
            captureCoordinator.captureAreaAndShare()
        case .captureAreaAndAnnotate:
            captureCoordinator.captureAreaAndAnnotate()
        case .captureAreaAndPin:
            captureCoordinator.captureAreaAndPin()
        case .pickColor:
            captureCoordinator.pickColor()
        case .pinFromClipboard:
            captureCoordinator.pinFromClipboard()
        case .editClipboardImage:
            captureCoordinator.editClipboardImage()
        case .openImageFile:
            captureCoordinator.openImageFilesWithPanel()
        case .captureOCR:
            ocrCoordinator?.startInstantOCR()
        case .recordArea, .recordFullscreen:
            guard FeatureFlags.screenRecording else {
                showFeatureUnavailableNotice(action)
                return
            }
            if action == .recordArea {
                recordingCoordinator?.startRecordingFlow()
            } else {
                recordingCoordinator?.startFullScreenRecordingFlow()
            }
        case .openPreferences:
            showPreferences()
        case .openHistory:
            menuBarController?.showHistory()
        case .hideDesktopIcons:
            desktopIconsCover.setHiddenManually(true)
        case .showDesktopIcons:
            desktopIconsCover.setHiddenManually(false)
        case .toggleDesktopIcons:
            desktopIconsCover.setHiddenManually(!desktopIconsCover.isHiddenManually)
        }
        logAutomationURL("Performed action \(String(describing: action))")
    }

    private var featureUnavailableToast: ToastWindow?

    /// Automation-Befehl für eine in Phase 1 ausgeblendete Funktion: sichtbar ablehnen statt still nichts zu tun.
    private func showFeatureUnavailableNotice(_ action: AutomationURLAction) {
        logAutomationURL("Rejected hidden feature \(String(describing: action))")
        featureUnavailableToast?.orderOut(nil)
        featureUnavailableToast = ToastWindow(
            message: String(localized: "This feature is not available in this version."),
            icon: "exclamationmark.triangle.fill",
            iconColor: .systemOrange
        )
        featureUnavailableToast?.show(autoDismissAfter: 3)
    }

    private var automationBlockedNoticeAt: Date?

    /// A blocked `knippi://` command says so instead of vanishing; at most every
    /// 30 s, so a looping caller can't flood the screen with toasts.
    private func showAutomationBlockedNotice(now: Date = Date()) {
        if let last = automationBlockedNoticeAt, now.timeIntervalSince(last) < 30 { return }
        automationBlockedNoticeAt = now
        featureUnavailableToast?.orderOut(nil)
        featureUnavailableToast = ToastWindow(
            message: String(localized: "Another app tried to control Knippi. You can allow this in Settings → General."),
            icon: "hand.raised.fill",
            iconColor: .systemOrange
        )
        featureUnavailableToast?.show(autoDismissAfter: 4)
    }

    private func logAutomationURL(_ message: String) {
        guard settings.diagnosticLoggingEnabled else { return }
        DiagnosticLogger.append(message, category: "AutomationURL")
    }

    /// Called when the user reopens the app while it's already running
    /// (Spotlight, Launchpad, Finder). Launch — including Launch at Login —
    /// stays silent. Reopen always shows Preferences, since the menu bar icon
    /// may be hidden by the user or crowded out behind the notch. Handled as a
    /// raw Apple Event because SwiftUI never forwards
    /// `applicationShouldHandleReopen` to the adaptor delegate.
    @objc private func handleReopen(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        showPreferences()
    }

    func showPreferences() {
        preferencesWindow?.show()
    }

    /// Rebuild the live `ShareCoordinator` from current `AppSettings` + Keychain.
    /// Called after the Cloud Share wizard saves new credentials, and after the
    /// user resets the configuration — so the next capture's share button
    /// reflects the current state without requiring a relaunch.
    func refreshShareCoordinator() {
        shareCoordinator?.invalidate()
        shareCoordinator = makeShareCoordinator(settings: settings)
        captureCoordinator?.shareCoordinator = shareCoordinator
    }

    private func makeShareCoordinator(settings: AppSettings) -> ShareCoordinator? {
        guard
            settings.isCloudShareConfigured,
            let providerRaw = settings.cloudShareProvider,
            let provider = ShareProvider(rawValue: providerRaw),
            let urlPrefix = settings.cloudShareURLPrefix,
            let bucket = settings.cloudShareBucket
        else {
            return nil
        }

        let keychain = KeychainHelper(service: "dev.mwlr.knippi.share.\(provider.rawValue)")
        guard
            let access = AppDelegate.keychainString(keychain, account: "accessKey"),
            let secret = AppDelegate.keychainString(keychain, account: "secretKey")
        else {
            return nil
        }

        var fields: [String: String] = [:]
        if let accountID = settings.cloudShareAccountID {
            fields["accountID"] = accountID
        }
        if let region = settings.cloudShareRegion {
            fields["region"] = region
        }
        if let endpoint = settings.cloudShareEndpoint {
            fields["endpoint"] = endpoint
        }
        if let pathPrefix = settings.cloudSharePathPrefix {
            fields["pathPrefix"] = pathPrefix
        }

        let config = ShareConfig(provider: provider, urlPrefix: urlPrefix, bucket: bucket, fields: fields)
        guard let destination = try? ShareDestinationFactory.make(config: config, accessKey: access, secretKey: secret) else {
            return nil
        }
        return ShareCoordinator(destination: destination) { [settings] in
            settings.cloudShareCopyLinkWhenUploadStarts
        }
    }

    /// Read a string from Keychain. Returns nil on missing entry or known recoverable errors.
    /// Any unexpected error triggers an assertion failure in debug builds.
    private static func keychainString(_ keychain: KeychainHelper, account: String) -> String? {
        do {
            return try keychain.get(account: account)
        } catch KeychainError.interactionNotAllowed {
            // Keychain locked (e.g., app launched at login before user logs in).
            // Returning nil leaves the coordinator nil; the next share attempt rebuilds it
            // (CaptureCoordinator.availableShareCoordinator, audit P5).
            return nil
        } catch {
            Logger(subsystem: "dev.mwlr.knippi", category: "share")
                .error("Keychain read failed for \(account, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}

extension Notification.Name {
    /// Posted when the "other apps may control Knippi" answer changes outside Settings.
    static let knippiAutomationURLsSettingChanged = Notification.Name("dev.mwlr.knippi.automationURLsSettingChanged")
}

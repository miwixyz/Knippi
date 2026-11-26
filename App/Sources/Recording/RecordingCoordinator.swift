// App/Sources/Recording/RecordingCoordinator.swift
import AppKit
// AVFoundation's `AVAssetTrack` and related types aren't annotated as
// `Sendable` in the SDK yet. Without @preconcurrency, Swift 6 strict-
// concurrency builds (Xcode 17 CI) fail compiling `openEditor(…)` where
// `asset.loadTracks(withMediaType:)` returns `[AVAssetTrack]` across an
// async boundary. Local Debug builds may succeed due to DerivedData
// caching old artefacts; CI's clean build is authoritative.
@preconcurrency import AVFoundation
import Observation
import RecordingKit
import CameraKit
import CaptureKit
import SharedKit
import ExportKit
import EffectsKit
import EditorKit

enum KeyPressOverlayPermissionDecision: Equatable {
    case showOverlay
    case continueWithoutOverlay
    case cancelRecording

    static func forAlertResponse(_ response: NSApplication.ModalResponse) -> Self {
        response == .alertFirstButtonReturn ? .cancelRecording : .continueWithoutOverlay
    }
}

/// Orchestrates recording flow:
/// 1. Show overlay for area selection (drag, or Space to switch to window selection)
/// 2. Show recording toolbar (format, camera, mic, audio)
/// 3. User clicks Record → start recording with selected area
/// 4. Show controls (pause/stop/timer) + red border
/// 5. Stop → finalize MP4
@MainActor
@Observable
final class RecordingCoordinator {
    private let settings: AppSettings
    let recorder = ScreenRecorder()
    let cameraManager = CameraManager()
    var desktopIconsCover: DesktopIconsCover?

    private var overlayWindows: [CaptureOverlayWindow] = []
    private var selectionModeWindow: RecordingSelectionModeWindow?
    private var windowSelectionTask: Task<Void, Never>?
    private var toolbarWindow: RecordingToolbarWindow?
    private var selectionBorderWindow: SelectionBorderWindow?
    private var controlsWindow: RecordingControlsWindow?
    private var audioWarningPanel: RecordingWarningPanel?
    private var borderWindow: RecordingBorderWindow?
    private var cameraPiPWindow: CameraPiPWindow?
    private var recordingPreviewWindow: RecordingPreviewWindow?
    private var editorWindow: RecordingEditorWindow?
    private var editorCoordinator: EditorCoordinator?
    private var clickMonitor: ClickMonitor?
    private var cursorTelemetry: CursorTelemetry?
    private var clickHighlightWindow: ClickHighlightWindow?
    private var keyPressMonitor: KeyPressMonitor?
    private var keyPressOverlayWindow: KeyPressOverlayWindow?
    private var countdownWindow: CountdownWindow?
    private var escGlobalMonitor: Any?
    private var escLocalMonitor: Any?
    /// A stop is in progress; a second Stop (double click, warning panel, disk + writer
    /// timer in the same tick) must not report "Couldn't finish recording" (audit R4).
    private var isStopping = false
    /// Runs once the quick-preview save of the just-stopped recording finished (true = saved).
    private var pendingSaveCompletion: ((Bool) -> Void)?
    private var escEventTap: CFMachPort?
    private var escEventTapRunLoopSource: CFRunLoopSource?
    private struct AutomaticClipboardCopyResult {
        let copied: Bool
        let fileURL: URL?
    }

    private var automaticClipboardCopyTasks: [URL: Task<AutomaticClipboardCopyResult, Never>] = [:]
    private var automaticClipboardCopyState: [URL: RecordingClipboardState] = [:]

    // Selection state
    private var selectedRect: CGRect = .zero
    private var selectedScreen: NSScreen?
    private var selectedDisplayID: CGDirectDisplayID = CGMainDisplayID()
    private var selectedTarget: RecordingTarget?
    private var activeSelectionMode: RecordingSelectionMode?

    // Current recording inputs (used by restart)
    private var currentRecordingFormat: RecordingFormatChoice?
    private var currentCameraEnabled = false
    private var currentMicEnabled = false
    private var currentSystemAudioEnabled = false

    init(settings: AppSettings) {
        self.settings = settings
        cameraManager.refreshDevices()
        cameraManager.onInterrupted = { [weak self] in
            self?.handleCameraInterrupted()
        }
        recorder.onStreamInterrupted = { [weak self] error in
            self?.handleRecordingInterrupted(error: error)
        }
        recorder.onDiskSpaceLow = { [weak self] in
            self?.handleDiskSpaceLow()
        }
        recorder.onAudioIssue = { [weak self] issue in
            self?.showAudioWarning(for: issue)
        }
        recorder.onWriterFailed = { [weak self] error in
            self?.handleRecordingWriterFailed(error: error)
        }
    }

    // MARK: - Public API

    /// Start the recording flow: show overlay for area selection.
    /// A recording is running or being set up. Starting another one would
    /// film the selection UI and overwrite the running one's border and area.
    var isRecordingActive: Bool {
        recorder.state != .idle || controlsWindow != nil || countdownWindow != nil
    }

    func startRecordingFlow() {
        guard !isRecordingActive else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            // A toolbar from an earlier selection must go first: it stayed orphaned (no way to
            // close it) and its Esc tap swallowed the first Esc of the new selection (audit R5).
            self.dismissToolbarUI()
            if self.showRememberedRecordingArea() {
                return
            }
            if self.settings.recordingSelectsWindow {
                self.requestWindowSelectionOverlay()
            } else {
                self.showAreaSelectionOverlay()
            }
        }
    }

    /// Start a full-screen recording flow for the display under the pointer.
    /// The recording toolbar still appears before capture begins so the user
    /// can confirm camera, microphone, system audio, format, and countdown.
    func startFullScreenRecordingFlow() {
        guard !isRecordingActive else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.selectFullScreenForRecording()
        }
    }

    func startRecordingFlow(withSelectedArea rect: CGRect, screen: NSScreen) {
        guard !isRecordingActive else { return }
        dismissOverlay()
        dismissToolbarUI()
        handleAreaSelected(rect: rect, screen: screen)
    }

    // MARK: - Step 1: Area Selection

    private func showAreaSelectionOverlay() {
        windowSelectionTask?.cancel()
        presentSelectionOverlay(mode: .area, selectedMode: .area) { [weak self] in
            self?.requestWindowSelectionOverlay()
        }
    }

    private func requestWindowSelectionOverlay() {
        windowSelectionTask?.cancel()
        let fallbackMode = Self.windowEnumerationFallbackMode(activeMode: activeSelectionMode)
        windowSelectionTask = Task { [weak self] in
            guard let self else { return }
            let overlayIDs = Set(overlayWindows.map { CGWindowID($0.windowNumber) })
            do {
                let windows = try await ContentEnumerator.windows()
                    .filter { !overlayIDs.contains($0.id) }
                guard !Task.isCancelled else { return }
                guard !windows.isEmpty else {
                    fallBackFromWindowSelection(to: fallbackMode)
                    return
                }
                showWindowSelectionOverlay(windows: windows)
            } catch {
                guard !Task.isCancelled else { return }
                fallBackFromWindowSelection(to: fallbackMode)
                print("Window enumeration failed: \(error)")
            }
        }
    }

    private func fallBackFromWindowSelection(to mode: RecordingSelectionMode) {
        if activeSelectionMode == nil {
            showAreaSelectionOverlay()
        } else {
            selectionModeWindow?.setSelectedMode(mode)
        }
    }

    private func showWindowSelectionOverlay(windows: [WindowInfo]) {
        presentSelectionOverlay(mode: .windowSelection(windows), selectedMode: .window) { [weak self] in
            self?.showAreaSelectionOverlay()
        }
    }

    private func presentSelectionOverlay(
        mode: CaptureOverlayMode,
        selectedMode: RecordingSelectionMode,
        onSpaceToggle: @escaping () -> Void
    ) {
        dismissOverlay()
        activeSelectionMode = selectedMode
        settings.recordingSelectsWindow = selectedMode == .window

        for screen in NSScreen.screens {
            let overlay = CaptureOverlayWindow(
                screen: screen,
                settings: settings,
                handlesGlobalKeyEvents: overlayWindows.isEmpty,
                presetsDisabled: true,
                allowsMultiWindowSelection: false
            )
            overlay.onAreaSelected = { [weak self] rect, screen in
                self?.dismissOverlay()
                self?.handleAreaSelected(rect: rect, screen: screen)
            }
            overlay.onWindowSelected = { [weak self] windowID in
                self?.dismissOverlay()
                self?.handleWindowSelected(windowID: windowID)
            }
            overlay.onCancelled = { [weak self] in
                self?.dismissOverlay()
                self?.selectedTarget = nil
            }
            overlay.onSpaceToggle = onSpaceToggle
            overlay.onShortcutAction = { [weak self] action in
                self?.handleRecordingModeRequest(RecordingSelectionMode(action: action))
            }
            overlay.activate(mode: mode)
            overlayWindows.append(overlay)
        }

        showSelectionModeWindow(selectedMode: selectedMode)
    }

    private func showRememberedRecordingArea() -> Bool {
        guard settings.rememberLastRecordingArea else { return false }
        return selectLastRecordingArea()
    }

    @discardableResult
    private func selectLastRecordingArea() -> Bool {
        guard let selection = settings.lastRecordingArea else { return false }

        guard case let .area(x, y, width, height, screenID) = selection,
              width > 5,
              height > 5,
              let screen = NSScreen.screens.first(where: { $0.displayID == screenID }) else {
            return false
        }

        let screenBounds = CGRect(origin: .zero, size: screen.frame.size)
        let rect = CaptureSelectionGeometry.move(
            CGRect(x: x, y: y, width: width, height: height),
            by: .zero,
            in: screenBounds
        )
        dismissOverlay()
        dismissToolbarUI()
        handleAreaSelected(rect: rect, screen: screen)
        return true
    }

    private var canUseLastRecordingArea: Bool {
        guard let selection = settings.lastRecordingArea,
              case let .area(_, _, width, height, screenID) = selection else {
            return false
        }
        return width > 5
            && height > 5
            && NSScreen.screens.contains(where: { $0.displayID == screenID })
    }

    private func handleRecordingModeRequest(_ mode: RecordingSelectionMode) {
        switch mode {
        case .area:
            showAreaSelectionOverlay()
        case .window:
            requestWindowSelectionOverlay()
        case .fullScreen:
            selectFullScreenForRecording()
        case .lastArea:
            if !selectLastRecordingArea() {
                NSSound.beep()
            }
        }
    }

    private func selectFullScreenForRecording() {
        guard let screen = screenUnderPointer else {
            return
        }

        dismissOverlay()
        dismissToolbarUI()
        handleAreaSelected(
            rect: CGRect(origin: .zero, size: screen.frame.size),
            screen: screen,
            storesAsLastArea: false
        )
    }

    private func showSelectionModeWindow(selectedMode: RecordingSelectionMode) {
        guard let screen = screenUnderPointer else {
            return
        }

        let window = RecordingSelectionModeWindow(
            screen: screen,
            selectedMode: selectedMode,
            canUseLastArea: canUseLastRecordingArea,
            onSelect: { [weak self] mode in
                self?.handleRecordingModeRequest(mode)
            },
            onCancel: { [weak self] in
                self?.dismissOverlay()
                self?.selectedTarget = nil
            },
            onHover: { [weak self] isOver in
                self?.overlayWindows.forEach { $0.setPointerOverPanel(isOver) }
            }
        )
        window.show()
        selectionModeWindow = window
    }

    private var screenUnderPointer: NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(location) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    static func windowEnumerationFallbackMode(
        activeMode: RecordingSelectionMode?
    ) -> RecordingSelectionMode {
        activeMode ?? .area
    }

    private func handleAreaSelected(
        rect: CGRect,
        screen: NSScreen,
        storesAsLastArea: Bool = true
    ) {
        selectedScreen = screen
        selectedDisplayID = screen.displayID
        if storesAsLastArea {
            settings.lastRecordingArea = .area(rect: rect, screenID: screen.displayID)
        }

        // `rect` comes from the overlay view in view-local coordinates:
        // (0,0) at the screen's bottom-left, width/height = screen dimensions.
        // Convert to the display-local top-down coord system that every
        // downstream consumer expects (ScreenCaptureKit, CountdownWindow,
        // showRecordingControls, showBorder — all of them do `+ origin` to
        // turn this back into global AppKit coords).
        //
        // Previously this code subtracted `screenFrame.origin.x` from a
        // view-local X, which mixed coordinate systems and happened to work
        // only for the primary screen (whose origin is (0,0)). On a
        // secondary display, the resulting rect ended up on the primary
        // screen after downstream conversion, so the recording border and
        // controls toolbar both landed on the wrong display.
        let screenFrame = screen.frame
        let flippedY = screenFrame.height - rect.maxY
        selectedRect = CGRect(
            x: rect.origin.x,
            y: flippedY,
            width: rect.width,
            height: rect.height
        )
        selectedTarget = .displayArea(displayID: screen.displayID, rect: selectedRect)

        // Show the recording toolbar below the selected area
        showToolbar(selectionViewRect: rect, screen: screen)
    }

    private func handleWindowSelected(windowID: CGWindowID) {
        Task {
            let windows = try? await ContentEnumerator.windows()
            guard let window = windows?.first(where: { $0.id == windowID }) else { return }

            guard let screen = screenWithLargestIntersection(forGlobalTopLeftRect: window.frame)
                    ?? NSScreen.main ?? NSScreen.screens.first else {
                return
            }
            let pickedDisplayID = screen.displayID
            selectedScreen = screen
            selectedDisplayID = pickedDisplayID

            let displayBounds = CGDisplayBounds(pickedDisplayID)
            let displayLocalRect = CaptureDisplayGeometry.displayLocalRect(
                fromGlobalTopLeftRect: window.frame,
                displayBounds: displayBounds
            )
            guard !displayLocalRect.isNull, !displayLocalRect.isEmpty else { return }
            selectedRect = displayLocalRect
            selectedTarget = .window(windowID: windowID)

            let screenFrame = screen.frame
            let viewY = screenFrame.height - selectedRect.origin.y - selectedRect.height
            let viewRect = CGRect(
                x: selectedRect.origin.x,
                y: viewY,
                width: selectedRect.width,
                height: selectedRect.height
            )
            showToolbar(selectionViewRect: viewRect, screen: screen)
        }
    }

    private func screenWithLargestIntersection(forGlobalTopLeftRect rect: CGRect) -> NSScreen? {
        let screensByVisibleArea = NSScreen.screens.compactMap { screen -> (screen: NSScreen, area: CGFloat)? in
            let intersection = rect.intersection(CGDisplayBounds(screen.displayID))
            guard !intersection.isNull, !intersection.isEmpty else { return nil }
            return (screen, intersection.width * intersection.height)
        }
        return screensByVisibleArea.max { $0.area < $1.area }?.screen
    }

    // MARK: - Step 2: Recording Toolbar

    private func showToolbar(selectionViewRect: CGRect, screen: NSScreen) {
        // `selectionViewRect` is view-local (0-based, bottom-left origin on
        // the given screen). Both `SelectionBorderWindow` and
        // `RecordingToolbarWindow` position themselves in GLOBAL AppKit
        // screen coordinates, so convert before handing off. Without this,
        // everything lines up by accident only on the primary display.
        let globalSelectionRect = CGRect(
            x: selectionViewRect.origin.x + screen.frame.origin.x,
            y: selectionViewRect.origin.y + screen.frame.origin.y,
            width: selectionViewRect.width,
            height: selectionViewRect.height
        )

        // Show selection border with corner handles (persists while toolbar is visible)
        selectionBorderWindow = SelectionBorderWindow(selectionRect: globalSelectionRect, screen: screen)
        selectionBorderWindow?.show()

        toolbarWindow = RecordingToolbarWindow(
            selectionRect: globalSelectionRect,
            screen: screen,
            settings: settings,
            onRecord: { [weak self] format, cameraEnabled, cameraDeviceID, micEnabled, systemAudioEnabled in
                guard let self else { return }
                let willShowCountdown = self.settings.showCountdown && self.selectedScreen != nil
                self.dismissToolbarUI(keepCamera: cameraEnabled, removeEscapeMonitors: !willShowCountdown)
                if let cameraDeviceID {
                    self.cameraManager.selectedDeviceID = cameraDeviceID
                }
                self.startRecording(
                    format: format,
                    cameraEnabled: cameraEnabled,
                    micEnabled: micEnabled,
                    systemAudioEnabled: systemAudioEnabled
                )
            },
            onCameraToggled: { [weak self] enabled, deviceID in
                guard let self else { return false }
                if enabled {
                    if let deviceID {
                        self.cameraManager.selectedDeviceID = deviceID
                    }
                    self.cameraManager.stop()
                    do {
                        try await self.cameraManager.requestAccessAndStart()
                        // The macOS camera prompt can stay open while the user cancels the
                        // flow or switches the camera off again: don't start it then (audit R3).
                        guard !Task.isCancelled, self.toolbarWindow != nil else {
                            self.cameraManager.stop()
                            return false
                        }
                        self.showCameraPiP()
                        return true
                    } catch {
                        self.cameraPiPWindow?.close()
                        self.cameraPiPWindow = nil
                        self.cameraManager.stop()
                        if case CameraError.deviceUnavailable = error {
                            self.showCameraUnavailableToast()
                        } else if error is CameraError {
                            self.showCameraPermissionDeniedAlert()
                        }
                        return false
                    }
                } else {
                    self.cameraPiPWindow?.close()
                    self.cameraPiPWindow = nil
                    self.cameraManager.stop()
                    return true
                }
            },
            onChangeArea: { [weak self] in
                guard let self else { return }
                self.dismissToolbarUI()
                self.showAreaSelectionOverlay()
            },
            onCancel: { [weak self] in
                self?.cancelPendingRecordingFlow()
            },
            onCameraSettingsChanged: { [weak self] in
                self?.cameraPiPWindow?.applySettings()
            }
        )
        toolbarWindow?.show()

        installEscapeMonitors()
    }

    private func installEscapeMonitors() {
        removeEscapeMonitors()

        escGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                Task { @MainActor in
                    self?.cancelPendingRecordingFlow()
                }
            }
        }
        escLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in
                    self?.cancelPendingRecordingFlow()
                }
                return nil
            }
            return event
        }

        installEscapeEventTap()
    }

    private func removeEscapeMonitors() {
        if let m = escGlobalMonitor { NSEvent.removeMonitor(m); escGlobalMonitor = nil }
        if let m = escLocalMonitor { NSEvent.removeMonitor(m); escLocalMonitor = nil }
        if let source = escEventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            escEventTapRunLoopSource = nil
        }
        if let tap = escEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            escEventTap = nil
        }
    }

    private func installEscapeEventTap() {
        // Keep ESC working even if focus moves away from the setup toolbar.
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, refcon in
                // macOS disables a tap whose callback was too slow or on certain user
                // input; without re-enabling, ESC silently stops working (audit R16,
                // 21.11.). The tap's run-loop source is on the main run loop.
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let refcon {
                        let coordinator = Unmanaged<RecordingCoordinator>.fromOpaque(refcon).takeUnretainedValue()
                        MainActor.assumeIsolated {
                            if let tap = coordinator.escEventTap {
                                CGEvent.tapEnable(tap: tap, enable: true)
                            }
                        }
                    }
                    return Unmanaged.passUnretained(event)
                }
                guard type == .keyDown,
                      event.getIntegerValueField(.keyboardEventKeycode) == 53,
                      let refcon else {
                    return Unmanaged.passUnretained(event)
                }

                let coordinator = Unmanaged<RecordingCoordinator>.fromOpaque(refcon).takeUnretainedValue()
                Task { @MainActor in
                    coordinator.cancelPendingRecordingFlow()
                }
                return nil
            },
            userInfo: refcon
        ) else {
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        escEventTap = tap
        escEventTapRunLoopSource = source
    }

    private func cancelPendingRecordingFlow() {
        if cameraPiPWindow?.presentationModeActive == true {
            cameraPiPWindow?.exitPresentationMode()
            return
        }

        countdownWindow?.cancel()
        countdownWindow = nil
        desktopIconsCover?.setHiddenForRecording(false)
        dismissToolbarUI()
        selectedTarget = nil
    }

    private func dismissToolbarUI(keepCamera: Bool = false, removeEscapeMonitors shouldRemoveEscapeMonitors: Bool = true) {
        toolbarWindow?.close()
        toolbarWindow = nil
        selectionBorderWindow?.close()
        selectionBorderWindow = nil
        if !keepCamera {
            cameraPiPWindow?.close()
            cameraPiPWindow = nil
            cameraManager.stop()
        }
        if shouldRemoveEscapeMonitors {
            removeEscapeMonitors()
        }
    }

    // MARK: - Step 3: Start Recording

    private func makeRecordingConfig(
        format: RecordingKit.RecordingFormat,
        fps: Int,
        captureSystemAudio: Bool,
        captureMicrophone: Bool,
        showCursor: Bool
    ) -> RecordingConfig {
        switch selectedTarget ?? .displayArea(displayID: selectedDisplayID, rect: selectedRect) {
        case .displayArea(let displayID, let rect):
            return RecordingConfig(
                captureRect: rect,
                displayID: displayID,
                format: format,
                fps: fps,
                captureSystemAudio: captureSystemAudio,
                captureMicrophone: captureMicrophone,
                showCursor: showCursor
            )
        case .window(let windowID):
            return RecordingConfig(
                windowID: windowID,
                format: format,
                fps: fps,
                captureSystemAudio: captureSystemAudio,
                captureMicrophone: captureMicrophone,
                showCursor: showCursor
            )
        }
    }

    private func startRecording(
        format: RecordingFormatChoice,
        cameraEnabled: Bool,
        micEnabled: Bool,
        systemAudioEnabled: Bool,
        restoredCameraPiPState: CameraPiPRestorationState? = nil
    ) {
        guard !isRecordingActive else { return }
        var micEnabled = micEnabled
        if micEnabled {
            // Ask for the microphone only when it is switched on for a recording.
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                break
            case .notDetermined:
                Task { @MainActor [weak self] in
                    _ = await AVCaptureDevice.requestAccess(for: .audio)
                    self?.startRecording(
                        format: format, cameraEnabled: cameraEnabled, micEnabled: true,
                        systemAudioEnabled: systemAudioEnabled, restoredCameraPiPState: restoredCameraPiPState
                    )
                }
                return
            default:
                micEnabled = false
                showRecordingProblem(
                    String(localized: "Recording without microphone"),
                    detail: String(localized: "Knippi may not use the microphone. Allow it under System Settings → Privacy & Security → Microphone, then switch the microphone on again."),
                    error: nil
                )
            }
        }
        // Resolve Input Monitoring before creating any recording UI. Opening
        // System Settings cancels this attempt, as the alert instructs the user
        // to grant access and start recording again.
        guard confirmStartDespiteLowDiskSpace() else {
            dismissToolbarUI()
            selectedTarget = nil
            return
        }

        let keyPressOverlayDecision = prepareKeyPressOverlayPermission()
        guard keyPressOverlayDecision != .cancelRecording else {
            dismissToolbarUI()
            selectedTarget = nil
            return
        }
        let keyPressOverlayReady = keyPressOverlayDecision == .showOverlay

        currentRecordingFormat = format
        currentCameraEnabled = cameraEnabled
        currentMicEnabled = micEnabled
        currentSystemAudioEnabled = systemAudioEnabled

        // Editor flow renders the cursor from telemetry, so avoid baking the
        // hardware cursor into the source video in that path. The quick-preview
        // flow still keeps the native hardware cursor in the captured file.
        var config = makeRecordingConfig(
            format: format == .gif ? .gif : .video,
            fps: 30,
            captureSystemAudio: systemAudioEnabled,
            captureMicrophone: micEnabled,
            showCursor: settings.openEditorAfterRecording ? false : settings.showCursor
        )
        if micEnabled {
            // An unplugged device falls back to the system default, matching the toolbar.
            config.microphoneDeviceID = settings.recordingMicDeviceID
                .flatMap { AVCaptureDevice(uniqueID: $0)?.uniqueID }
        }

        // Start the camera if it is not already running from the toolbar
        // preview (permission was requested when it was switched on there).
        if cameraEnabled && cameraPiPWindow == nil {
            // No empty camera bubble in the video: without a camera, record without it and say so
            // (audit R8, 21.11.).
            do {
                try cameraManager.start()
                showCameraPiP(restorationState: restoredCameraPiPState)
            } catch {
                showCameraUnavailableToast()
            }
        }

        if settings.hideDesktopIconsWhileRecording {
            desktopIconsCover?.setHiddenForRecording(true)
        }

        let actuallyStart: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                do {
                    // Show the red border before starting the stream so its
                    // window ID can be passed to SCContentFilter — otherwise
                    // it gets composited into the first captured frames.
                    self.showBorder()
                    self.borderWindow?.displayIfNeeded()
                    let excludeIDs: [CGWindowID]
                    if let n = self.borderWindow?.windowNumber, n > 0 {
                        excludeIDs = [CGWindowID(n)]
                    } else {
                        excludeIDs = []
                    }
                    try await self.recorder.startRecording(config: config, excludeWindowIDs: excludeIDs)
                    self.startClickHighlight()
                    if keyPressOverlayReady {
                        self.startKeyPressOverlay()
                    }
                    self.startCursorTelemetry()
                    self.showRecordingControls()
                    self.cameraPiPWindow?.setDodgingEnabled(true)
                } catch {
                    NSLog("[Knippi] Recording failed to start: %@", String(describing: error))
                    self.desktopIconsCover?.setHiddenForRecording(false)
                    self.borderWindow?.hide()
                    self.borderWindow = nil
                    if cameraEnabled {
                        self.cameraPiPWindow?.close()
                        self.cameraPiPWindow = nil
                        self.cameraManager.stop()
                    }
                    self.showRecordingProblem(
                        String(localized: "Couldn't start recording"), error: error
                    )
                }
            }
        }

        if settings.showCountdown, let screen = selectedScreen {
            let cd = CountdownWindow(selectionRect: selectedRect, screen: screen)
            countdownWindow = cd
            cd.runCountdown {
                self.countdownWindow = nil
                self.removeEscapeMonitors()
                actuallyStart()
            }
        } else {
            actuallyStart()
        }
    }

    // MARK: - Step 4: During Recording

    /// `afterStop` runs once the recording was stopped and, in the quick-preview flow, the
    /// save finished; its argument says whether it is saved (in the editor flow it is not
    /// saved yet). Before, it ran right after the save had only *started* (audit R2).
    func stopRecording(afterStop: (@MainActor (_ saved: Bool) -> Void)? = nil) {
        guard !isStopping else { return }
        isStopping = true
        Task {
            defer { isStopping = false }
            do {
                let result = try await recorder.stopRecording()
                // Only the editor reads cursor.json; the quick-preview flow never did, so
                // writing it there just piled files up (audit R11, 21.11.).
                let cursorTelemetryURL = stopCursorTelemetry(save: settings.openEditorAfterRecording)
                hideRecordingUI()

                let tempURL = result.fileURL

                let format = result.format as RecordingKit.RecordingFormat
                startAutomaticClipboardCopyIfNeeded(url: tempURL, format: format)

                if settings.openEditorAfterRecording {
                    // The editor owns the file from here; recovery after a crash only
                    // covers the quick-preview flow (audit R6).
                    InterruptedRecording.clear(ifMarking: tempURL)
                    // Open the full recording editor (trim, zoom, export)
                    openEditor(
                        tempURL: tempURL,
                        cursorTelemetryURL: cursorTelemetryURL,
                        showsCursor: settings.showCursor,
                        recordingAreaSize: result.size,
                        outputFormat: EditorOutputFormat(recordingFormat: format)
                    )
                } else {
                    // Quick-preview flow: the recording is saved right away (like a
                    // screenshot); the preview shows the progress and stays open
                    // with Save/Copy only if saving fails. It used to close by
                    // itself after 5 s without saving, losing the recording.
                    let thumbnail = await VideoThumbnail.extractThumbnail(from: tempURL)
                    let nsThumb = thumbnail.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
                    let size = VideoThumbnail.formattedFileSize(VideoThumbnail.fileSize(at: tempURL))
                    let duration = VideoThumbnail.formattedDuration(result.duration)
                    showRecordingPreview(thumbnail: nsThumb, duration: duration, fileSize: size,
                                        tempURL: tempURL, format: format)
                    if let afterStop {
                        pendingSaveCompletion = { saved in afterStop(saved) }
                    }
                    recordingPreviewWindow?.onSave?()
                    return
                }
                afterStop?(false)
            } catch {
                NSLog("[Knippi] Failed to stop/save recording: %@", String(describing: error))
                hideRecordingUI()
                await self.handleRecordingStopFailure(error)
            }
        }
    }

    /// Stopping failed. A partly written file is saved if possible; either
    /// way the user learns what happened instead of the controls just vanishing.
    private func handleRecordingStopFailure(_ error: Error) async {
        if case RecordingError.writerFailed = error,
           let partial = recorder.partialRecordingURL,
           let savedURL = await exportRecording(partial, format: .video) {
            showRecordingProblem(
                String(localized: "Recording was cut short"),
                detail: String(localized: "Knippi could not keep writing the video. What was recorded up to that point has been saved to \(savedURL.deletingLastPathComponent().path)."),
                error: error
            )
            return
        }
        if case RecordingError.noFramesCaptured = error {
            showRecordingProblem(
                String(localized: "Nothing was recorded"),
                detail: String(localized: "The recording ended before the first frame arrived."),
                error: nil
            )
            return
        }
        showRecordingProblem(String(localized: "Couldn't finish recording"), error: error)
    }

    private func handleRecordingInterrupted(error: Error) {
        NSLog("[Knippi] Recording stream stopped unexpectedly: %@", String(describing: error))
        // Keep what was recorded (saved automatically), then say why it ended.
        stopRecording { [weak self] saved in
            if case .permissionMissing = CaptureErrorPresentation.forError(error) {
                self?.showRecordingProblem(
                    String(localized: "Recording ended"),
                    detail: saved
                        ? String(localized: "macOS withdrew the Screen Recording permission. What was recorded so far has been saved.")
                        : String(localized: "macOS withdrew the Screen Recording permission. What was recorded so far is open in Knippi but not saved yet."),
                    error: nil
                )
            } else {
                self?.showRecordingProblem(
                    String(localized: "Recording ended"),
                    detail: saved
                        ? String(localized: "macOS stopped the recording. What was recorded so far has been saved.")
                        : String(localized: "macOS stopped the recording. What was recorded so far is open in Knippi but not saved yet."),
                    error: error
                )
            }
        }
    }

    private func handleRecordingWriterFailed(error: Error) {
        NSLog("[Knippi] Recording writer failed: %@", String(describing: error))
        stopRecording()
    }

    /// Warning alert for a recording that failed or ended early.
    private func showRecordingProblem(_ title: String, detail: String? = nil, error: Error?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = [detail, error?.localizedDescription].compactMap { $0 }.joined(separator: "\n\n")
        alert.addButton(withTitle: String(localized: "OK"))
        NSApp.activate()
        alert.runModal()
    }

    private func showAudioWarning(for issue: AudioIssue) {
        guard let screen = selectedScreen, let anchor = controlsWindow?.frame else { return }
        let message: String
        var actions: [RecordingWarningPanel.Action] = [
            .init(title: String(localized: "Stop Recording"), isProminent: true) { [weak self] in
                self?.dismissAudioWarning()
                self?.stopRecording()
            },
            .init(title: String(localized: "Ignore"), isProminent: false) { [weak self] in
                self?.dismissAudioWarning()
            },
        ]
        switch issue {
        case .microphoneSilent:
            guard settings.warnAboutMutedMicrophone else { return }
            message = String(localized: "Your microphone might be muted. No sound has been picked up since the recording started.")
            actions.insert(.init(title: String(localized: "Don't Warn Again"), isProminent: false) { [weak self] in
                self?.settings.warnAboutMutedMicrophone = false
                self?.dismissAudioWarning()
            }, at: 1)
        case .microphoneStopped:
            message = String(localized: "The microphone stopped sending audio. It may have been disconnected.")
        case .systemAudioStopped:
            message = String(localized: "System audio stopped being captured. The rest of the recording may have no sound.")
        }

        dismissAudioWarning()
        audioWarningPanel = RecordingWarningPanel(message: message, actions: actions, above: anchor, screen: screen)
        audioWarningPanel?.show()
    }

    private func dismissAudioWarning() {
        audioWarningPanel?.close()
        audioWarningPanel = nil
    }

    private func handleDiskSpaceLow() {
        stopRecording(afterStop: { [weak self] saved in self?.showDiskSpaceLowAlert(saved: saved) })
    }

    private func showDiskSpaceLowAlert(saved: Bool) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Recording stopped because your disk is almost full")
        alert.informativeText = saved
            ? String(localized: "The recording was stopped and saved to prevent data loss. Free up disk space before recording again.")
            : String(localized: "The recording was stopped to prevent data loss. It is open in Knippi but not saved yet. Free up disk space before saving it.")
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }

    private func confirmStartDespiteLowDiskSpace() -> Bool {
        guard settings.warnAboutLowDiskSpace,
              let available = DiskSpace.availableBytes(at: ScreenRecorder.recordingDirectory),
              available < DiskSpace.recommendedToStartRecording else { return true }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Your disk is almost full")
        let free = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
        alert.informativeText = String(localized: "Only \(free) is free. The recording will be stopped automatically if space runs out.")
        alert.addButton(withTitle: String(localized: "Record Anyway"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = String(localized: "Don't warn me again")
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            settings.warnAboutLowDiskSpace = false
        }
        return response == .alertFirstButtonReturn
    }

    private func restartRecording() {
        // A Stop already in progress owns the file; restarting now would race it.
        guard !isStopping, let format = currentRecordingFormat else { return }
        let restoredCameraPiPState = currentCameraEnabled ? cameraPiPWindow?.restartRestorationState : nil
        isStopping = true

        Task {
            defer { isStopping = false }
            do {
                let result = try await recorder.stopRecording()
                // Discard temp file — restart should not show preview.
                InterruptedRecording.clear(ifMarking: result.fileURL)
                try? FileManager.default.removeItem(at: result.fileURL)
            } catch RecordingError.noFramesCaptured {
                // Restart pressed before the first frame: nothing to discard (the
                // recorder already removed the empty file), so just start again.
            } catch {
                // Used to be a bare print: the controls vanished with no reason
                // given, and a partly written file stayed in tmp (audit R12, 21.11.).
                discardPartialRecording()
                hideRecordingUI()
                showRecordingProblem(String(localized: "Couldn't restart recording"), error: error)
                return
            }
            hideRecordingUI()
            startRecording(
                format: format,
                cameraEnabled: currentCameraEnabled,
                micEnabled: currentMicEnabled,
                systemAudioEnabled: currentSystemAudioEnabled,
                restoredCameraPiPState: restoredCameraPiPState
            )
        }
    }

    /// Restart and Delete mean "throw this recording away"; a partly written file the
    /// recorder kept for recovery would otherwise stay in tmp (audit R12, 21.11.).
    private func discardPartialRecording() {
        guard let partial = recorder.partialRecordingURL else { return }
        InterruptedRecording.clear(ifMarking: partial)
        try? FileManager.default.removeItem(at: partial)
    }

    private func confirmDeleteRecording() {
        // A Stop already in progress owns the file; deleting now would race it.
        guard !isStopping else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Delete this recording?")
        alert.informativeText = String(localized: "The current recording will be permanently discarded.")
        alert.addButton(withTitle: String(localized: "Delete"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn, !isStopping else { return }
        isStopping = true

        Task {
            defer { isStopping = false }
            do {
                let result = try await recorder.stopRecording()
                InterruptedRecording.clear(ifMarking: result.fileURL)
                try? FileManager.default.removeItem(at: result.fileURL)
                hideRecordingUI()
            } catch {
                print("Failed to delete recording: \(error)")
                discardPartialRecording()
                hideRecordingUI()
            }
        }
    }

    private func exportRecording(
        _ tempURL: URL,
        format: RecordingKit.RecordingFormat,
        destinationOverride: URL? = nil,
        deleteSourceOnSuccess: Bool = true,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async -> URL? {
        let exportFormat: ExportFormat = format == .gif ? .gif : .mp4
        let fileFormat: FileFormat = format == .gif ? .gif : .mp4
        let destURL: URL
        if let destinationOverride {
            destURL = destinationOverride
        } else {
            let exportDir = settings.exportLocation
            let fileName = FileNaming.generateFileName(for: .recording, format: fileFormat)
            destURL = exportDir.appendingPathComponent(fileName)
        }
        let exportDir = destURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

        let options = ExportOptions(
            format: exportFormat,
            quality: settings.exportQuality,
            destination: destURL
        )

        do {
            if deleteSourceOnSuccess,
               let copyTask = automaticClipboardCopyTasks[tempURL] {
                _ = await copyTask.value
            }
            let result = try await VideoExporter.export(source: tempURL, options: options, progress: progress)
            InterruptedRecording.clear(ifMarking: tempURL)
            if deleteSourceOnSuccess {
                // Clean up temp file after successful export
                try? FileManager.default.removeItem(at: tempURL)
            }
            return result
        } catch {
            // Use NSLog so the error is visible in Console.app — `print` only
            // surfaces under Xcode-attached debugging.
            NSLog("[Knippi] Recording export FAILED (format=%@, dest=%@): %@",
                  String(describing: format), destURL.path,
                  String(describing: error))
            return nil
        }
    }

    func recoverInterruptedRecording() {
        // The marker stays until the export succeeded (`exportRecording` clears it),
        // so a failed recovery is retried on the next launch instead of lost.
        guard let url = InterruptedRecording.pending() else { return }
        Task {
            let duration = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
            guard duration > 0 else {
                InterruptedRecording.clear(ifMarking: url)
                try? FileManager.default.removeItem(at: url)
                return
            }
            guard let savedURL = await exportRecording(url, format: .video) else {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = String(localized: "Couldn't recover recording")
                alert.informativeText = String(localized: "Knippi quit unexpectedly during a recording, and saving what was captured failed. The file is still at \(url.path).")
                alert.addButton(withTitle: String(localized: "OK"))
                alert.runModal()
                return
            }
            CaptureCoordinator.postNotification(
                title: String(localized: "Recording recovered"),
                body: String(localized: "Knippi quit unexpectedly during a recording. What was captured has been saved to \(savedURL.deletingLastPathComponent().path).")
            )
        }
    }

    private func showRecordingSaveFailureAlert(format: RecordingKit.RecordingFormat) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Couldn't save recording")
        let kind = format == .gif ? String(localized: "GIF") : String(localized: "video")
        alert.informativeText = String(localized: "Saving the \(kind) to \(settings.exportLocation.path) failed. The recording is still available in the preview — close this dialog and try Save again, or use Copy.")
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }

    private func showRecordingCopyFailureAlert(
        format: RecordingKit.RecordingFormat,
        previewAvailable: Bool
    ) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Couldn't copy recording")
        let kind = format == .gif ? String(localized: "GIF") : String(localized: "video")
        if previewAvailable {
            alert.informativeText = String(localized: "Copying the \(kind) to the clipboard failed. The recording is still available in the preview — close this dialog and try Copy again, or use Save.")
        } else {
            alert.informativeText = String(localized: "Copying the \(kind) to the clipboard failed. Export it again from the editor.")
        }
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }

    func openEditor(
        tempURL: URL,
        cursorTelemetryURL: URL?,
        showsCursor: Bool,
        recordingAreaSize: CGSize,
        outputFormat: EditorOutputFormat
    ) {
        Task {
            let asset = AVURLAsset(url: tempURL)
            let duration = (try? await asset.load(.duration).seconds) ?? 0
            let tracks = try? await asset.loadTracks(withMediaType: .video)
            let naturalSize = (try? await tracks?.first?.load(.naturalSize)) ?? .zero

            let project = RecordingProject(
                sourceVideoURL: tempURL,
                cursorTelemetryURL: cursorTelemetryURL,
                showsCursor: showsCursor,
                videoDuration: duration,
                videoSize: naturalSize,
                recordingAreaSize: recordingAreaSize == .zero ? naturalSize : recordingAreaSize
            )

            let coordinator = EditorCoordinator(project: project, outputFormat: outputFormat)
            coordinator.onClose = { [weak self] in
                // The editor is the only reader of cursor.json and it is not reopened
                // later, so remove it with the editor (audit R11, 21.11.).
                if let cursorTelemetryURL {
                    try? FileManager.default.removeItem(at: cursorTelemetryURL)
                }
                // The editor closes only after a finished export or a confirmed discard
                // (RecordingEditorWindow.performClose), so the source recording in tmp
                // is no longer needed. Without this every recording stayed behind
                // (several hundred MB each).
                try? FileManager.default.removeItem(at: tempURL)
                self?.editorWindow?.close()
                self?.editorWindow = nil
                self?.editorCoordinator = nil
            }
            let window = RecordingEditorWindow(coordinator: coordinator)
            self.editorCoordinator = coordinator
            self.editorWindow = window
            window.showCentered()
        }
    }

    private func showRecordingPreview(thumbnail: NSImage?, duration: String, fileSize: String,
                                      tempURL: URL, format: RecordingKit.RecordingFormat) {
        recordingPreviewWindow?.close()
        recordingPreviewWindow = nil

        let state = RecordingPreviewState()
        let window = RecordingPreviewWindow(
            thumbnail: thumbnail, duration: duration, fileSize: fileSize,
            state: state, settings: settings
        )

        window.onCopy = { [weak self, weak window] in
            // Ignore Copy if a save is already running — same reason we
            // disable the buttons in the view (avoid double-write races).
            guard !state.isSaving else { return }
            guard let self else { return }
            state.isSaving = true
            state.saveProgress = 0
            state.progressLabel = String(localized: "Copying…")
            window?.cancelAutoDismissForSave()

            Task { @MainActor in
                let copied = await self.copyRecordingToClipboard(
                    tempURL,
                    format: format
                ) { progress in
                    Task { @MainActor in state.saveProgress = progress }
                }

                if copied {
                    self.recordingPreviewWindow?.close()
                    self.recordingPreviewWindow = nil
                } else {
                    state.isSaving = false
                    state.saveProgress = 0
                    state.progressLabel = String(localized: "Saving…")
                    self.showRecordingCopyFailureAlert(format: format, previewAvailable: true)
                }
            }
        }

        window.onSave = { [weak self, weak window] in
            guard let self else { return }
            // Ignore further clicks while a save is in flight — without
            // this guard, repeated clicks during a slow GIF export would
            // queue up multiple identical saves and write duplicate files.
            guard !state.isSaving else { return }
            state.isSaving = true
            state.saveProgress = 0
            state.progressLabel = String(localized: "Saving…")
            window?.cancelAutoDismissForSave()

            Task { @MainActor in
                let result = await self.exportRecording(tempURL, format: format) { progress in
                    // VideoExporter calls this from background contexts;
                    // hop to MainActor to mutate Observable state safely.
                    Task { @MainActor in
                        state.saveProgress = progress
                    }
                }

                let completion = self.pendingSaveCompletion
                self.pendingSaveCompletion = nil
                if let savedURL = result {
                    self.recordingPreviewWindow?.close()
                    self.recordingPreviewWindow = nil
                    self.showRecordingSavedToast(savedURL)
                } else {
                    // Reset state so the buttons return and the user can
                    // retry without restarting the recording.
                    state.isSaving = false
                    state.saveProgress = 0
                    self.showRecordingSaveFailureAlert(format: format)
                }
                completion?(result != nil)
            }
        }

        window.onClose = { [weak self] in
            // Closing mid-export would orphan the temp file with no UI to
            // recover from. Block until the save finishes.
            guard !state.isSaving else { return }
            // Still unsaved (the save failed): closing would quietly leave the recording in a
            // temp folder. Ask first (audit R7, 21.11.).
            if FileManager.default.fileExists(atPath: tempURL.path) {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = String(localized: "Discard this recording?")
                alert.informativeText = String(localized: "It hasn't been saved yet. If you close the preview, the recording is deleted.")
                alert.addButton(withTitle: String(localized: "Keep Preview Open"))
                alert.addButton(withTitle: String(localized: "Discard Recording"))
                guard alert.runModal() == .alertSecondButtonReturn else { return }
                InterruptedRecording.clear(ifMarking: tempURL)
                try? FileManager.default.removeItem(at: tempURL)
            }
            self?.recordingPreviewWindow?.close()
            self?.recordingPreviewWindow = nil
        }

        window.show()
        recordingPreviewWindow = window
    }

    private var savedToast: ToastWindow?

    /// The chosen camera is gone (unplugged) – the recording runs without the speaker view.
    /// The camera failed or was taken away mid-session: no frozen or empty bubble in
    /// the video. The camera manager has already stopped itself.
    private func handleCameraInterrupted() {
        cameraPiPWindow?.orderOut(nil)
        cameraPiPWindow?.close()
        cameraPiPWindow = nil
        savedToast?.close()
        savedToast = ToastWindow(message: String(localized: "Camera stopped – it is no longer shown"))
        savedToast?.show(autoDismissAfter: 3)
    }

    private func showCameraUnavailableToast() {
        savedToast?.close()
        savedToast = ToastWindow(message: String(localized: "Camera not available – recording without it"))
        savedToast?.show(autoDismissAfter: 3)
    }

    private func showRecordingSavedToast(_ url: URL) {
        savedToast?.close()
        savedToast = ToastWindow(message: String(localized: "Recording saved to \(url.deletingLastPathComponent().lastPathComponent)"))
        savedToast?.show()
    }

    private func startAutomaticClipboardCopyIfNeeded(
        url: URL,
        format: RecordingKit.RecordingFormat
    ) {
        guard settings.recordingAutoCopy else { return }

        let copyTask = Task(priority: .utility) { [weak self] in
            guard let self else { return AutomaticClipboardCopyResult(copied: false, fileURL: nil) }
            let copied = await copyRecordingToClipboard(
                url,
                format: format,
                deleteSourceOnSuccess: false
            )
            return AutomaticClipboardCopyResult(copied: copied, fileURL: automaticClipboardCopyState[url]?.copiedFileURL)
        }
        automaticClipboardCopyTasks[url] = copyTask

        Task { [weak self] in
            let result = await copyTask.value
            guard let self else { return }
            if !result.copied {
                showRecordingCopyFailureAlert(
                    format: format,
                    previewAvailable: self.recordingPreviewWindow != nil
                )
            }
        }
    }

    private func exportRecordingToClipboard(
        _ tempURL: URL,
        format: RecordingKit.RecordingFormat,
        deleteSourceOnSuccess: Bool = true,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async -> URL? {
        let fileFormat: FileFormat = format == .gif ? .gif : .mp4
        let clipboardDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("knippi-clipboard-exports", isDirectory: true)
        let destinationURL = clipboardDir
            .appendingPathComponent("knippi_clipboard_\(UUID().uuidString).\(FileNaming.fileExtension(for: fileFormat))")

        let exportedURL = await exportRecording(
            tempURL,
            format: format,
            destinationOverride: destinationURL,
            deleteSourceOnSuccess: deleteSourceOnSuccess,
            progress: progress
        )
        if exportedURL == nil {
            try? FileManager.default.removeItem(at: destinationURL)
        }
        return exportedURL
    }

    private func copyRecordingToClipboard(
        _ tempURL: URL,
        format: RecordingKit.RecordingFormat,
        deleteSourceOnSuccess: Bool = true,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async -> Bool {
        if deleteSourceOnSuccess {
            if let copyTask = automaticClipboardCopyTasks[tempURL] {
                let result = await copyTask.value
                if result.copied, let copiedFileURL = result.fileURL {
                    automaticClipboardCopyState[tempURL] = RecordingClipboardState(copiedFileURL: copiedFileURL)
                    let restored = RecordingClipboard.copy(
                        fileURL: copiedFileURL,
                        cleaningDirectory: copiedFileURL.deletingLastPathComponent()
                    )
                    if restored {
                        try? FileManager.default.removeItem(at: tempURL)
                        return true
                    }
                }
            } else if let copiedFileURL = automaticClipboardCopyState[tempURL]?.copiedFileURL {
                let restored = RecordingClipboard.copy(
                    fileURL: copiedFileURL,
                    cleaningDirectory: copiedFileURL.deletingLastPathComponent()
                )
                if restored {
                    try? FileManager.default.removeItem(at: tempURL)
                    return true
                }
            }
        }

        guard let clipboardURL = await exportRecordingToClipboard(
            tempURL,
            format: format,
            deleteSourceOnSuccess: deleteSourceOnSuccess,
            progress: progress
        ) else {
            return false
        }

        let copied = RecordingClipboard.copy(
            fileURL: clipboardURL,
            cleaningDirectory: clipboardURL.deletingLastPathComponent()
        )
        if copied {
            automaticClipboardCopyState[tempURL] = RecordingClipboardState(copiedFileURL: clipboardURL)
        }
        return copied
    }

    // MARK: - UI Helpers

    private func dismissOverlay() {
        windowSelectionTask?.cancel()
        windowSelectionTask = nil
        for window in overlayWindows {
            window.deactivate()
        }
        overlayWindows.removeAll()
        selectionModeWindow?.close()
        selectionModeWindow = nil
        activeSelectionMode = nil
    }

    private func startClickHighlight() {
        guard settings.highlightClicks else { return }

        let window = ClickHighlightWindow(displayID: selectedDisplayID)
        window.showWindow()
        clickHighlightWindow = window

        let monitor = ClickMonitor()
        monitor.onClick = { [weak self] point in
            Task { @MainActor in
                self?.clickHighlightWindow?.showClick(at: point)
            }
        }
        monitor.start()
        clickMonitor = monitor
    }

    private func stopClickHighlight() {
        clickMonitor?.stop()
        clickMonitor = nil
        clickHighlightWindow?.hideWindow()
        clickHighlightWindow?.close()
        clickHighlightWindow = nil
    }

    /// Ensures Input Monitoring is available when the key HUD is enabled.
    /// Must run **before** capture starts so permission UI is not recorded.
    /// Returns whether this attempt should show the overlay, continue without
    /// it, or stop so the user can grant access and start recording again.
    private func prepareKeyPressOverlayPermission() -> KeyPressOverlayPermissionDecision {
        guard settings.showKeyPressesWhileRecording else { return .continueWithoutOverlay }

        // Window-target capture only includes the selected app window, so Knippi's HUD
        // cannot appear in the file. Skip until we support compositing (if ever).
        if case .window = selectedTarget {
            return .continueWithoutOverlay
        }

        let permissions = PermissionManager()
        if permissions.requestInputMonitoringPermission() {
            return .showOverlay
        }

        return showInputMonitoringNeededAlert(permissions: permissions)
    }

    private func startKeyPressOverlay() {
        guard settings.showKeyPressesWhileRecording else { return }
        if case .window = selectedTarget { return }
        guard let recordingFrame = appKitRecordingFrame() else { return }

        // Permission was preflighted before capture; never create the HUD without access.
        let permissions = PermissionManager()
        permissions.checkInputMonitoringPermission()
        guard permissions.inputMonitoringGranted else { return }

        stopKeyPressOverlay()

        let window = KeyPressOverlayWindow(settings: settings, recordingFrame: recordingFrame)
        window.show()
        keyPressOverlayWindow = window

        let monitor = KeyPressMonitor()
        // Prefer detailed callback so command-ish keys (⌘/⌃) start a new bezel line (KeyCastr).
        monitor.onKeyDisplayDetailed = { [weak self] label, isCommand in
            Task { @MainActor in
                guard let self else { return }
                // Plain typing only if the user opted in; read live so the switch works mid-recording.
                if self.settings.showOnlyShortcutKeyPresses, !isCommand { return }
                self.keyPressOverlayWindow?.appendChip(label, isCommand: isCommand)
            }
        }
        monitor.start()
        keyPressMonitor = monitor
    }

    /// Recording selection as an AppKit global frame (bottom-left origin).
    /// Shared by controls, border, PiP, and the key-press HUD.
    private func appKitRecordingFrame() -> CGRect? {
        guard let screen = selectedScreen else { return nil }
        let screenFrame = screen.frame
        let viewY = screenFrame.height - selectedRect.origin.y - selectedRect.height
        return CGRect(
            x: selectedRect.origin.x + screenFrame.origin.x,
            y: viewY + screenFrame.origin.y,
            width: selectedRect.width,
            height: selectedRect.height
        )
    }

    private func stopKeyPressOverlay() {
        keyPressMonitor?.stop()
        keyPressMonitor = nil
        keyPressOverlayWindow?.hideAndClose()
        keyPressOverlayWindow = nil
    }

    private func showInputMonitoringNeededAlert(
        permissions: PermissionManager
    ) -> KeyPressOverlayPermissionDecision {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(localized: "Input Monitoring Needed")
        alert.informativeText = String(localized: "To show key presses while recording, enable Knippi in System Settings > Privacy & Security > Input Monitoring, then start recording again.")
        alert.addButton(withTitle: String(localized: "Open Input Monitoring Settings"))
        alert.addButton(withTitle: String(localized: "Continue Without Overlay"))
        alert.window.level = .screenSaver + 2
        let response = alert.runModal()
        let decision = KeyPressOverlayPermissionDecision.forAlertResponse(response)
        if decision == .cancelRecording {
            permissions.openInputMonitoringSettings()
        }
        return decision
    }

    private func startCursorTelemetry() {
        // CursorTelemetry normalizes CGEvent positions, which are in global
        // TOP-LEFT origin. `selectedRect` is in display-local top-left origin
        // (see handleAreaSelected), so the correct global-top-left origin of
        // the recording rect is `CGDisplayBounds(displayID).origin + selectedRect.origin`.
        //
        // Do NOT use NSScreen.frame here — that is in AppKit BOTTOM-LEFT origin
        // and would require flipping CGEvent positions to match, which is what
        // downstream code does NOT do. Using the bottom-left rect against a
        // top-left event position produces an overlay cursor drawn at the
        // wrong on-screen location.
        let displayBounds = CGDisplayBounds(selectedDisplayID)
        let globalRect = CGRect(
            x: displayBounds.origin.x + selectedRect.origin.x,
            y: displayBounds.origin.y + selectedRect.origin.y,
            width: selectedRect.width,
            height: selectedRect.height
        )
        let telemetry = CursorTelemetry(recordingRect: globalRect)
        telemetry.start()
        cursorTelemetry = telemetry
    }

    private func stopCursorTelemetry(save: Bool) -> URL? {
        guard let telemetry = cursorTelemetry else { return nil }
        telemetry.stop()
        cursorTelemetry = nil
        guard save else { return nil }

        let recordingsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Knippi/Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)

        let telemetryURL = recordingsDir.appendingPathComponent("\(UUID().uuidString).cursor.json")
        do {
            try telemetry.save(to: telemetryURL)
            return telemetryURL
        } catch {
            return nil
        }
    }

    private func showRecordingControls() {
        guard let screen = selectedScreen,
              let recordingFrame = appKitRecordingFrame() else { return }

        controlsWindow = RecordingControlsWindow(
            recordingFrame: recordingFrame,
            screen: screen,
            recorder: recorder,
            onStop: { [weak self] in self?.stopRecording() },
            onRestart: { [weak self] in self?.restartRecording() },
            onDelete: { [weak self] in self?.confirmDeleteRecording() }
        )
        controlsWindow?.show()
    }

    private func showBorder() {
        guard let screen = selectedScreen,
              let recordingFrame = appKitRecordingFrame() else { return }
        // RecordingBorderWindow takes the capture rect and pushes the stroke outside
        // it by itself (`outset`); expanding here as well put the border 3 pt too
        // far out (audit R15, 21.11.).
        borderWindow = RecordingBorderWindow(frame: recordingFrame, screen: screen)
        borderWindow?.show()
    }

    private func hideRecordingUI() {
        stopClickHighlight()
        stopKeyPressOverlay()
        cursorTelemetry?.stop()
        cursorTelemetry = nil
        controlsWindow?.close()
        controlsWindow = nil
        desktopIconsCover?.setHiddenForRecording(false)
        dismissAudioWarning()
        borderWindow?.hide()
        borderWindow = nil
        // Force the camera window off screen before closing.
        cameraPiPWindow?.orderOut(nil)
        cameraPiPWindow?.close()
        cameraPiPWindow = nil
        cameraManager.stop()
    }

    private func showCameraPiP(restorationState: CameraPiPRestorationState? = nil) {
        // Close an existing camera window first to prevent duplicates.
        cameraPiPWindow?.orderOut(nil)
        cameraPiPWindow?.close()
        cameraPiPWindow = nil

        cameraPiPWindow = CameraPiPWindow(
            cameraManager: cameraManager,
            settings: settings,
            recordingFrame: appKitRecordingFrame(),
            restorationState: restorationState
        )
        cameraPiPWindow?.show()
    }

    private func showCameraPermissionDeniedAlert() {
        let shouldRestoreToolbar = toolbarWindow?.isVisible == true
        toolbarWindow?.orderOut(nil)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Camera Access Needed")
        alert.informativeText = String(localized: "Camera access is turned off. Enable Knippi in System Settings > Privacy & Security > Camera, then try again.")
        alert.addButton(withTitle: String(localized: "Open Camera Settings"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.window.level = .screenSaver + 2

        let response = alert.runModal()
        if shouldRestoreToolbar {
            toolbarWindow?.show()
        }
        guard response == .alertFirstButtonReturn,
              let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

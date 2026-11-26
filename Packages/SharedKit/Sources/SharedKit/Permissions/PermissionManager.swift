import AppKit
import AVFoundation
import CoreGraphics
import Observation
import os
@preconcurrency import ScreenCaptureKit

public enum PermissionKind: String, CaseIterable, Sendable {
    case screenRecording
    case accessibility
    case inputMonitoring
    case camera
    case microphone

    public var settingsURL: URL {
        switch self {
        case .screenRecording:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        case .inputMonitoring:
            // Input Monitoring pane (ListenEvent) — required for global keystroke visualizer.
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        case .camera:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        }
    }
}

@Observable
@MainActor
public final class PermissionManager {
    public private(set) var screenRecordingGranted: Bool = false
    public private(set) var cameraGranted: Bool = false
    public private(set) var microphoneGranted: Bool = false
    public private(set) var accessibilityGranted: Bool = false
    public private(set) var inputMonitoringGranted: Bool = false

    public init() {}

    public func refreshAll() async {
        await checkScreenRecordingPermission()
        checkAccessibilityPermission()
        checkInputMonitoringPermission()
        checkCameraPermission()
        checkMicrophonePermission()
    }

    // MARK: - Screen Recording

    public func checkScreenRecordingPermission() async {
        // Apples Statusabfrage ohne Nebenwirkung, deshalb zuerst. Korrektur
        // 2026-11-20 (macOS 27.2): Die frühere Annahme, die Aufnahme habe trotz
        // -3801 funktioniert, war ein Messfehler — CGDisplayCreateImage lieferte
        // ohne Freigabe nur das Schreibtischbild (keine Fenster, keine Menüleiste).
        // Das -3801 von SCShareableContent war korrekt.
        // 2026-11-26: Keine Nachprüfung per SCShareableContent mehr. Ohne Freigabe zeigt
        // dieser Aufruf jedes Mal den macOS-Dialog „… möchte den Bildschirm aufnehmen“ –
        // beim Öffnen der Einstellungen und bei jedem Zurückkehren in die App. Die
        // Statusabfrage reicht (siehe Korrektur oben).
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        if !screenRecordingGranted {
            Logger(subsystem: "dev.mwlr.knippi", category: "permissions")
                .info("Screen recording permission not granted (preflight)")
        }
    }

    // MARK: - Camera

    public func checkCameraPermission() {
        cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    public func requestCameraPermission() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraGranted = true
        case .notDetermined:
            cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        default:
            cameraGranted = false
        }
    }

    // MARK: - Microphone

    public func checkMicrophonePermission() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    public func requestMicrophonePermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            microphoneGranted = true
        case .notDetermined:
            microphoneGranted = await AVCaptureDevice.requestAccess(for: .audio)
        default:
            microphoneGranted = false
        }
    }

    // MARK: - Accessibility

    public func checkAccessibilityPermission() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    /// Prompt the user to grant Accessibility permission.
    /// Opens System Settings if not yet trusted.
    public func requestAccessibilityPermission() {
        // AXIsProcessTrustedWithOptions with prompt option
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Input Monitoring

    public func checkInputMonitoringPermission() {
        inputMonitoringGranted = CGPreflightListenEventAccess()
    }

    /// Request Input Monitoring so global keystroke monitors can receive events.
    /// Returns whether access is currently granted after the request attempt.
    @discardableResult
    public func requestInputMonitoringPermission() -> Bool {
        if CGPreflightListenEventAccess() {
            inputMonitoringGranted = true
            return true
        }
        let granted = CGRequestListenEventAccess()
        inputMonitoringGranted = granted
        return granted
    }

    // MARK: - Open System Settings

    public func openScreenRecordingSettings() {
        openSettings(for: .screenRecording)
    }

    public func openMicrophoneSettings() {
        openSettings(for: .microphone)
    }

    public func openAccessibilitySettings() {
        openSettings(for: .accessibility)
    }

    public func openInputMonitoringSettings() {
        openSettings(for: .inputMonitoring)
    }

    public func openSettings(for kind: PermissionKind) {
        NSWorkspace.shared.open(kind.settingsURL)
    }
}

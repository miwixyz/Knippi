// App/Sources/Capture/ScrollCaptureAutoScroller.swift
import ApplicationServices
import CaptureKit
import CoreGraphics

/// Scrolls the page under a scrolling capture by itself (auto mode).
///
/// Sends scroll-wheel events to the middle of the selection, which needs the
/// Accessibility permission ("Gerätesteuerung und Datenzugriff" on macOS 27).
enum ScrollCaptureAutoScroller {
    /// Share of the selection height scrolled per step; the rest overlaps,
    /// which the stitcher needs to line frames up.
    static let stepShare = 0.4

    static var isPermitted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that leads to the Accessibility setting.
    static func requestPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary // kAXTrustedCheckOptionPrompt
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// `captureRect` in display points, top-left origin (ScreenCaptureKit).
    static func make(captureRect: CGRect, displayID: CGDirectDisplayID) -> ScrollCaptureController.AutoScroller {
        let display = CGDisplayBounds(displayID)
        let center = CGPoint(x: display.minX + captureRect.midX, y: display.minY + captureRect.midY)
        let step = Int32(max(20, (captureRect.height * stepShare).rounded()))
        return {
            // Scroll events go to the window under the pointer.
            CGWarpMouseCursorPosition(center)
            guard let event = CGEvent(
                scrollWheelEvent2Source: nil, units: .pixel,
                wheelCount: 1, wheel1: -step, wheel2: 0, wheel3: 0
            ) else { return }
            event.location = center
            event.post(tap: .cghidEventTap)
        }
    }
}

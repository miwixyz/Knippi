// App/Sources/Capture/CaptureNotifications.swift
import Foundation

extension Notification.Name {
    /// Posted after the desktop (including any system alert) has been frozen.
    static let knippiCaptureDidFreezeDesktop = Notification.Name("knippiCaptureDidFreezeDesktop")
    /// Posted after the interactive capture overlay has been dismissed.
    static let knippiCaptureDidEnd = Notification.Name("knippiCaptureDidEnd")
}

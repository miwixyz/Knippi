// Packages/SharedKit/Sources/SharedKit/Settings/CameraSettings.swift
// Speaker picture (webcam picture-in-picture) during screen recordings.
// Restored from Capso (removed in Knippi phase 1, back in 0.3.0).
import CoreGraphics
import Foundation

public enum CameraShape: String, CaseIterable, Sendable {
    case circle
    case square     // 1:1 with rounded corners
    case landscape  // 16:9
    case portrait   // 9:16

    /// Aspect ratio (width / height) for this shape.
    public var aspectRatio: CGFloat {
        switch self {
        case .circle, .square: return 1.0
        case .landscape: return 16.0 / 9.0
        case .portrait: return 9.0 / 16.0
        }
    }
}

public enum CameraSize: String, CaseIterable, Sendable {
    case small   // 100pt shorter dimension
    case medium  // 150pt
    case large   // 220pt

    /// Length of the shorter dimension in points.
    public var shorterDimension: CGFloat {
        switch self {
        case .small: return 100
        case .medium: return 150
        case .large: return 220
        }
    }
}


public extension AppSettings {
    public var cameraShape: CameraShape {
        get {
            guard let raw = defaults.string(forKey: "cameraShape"),
                  let value = CameraShape(rawValue: raw) else { return .circle }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: "cameraShape") }
    }

    public var cameraSize: CameraSize {
        get {
            guard let raw = defaults.string(forKey: "cameraSize"),
                  let value = CameraSize(rawValue: raw) else { return .medium }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: "cameraSize") }
    }

    public var cameraMirror: Bool {
        get { defaults.object(forKey: "cameraMirror") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "cameraMirror") }
    }

    /// Custom size (shorter dimension in points). 0 means use the cameraSize preset.
    /// Set when the user drags the corner resize handle.
    public var cameraCustomSizePt: Double {
        get { defaults.object(forKey: "cameraCustomSizePt") as? Double ?? 0 }
        set { defaults.set(newValue, forKey: "cameraCustomSizePt") }
    }

    /// When `true`, the camera PiP becomes nearly transparent while the pointer is over it
    /// (so content behind it is readable without moving the window). Idle stays fully solid.
    /// Presentation / fullscreen mode always stays opaque. Off by default.
    /// Recorded output matches on-screen opacity.
    public var cameraPiPFadeOnHover: Bool {
        get { defaults.object(forKey: "cameraPiPFadeOnHover") as? Bool ?? false }
        set {
            guard cameraPiPFadeOnHover != newValue else { return }
            defaults.set(newValue, forKey: "cameraPiPFadeOnHover")
            NotificationCenter.default.post(name: .cameraPiPHoverOptionsChanged, object: self)
        }
    }

    /// When `true`, mouse clicks pass through the small camera PiP to whatever is behind it
    /// while the pointer is over it. Independent of fade-on-hover. Off by default.
    /// Never applies in fullscreen / presentation mode (PiP stays interactive there).
    public var cameraPiPClickThrough: Bool {
        get { defaults.object(forKey: "cameraPiPClickThrough") as? Bool ?? false }
        set {
            guard cameraPiPClickThrough != newValue else { return }
            defaults.set(newValue, forKey: "cameraPiPClickThrough")
            NotificationCenter.default.post(name: .cameraPiPHoverOptionsChanged, object: self)
        }
    }

}


public extension Notification.Name {
    /// Posted when `cameraPiPFadeOnHover` or `cameraPiPClickThrough` changes,
    /// so a live PiP can re-apply opacity / click-through without observing all UserDefaults writes.
    static let cameraPiPHoverOptionsChanged = Notification.Name("cameraPiPHoverOptionsChanged")
}

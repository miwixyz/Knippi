// Packages/SharedKit/Sources/SharedKit/Settings/WelcomeGate.swift
import Foundation

/// Decides whether the one-time welcome window appears (new in 0.8.0).
///
/// It is for new installs only: someone updating from an older Knippi has no
/// `welcomeShown` value yet but already knows the app.
public enum WelcomeGate {
    /// Knippi writes this key on every launch (since Capso). Read it before the
    /// launch writes it: missing means this is the very first launch.
    static let launchMarkerKey = "NSInitialToolTipDelay"

    public static func hasLaunchedBefore(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: launchMarkerKey) != nil
    }

    public static func shouldShow(settings: AppSettings, hasLaunchedBefore: Bool) -> Bool {
        !hasLaunchedBefore && !settings.welcomeShown
    }

    /// Defaults that changed in 0.8.0 apply to new installs only. An install from before
    /// that never touched the switch has no stored value and would silently change on
    /// update; store its old default instead (`screenshotAutoSave` was off).
    public static func keepPreviousDefaults(settings: AppSettings, defaults: UserDefaults = .standard,
                                            hasLaunchedBefore: Bool) {
        guard hasLaunchedBefore, defaults.object(forKey: "screenshotAutoSave") == nil else { return }
        settings.screenshotAutoSave = false
    }
}

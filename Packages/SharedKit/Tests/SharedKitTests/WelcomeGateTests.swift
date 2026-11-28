import Foundation
import Testing
@testable import SharedKit

@Suite("WelcomeGate")
struct WelcomeGateTests {
    private func freshDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("A fresh install shows the welcome window")
    func freshInstallShows() {
        let defaults = freshDefaults("test.welcome.fresh")
        let launchedBefore = WelcomeGate.hasLaunchedBefore(defaults: defaults)
        #expect(WelcomeGate.shouldShow(settings: AppSettings(defaults: defaults), hasLaunchedBefore: launchedBefore))
    }

    @Test("An install from before the welcome window does not show it after the update")
    func existingInstallSkips() {
        let defaults = freshDefaults("test.welcome.existing")
        defaults.set(300, forKey: "NSInitialToolTipDelay")   // written on every launch since Capso
        let launchedBefore = WelcomeGate.hasLaunchedBefore(defaults: defaults)
        #expect(launchedBefore)
        #expect(!WelcomeGate.shouldShow(settings: AppSettings(defaults: defaults), hasLaunchedBefore: launchedBefore))
    }

    @Test("Once dismissed it never shows again")
    func dismissedSkips() {
        let defaults = freshDefaults("test.welcome.dismissed")
        let settings = AppSettings(defaults: defaults)
        settings.welcomeShown = true
        #expect(!WelcomeGate.shouldShow(settings: AppSettings(defaults: defaults), hasLaunchedBefore: false))
    }

    @Test("An update keeps auto-save off for installs that never changed it")
    func updateKeepsOldAutoSaveDefault() {
        let defaults = freshDefaults("test.welcome.autosave.update")
        let settings = AppSettings(defaults: defaults)
        WelcomeGate.keepPreviousDefaults(settings: settings, defaults: defaults, hasLaunchedBefore: true)
        #expect(!AppSettings(defaults: defaults).screenshotAutoSave)
    }

    @Test("An update keeps an explicit auto-save choice")
    func updateKeepsExplicitChoice() {
        let defaults = freshDefaults("test.welcome.autosave.explicit")
        let settings = AppSettings(defaults: defaults)
        settings.screenshotAutoSave = true
        WelcomeGate.keepPreviousDefaults(settings: settings, defaults: defaults, hasLaunchedBefore: true)
        #expect(AppSettings(defaults: defaults).screenshotAutoSave)
    }

    @Test("A new install gets auto-save on")
    func freshInstallGetsNewDefault() {
        let defaults = freshDefaults("test.welcome.autosave.fresh")
        let settings = AppSettings(defaults: defaults)
        WelcomeGate.keepPreviousDefaults(settings: settings, defaults: defaults, hasLaunchedBefore: false)
        #expect(AppSettings(defaults: defaults).screenshotAutoSave)
    }
}

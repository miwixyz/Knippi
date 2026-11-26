import Foundation

/// Remembers the file of the recording in progress so it can be recovered
/// if the app quits before the recording is finalized.
public enum InterruptedRecording {
    static let key = "inProgressRecordingPath"

    static func mark(_ url: URL, defaults: UserDefaults = .standard) {
        defaults.set(url.path, forKey: key)
    }

    public static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    /// Forgets the marker once `url` is safely saved elsewhere (or deliberately discarded).
    /// Until then a crash leaves it for recovery on the next launch (audit R6, 21.11.).
    public static func clear(ifMarking url: URL, defaults: UserDefaults = .standard) {
        guard defaults.string(forKey: key) == url.path else { return }
        defaults.removeObject(forKey: key)
    }

    /// Returns the file left behind by an unfinished recording without
    /// forgetting it, so the marker survives until the file is safely saved
    /// (`clear(ifMarking:)`). A marker whose file is gone is dropped.
    public static func pending(defaults: UserDefaults = .standard) -> URL? {
        guard let path = defaults.string(forKey: key) else { return nil }
        guard FileManager.default.fileExists(atPath: path) else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    /// Returns the file left behind by an unfinished recording, if it still
    /// exists, and forgets it so recovery runs at most once.
    public static func take(defaults: UserDefaults = .standard) -> URL? {
        guard let path = defaults.string(forKey: key) else { return nil }
        defaults.removeObject(forKey: key)
        return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }
}

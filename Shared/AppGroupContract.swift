import Foundation

/// Single source of truth for everything the app and its widget share.
///
/// The app and the Widget extension are separate processes; they can only see each
/// other's data through the shared App Group container. All persistence (the SwiftData
/// store and the proof/progress photo files) lives under `AppGroup.containerURL`.
enum AppGroup {
    /// Must match `com.apple.security.application-groups` in both entitlements files.
    static let id = "group.app.75her.com"

    /// Root of the shared container. In production (signed, with the App Group entitlement)
    /// this is the real shared container the app and widget both see. For unsigned dev/simulator
    /// builds where the entitlement is absent, we fall back to a local Application Support
    /// directory so the app still runs (the widget just won't share data in that mode).
    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) {
            return url
        }
        let fm = FileManager.default
        let fallback = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Her75Shared", isDirectory: true)
        if !fm.fileExists(atPath: fallback.path) {
            try? fm.createDirectory(at: fallback, withIntermediateDirectories: true)
        }
        return fallback
    }

    /// SwiftData store location, shared by app + widget.
    static var storeURL: URL {
        containerURL.appendingPathComponent("Her75.store")
    }

    /// Directory that holds proof/progress photo files (kept out of the database).
    static var photosURL: URL {
        let url = containerURL.appendingPathComponent("Photos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    /// UserDefaults suite shared across processes (lightweight flags, e.g. widget refresh hints).
    static var defaults: UserDefaults {
        UserDefaults(suiteName: id) ?? .standard
    }
}

/// WidgetKit timeline reload trigger name, used by both sides.
enum WidgetKind {
    static let today = "Her75TodayWidget"
}

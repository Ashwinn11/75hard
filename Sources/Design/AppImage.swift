import SwiftUI
import UIKit

/// Loads bundled royalty-free photos (flat files in Resources/Images) by name.
/// Falls back gracefully so a missing image never breaks layout — callers get a
/// tasteful gradient placeholder instead.
enum AppImage {
    // Bounded so decoded bundled photos (marquee / hero images) can't accumulate unbounded.
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 40
        return c
    }()

    static func ui(_ name: String) -> UIImage? {
        if let hit = cache.object(forKey: name as NSString) { return hit }
        guard let url = url(for: name), let img = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(img, forKey: name as NSString)
        return img
    }

    static func exists(_ name: String) -> Bool { url(for: name) != nil }

    /// Resources/Images is bundled as a folder reference, so photos live under `Images/` in the
    /// bundle. Fall back to the bundle root for any loose/flattened resources.
    private static func url(for name: String) -> URL? {
        for ext in ["jpg", "jpeg", "png"] {
            if let u = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Images") { return u }
            if let u = Bundle.main.url(forResource: name, withExtension: ext) { return u }
        }
        return nil
    }
}

/// The user's profile photo for the Today screen ("make it yours"). Stored in the shared
/// container; a version counter in UserDefaults lets views refresh when it changes.
enum ProfilePhoto {
    static var fileURL: URL { AppGroup.containerURL.appendingPathComponent("profile.jpg") }
    static func load() -> UIImage? { UIImage(contentsOfFile: fileURL.path) }
    static func save(_ data: Data) {
        // The avatar renders at ≤128pt; store a small square-ish JPEG, not the camera original.
        let out = ImageProcessing.downsampledJPEG(data, maxPixel: 512, quality: 0.85) ?? data
        try? out.write(to: fileURL)
        let v = UserDefaults.standard.integer(forKey: "profilePhotoV")
        UserDefaults.standard.set(v + 1, forKey: "profilePhotoV")
    }
}

/// A photo that fills its frame, or a soft branded gradient if the asset is missing.
struct PhotoFill: View {
    let name: String
    var fallback: LinearGradient = Theme.clayGradient

    var body: some View {
        if let ui = AppImage.ui(name) {
            Image(uiImage: ui).resizable().scaledToFill()
        } else {
            fallback
        }
    }
}

import UIKit
import ImageIO

/// Photo decoding helpers. A 75-cell hive can hold dozens of proof photos; decoding
/// each at full JPEG resolution would spike memory into the gigabytes, so we always
/// decode a cell-sized thumbnail via ImageIO downsampling.
enum ImageProcessing {

    /// Downsample image `data` so its largest edge is ~`maxPixel` points (×scale handled by caller).
    static func thumbnail(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let pixels = max(1, Int(maxPixel.rounded()))
        let srcOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, srcOptions) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // respect EXIF orientation
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Compress a UIImage to JPEG for on-disk storage of a proof photo.
    static func jpeg(_ image: UIImage, quality: CGFloat = 0.8) -> Data? {
        image.jpegData(compressionQuality: quality)
    }
}

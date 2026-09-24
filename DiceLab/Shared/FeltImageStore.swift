import UIKit

/// Persists the user's custom felt photo — one file in Documents, kept out
/// of `UserDefaults` (which is for settings, not textures) and out of the
/// asset catalog (user content isn't a build-time asset).
enum FeltImageStore {
    private static let fileName = "felt.jpg"
    /// The picker hands us whatever the photo library holds — downscale so a
    /// 12 MP portrait doesn't become a texture.
    private static let maxSide: CGFloat = 1024

    private static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: fileName)
    }

    static func save(_ image: UIImage) {
        let scaled = image.scaled(toFit: maxSide)
        try? scaled.jpegData(compressionQuality: 0.8)?.write(to: url)
    }

    static func load() -> UIImage? {
        UIImage(contentsOfFile: url.path)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}

private extension UIImage {
    func scaled(toFit maxSide: CGFloat) -> UIImage {
        // Measure pixels, not points: `size` is in points, so a 2×/3×
        // source could exceed the pixel cap unseen.
        let pixelSize = cgImage.map { CGSize(width: $0.width, height: $0.height) }
            ?? CGSize(width: size.width * scale, height: size.height * scale)
        let scale = min(1, maxSide / max(pixelSize.width, pixelSize.height))
        guard scale < 1 else { return self }
        let newSize = CGSize(width: pixelSize.width * scale,
                             height: pixelSize.height * scale)
        // scale = 1 makes renderer points == pixels — the device display
        // scale can't re-inflate the output (a 1024-pt render at 3× would
        // emit a 3072-px texture).
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

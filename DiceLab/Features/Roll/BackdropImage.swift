import UIKit

/// Runtime-drawn backdrop images — equirectangular (2:1) vertical gradients
/// with a bright horizon band, because one image serves every consumer:
/// SceneKit's `scene.background` *and* `lightingEnvironment`, RealityKit's
/// dome texture *and* its `cubeFromEquirectangular` IBL source. No assets,
/// same rule as `DieFaceTexture`.
enum BackdropImage {

    /// Equirect size. Everything downstream resamples it (the dome's UVs,
    /// the IBL cube), so a modest source loses nothing — 1024×512 keeps a
    /// photo of any size honest too.
    private static let size = CGSize(width: 1024, height: 512)

    /// What the backdrop resolves to on screen: the user's photo when one
    /// is picked and still loadable, else the preset's gradient, else nil —
    /// which each engine renders as its pre-M9d look (flat black).
    static func resolve(_ backdrop: BackdropAppearance) -> UIImage? {
        if backdrop.usesImage, let photo = UserImageStore.backdrop.load() {
            return photo
        }
        return image(for: backdrop.preset)
    }

    /// A preset's gradient, or nil for `.none` — "no backdrop" is a real
    /// choice, not a missing image.
    static func image(for preset: BackdropPreset) -> UIImage? {
        switch preset {
        case .none:
            return nil
        case .graphite:
            // Neutral dark studio — a cool gray band, lights nothing warm.
            return gradient(top: UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1),
                            horizon: UIColor(red: 0.30, green: 0.30, blue: 0.34, alpha: 1),
                            bottom: UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1))
        case .dusk:
            // Deep blue zenith into a violet horizon.
            return gradient(top: UIColor(red: 0.03, green: 0.04, blue: 0.12, alpha: 1),
                            horizon: UIColor(red: 0.30, green: 0.18, blue: 0.42, alpha: 1),
                            bottom: UIColor(red: 0.02, green: 0.02, blue: 0.06, alpha: 1))
        case .ember:
            // Warm low glow — the horizon band reads as firelight.
            return gradient(top: UIColor(red: 0.09, green: 0.03, blue: 0.02, alpha: 1),
                            horizon: UIColor(red: 0.52, green: 0.20, blue: 0.07, alpha: 1),
                            bottom: UIColor(red: 0.04, green: 0.02, blue: 0.01, alpha: 1))
        }
    }

    /// Three-stop vertical gradient — zenith → horizon → floor. The horizon
    /// sits at the image's vertical center, which is where an equirect
    /// sampler expects it.
    private static func gradient(top: UIColor, horizon: UIColor,
                                 bottom: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [top.cgColor, horizon.cgColor, bottom.cgColor] as CFArray,
                locations: [0, 0.5, 1]) {
                cg.drawLinearGradient(gradient, start: .zero,
                                      end: CGPoint(x: 0, y: size.height),
                                      options: [])
            } else {
                top.setFill()
                cg.fill(CGRect(origin: .zero, size: size))
            }
        }
    }
}

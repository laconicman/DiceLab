import SceneKit

/// Runtime-generated die faces: no asset catalog, one `UIImage` per value,
/// applied to the die's material slots — six for the cube, twenty for the
/// icosahedron.
///
/// Apple never documents which `materials` index covers which box face, so
/// instead of hardcoding an order we *derive* it: the box's single geometry
/// element groups triangles contiguously per face, and each group's mean
/// vertex position is its outward normal; the custom d20 geometry gives
/// every face its own element, and the same mean-vertex trick applies.
/// `DieFace` stays the value↔normal authority; this file maps slot→face,
/// so visible faces can never disagree with the reported face-up value.
enum DieFaceTexture {

    /// Pip cells on a 3×3 grid, (column, row), (0,0) top-left. Pure data —
    /// tested — so the drawing code has nothing to get wrong but ink.
    static func pipLayout(for value: Int) -> [SIMD2<Int>] {
        switch value {
        case 1: [[1, 1]]
        case 2: [[0, 0], [2, 2]]
        case 3: [[0, 0], [1, 1], [2, 2]]
        case 4: [[0, 0], [2, 0], [0, 2], [2, 2]]
        case 5: [[0, 0], [2, 0], [1, 1], [0, 2], [2, 2]]
        case 6: [[0, 0], [2, 0], [0, 1], [2, 1], [0, 2], [2, 2]]
        default: []
        }
    }

    /// The UV patch a flat-shaded triangle face samples, in image space
    /// with v pointing DOWN — (0,0) is the image's top-left: the
    /// equilateral triangle inscribed in the image's center circle,
    /// apex at top so the numeral's top meets it. Shared by both
    /// engines; each converts to its own V convention where it builds
    /// texture coordinates.
    static let triangleUVs: [SIMD2<Float>] = [
        [0.5, 0.0], [0.067, 0.75], [0.933, 0.75],
    ]

    /// Cache key: the ink colors, shape, and translucency reach the
    /// pixels — finish channels shape the material, not the texture, so
    /// keying by them would duplicate identical images on every slider
    /// edit.
    private struct Ink: Hashable {
        let face: CodableColor
        let pip: CodableColor
        let shape: DieShape
        let translucency: Double
        /// Emission images carry a glow mask in alpha (opaque only where
        /// the packed color is non-black) so the mirror composite adds
        /// opacity exactly where light is added — pixels differ, so the
        /// mask can't share a cache entry with the diffuse draw.
        let glowMask: Bool
    }

    /// Face images per ink, drawn lazily and cached — identical for
    /// every die, so `materials(for:)` reuses them instead of re-rendering
    /// per spawn. Main-actor state: the controllers build dice on the
    /// main actor anyway, and a plain static dictionary read and written
    /// from Swift Testing's parallel workers is a data race — CI tripped
    /// on it once the M10 suites multiplied the readers.
    @MainActor private static var faceImageCache: [Ink: [UIImage]] = [:]

    /// The cached faces, 1…`shape.faceCount`, keyed by ink alone — the
    /// diffuse channel both engines bind, and the alpha both read as
    /// opacity when `translucency` is up (body α = color α × (1 − t),
    /// ink keeps the pip color's α). Emission draws through here too
    /// with translucency 0 and `glowMask`: its alpha is a glow mask the
    /// composite reads, while the engines' emission channels read RGB
    /// only.
    @MainActor static func images(face: CodableColor, pip: CodableColor,
                                  shape: DieShape,
                                  translucency: Double = 0,
                                  glowMask: Bool = false) -> [UIImage] {
        // Clamp once: an out-of-range payload must not mint a negative-
        // alpha fill, and values that clamp alike share one cache entry.
        let t = min(max(translucency, 0), 1)
        let key = Ink(face: face, pip: pip, shape: shape, translucency: t,
                      glowMask: glowMask)
        if let cached = faceImageCache[key] { return cached }
        // Color sliders mint a key per sampled value — a long edit session
        // could grow the map without limit, so it resets past 16 entries.
        if faceImageCache.count >= 16 { faceImageCache.removeAll(keepingCapacity: false) }
        let drawn = (1...shape.faceCount).map {
            image(for: $0, shape: shape, face: face, pip: pip,
                  bodyAlpha: 1 - CGFloat(t), glowMask: glowMask)
        }
        faceImageCache[key] = drawn
        return drawn
    }

    /// The diffuse channel — the RealityKit path binds the same images
    /// through `TextureResource` for color and opacity; generation stays
    /// in one place.
    @MainActor static func images(for appearance: DieAppearance,
                                  shape: DieShape) -> [UIImage] {
        images(face: appearance.faceColor, pip: appearance.pipColor,
               shape: shape, translucency: appearance.translucency)
    }

    /// The emission channel as images, or nil when nothing emits: the
    /// packed colors put each part's *share of the peak* in the texture so
    /// the material's scalar intensity can carry the magnitude (see
    /// `EmissionAppearance`). `peak == 0` means "leave emission off" — no
    /// black textures need drawing.
    @MainActor static func emissionImages(for appearance: DieAppearance,
                                          shape: DieShape) -> [UIImage]? {
        let emission = appearance.emission
        guard emission.peak > 0 else { return nil }
        return images(face: emission.packedFace, pip: emission.packedPips,
                      shape: shape, glowMask: true)
    }

    /// Composite key for the mirror bake: every input that reaches the
    /// pixels — diffuse ink, packed emission ink, the intensity alpha,
    /// translucency (the base's alpha rides into the composite), and the
    /// shape (pips vs numerals).
    private struct MirrorInk: Hashable {
        let face: CodableColor
        let pip: CodableColor
        let emissionFace: CodableColor
        let emissionPip: CodableColor
        let intensity: Double
        let translucency: Double
        let shape: DieShape
    }

    /// Baked composites for the RealityKit mirror copies (TD-13): the
    /// diffuse face with its emission added on top — an `UnlitMaterial`
    /// has no emissive channel, so the glow is baked into the texture.
    /// `plusLighter` approximates the PBR `texture × intensity` add; the
    /// draw alpha is `min(intensity, 1)`, so glow above 1× reads dimmer
    /// in the mirror than on the die — accepted, the copy is already
    /// dimmed. Nil when nothing emits: callers keep reusing the dice's
    /// own `TextureResource`s, which costs nothing per slider tick.
    @MainActor static func mirrorImages(for appearance: DieAppearance,
                                        shape: DieShape) -> [UIImage]? {
        let emission = appearance.emission
        guard let emissionImages = emissionImages(for: appearance, shape: shape)
        else { return nil }
        let key = MirrorInk(face: appearance.faceColor, pip: appearance.pipColor,
                            emissionFace: emission.packedFace,
                            emissionPip: emission.packedPips,
                            intensity: emission.intensity,
                            translucency: min(max(appearance.translucency, 0), 1),
                            shape: shape)
        if let cached = mirrorImageCache[key] { return cached }
        if mirrorImageCache.count >= 16 {
            mirrorImageCache.removeAll(keepingCapacity: false)
        }
        let diffuse = images(for: appearance, shape: shape)
        let alpha = CGFloat(min(emission.intensity, 1))
        let drawn = (0..<shape.faceCount).map { index in
            composite(base: diffuse[index], emission: emissionImages[index],
                      alpha: alpha)
        }
        mirrorImageCache[key] = drawn
        return drawn
    }

    @MainActor private static var mirrorImageCache: [MirrorInk: [UIImage]] = [:]

    /// Base face with the emission image added on top — `plusLighter`
    /// adds source to destination, which is what an emissive channel
    /// does to a lit surface. The emission image's alpha is a glow mask
    /// (opaque only where its packed color is non-black), so the add
    /// raises opacity exactly where light is added: a glass die's body
    /// keeps its translucency in the reflection instead of growing a
    /// solid dark one, and the body alpha no longer couples to the glow
    /// intensity.
    private static func composite(base: UIImage, emission: UIImage,
                                  alpha: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: base.size).image { _ in
            base.draw(at: .zero)
            emission.draw(at: .zero, blendMode: .plusLighter, alpha: alpha)
        }
    }

    /// Runtime-drawn face: fill + pips or a numeral. The fill's alpha is
    /// the color's own alpha × `bodyAlpha` — 1 for opaque dice, the
    /// translucency factor for glass — so the picker's opacity survives
    /// the dial; ink keeps the pip color's alpha untouched: glass you
    /// can still read. `glowMask` zeroes the fill's alpha when the
    /// packed emission color is black — the mirror composite then adds
    /// opacity only where light is actually added. Ink is never masked:
    /// opaque black pip ink is what keeps face glow off the pips.
    /// The same image serves as diffuse RGB, SceneKit `transparent`
    /// map, and RealityKit opacity texture.
    static func image(for value: Int, shape: DieShape,
                      face: CodableColor, pip: CodableColor,
                      side: CGFloat = 256, bodyAlpha: CGFloat = 1,
                      glowMask: Bool = false) -> UIImage {
        let size = CGSize(width: side, height: side)
        let ink = pip.uiColor
        // Below ~1/255 per channel the 8-bit bitmap quantizes to black
        // anyway — masking it off keeps alpha honest with the pixels.
        let emits = face.red + face.green + face.blue > 0.004
        let fillAlpha = glowMask && !emits ? 0
            : CGFloat(face.alpha) * bodyAlpha
        return UIGraphicsImageRenderer(size: size).image { _ in
            face.uiColor.withAlphaComponent(fillAlpha).setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()

            switch shape {
            case .d6:
                ink.setFill()
                let margin = side * 0.24
                let step = (side - 2 * margin) / 2
                let radius = side * 0.085
                for cell in pipLayout(for: value) {
                    let center = CGPoint(x: margin + step * CGFloat(cell.x),
                                         y: margin + step * CGFloat(cell.y))
                    UIBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                width: radius * 2, height: radius * 2)).fill()
                }
            case .d20:
                // Numerals, not pips — a d20's faces are too small to read
                // a count. 6 and 9 carry the underline bar real dice use
                // to disambiguate them; the typeface's own underline keeps
                // it glued to the baseline instead of floating free.
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: side * Numeral.pointScale),
                    .foregroundColor: ink,
                    .underlineStyle: (value == 6 || value == 9)
                        ? NSUnderlineStyle.single.rawValue : 0,
                    .underlineColor: ink,
                ]
                let text = NSAttributedString(string: String(value),
                                              attributes: attributes)
                let textSize = text.size()
                text.draw(at: CGPoint(x: (side - textSize.width) / 2,
                                      y: (side - textSize.height) / 2))
            }
        }
    }

    /// Numeral metrics for the d20: the point size must keep two digits
    /// inside the incircle (radius side/4) of the triangle UV patch the
    /// faces sample.
    private enum Numeral {
        static let pointScale: CGFloat = 0.34
    }

    /// One material per material slot, in the geometry's own order — the
    /// assignment is derived from vertex data, never assumed (see type
    /// docs). Finish channels come from the appearance: `clearCoat` is the
    /// lacquer layer that makes a die read as polished resin instead of
    /// printed cardboard. Emission is a second texture, not a flat color:
    /// `emission.intensity` carries the peak while the texture holds the
    /// face-vs-pip ratio, which is the only way "glowing pips, dark body"
    /// fits one emission channel.
    ///
    /// Translucency reuses the diffuse image's alpha as the transparency
    /// map — body α = color α × (1 − t), ink keeps the pip color's α —
    /// and turns the material double-
    /// sided so the far side's ink reads through the near side's glass.
    @MainActor static func materials(for geometry: SCNGeometry, shape: DieShape,
                                     appearance: DieAppearance = Appearance.ivory.die) -> [SCNMaterial] {
        let images = images(for: appearance, shape: shape)
        let emissionImages = emissionImages(for: appearance, shape: shape)
        let translucent = appearance.translucency > 0
        return materialAxes(of: geometry).map { direction in
            let value = DieFace.value(facing: direction, shape: shape)
            let material = SCNMaterial()
            material.lightingModel = .physicallyBased
            material.diffuse.contents = images[value - 1]
            material.roughness.contents = NSNumber(value: appearance.roughness)
            material.metalness.contents = NSNumber(value: appearance.metalness)
            material.clearCoat.contents = NSNumber(value: appearance.clearcoat)
            if translucent {
                material.transparent.contents = images[value - 1]
                material.isDoubleSided = true
                material.transparencyMode = .dualLayer
            }
            if let emissionImages {
                material.emission.contents = emissionImages[value - 1]
                material.emission.intensity = CGFloat(appearance.emission.intensity)
            }
            return material
        }
    }

    /// The outward direction of each material slot, in slot order. An
    /// SCNBox has ONE geometry element — six material slots map to
    /// contiguous triangle groups inside it (measured: +Z,+X,−Z,−X,+Y,−Y,
    /// two triangles per face); the d20's custom geometry gives each face
    /// its own element. Either way a slot's mean vertex position *is* its
    /// face normal's direction, and `DieFace.value` resolves it.
    static func materialAxes(of geometry: SCNGeometry) -> [SIMD3<Float>] {
        guard let vertices = geometry.sources(for: .vertex).first else { return [] }
        if geometry.elements.count > 1 {
            // One element per face — the custom d20 layout.
            return geometry.elements.map {
                meanVertex(indicesOf($0)[...], in: vertices)
            }
        }
        guard let element = geometry.elements.first else { return [] }
        let indices = indicesOf(element)
        let perFace = indices.count / 6
        guard perFace > 0 else { return [] }
        return (0..<6).map { face in
            let group = indices[(face * perFace)..<((face + 1) * perFace)]
            return meanVertex(group, in: vertices)
        }
    }

    private static func indicesOf(_ element: SCNGeometryElement) -> [Int] {
        element.data.withUnsafeBytes { raw in
            switch element.bytesPerIndex {
            case 2: raw.bindMemory(to: UInt16.self).map(Int.init)
            default: raw.bindMemory(to: UInt32.self).map(Int.init)
            }
        }
    }

    private static func meanVertex(_ indices: ArraySlice<Int>,
                                   in source: SCNGeometrySource) -> SIMD3<Float> {
        var sum = SIMD3<Float>.zero
        for index in indices {
            let base = source.dataOffset + index * source.dataStride
            // Read three Floats, not SIMD3<Float>: packed float3 vertex
            // data is 12-byte stride — a SIMD3 load demands 16-byte
            // alignment the data doesn't guarantee.
            let v = source.data.withUnsafeBytes { data -> SIMD3<Float> in
                SIMD3(data.load(fromByteOffset: base, as: Float.self),
                      data.load(fromByteOffset: base + 4, as: Float.self),
                      data.load(fromByteOffset: base + 8, as: Float.self))
            }
            sum += v
        }
        return indices.isEmpty ? .zero : sum / Float(indices.count)
    }
}

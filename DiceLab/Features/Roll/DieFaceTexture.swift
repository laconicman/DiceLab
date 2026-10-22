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

    /// Cache key: only the shape and the two ink colors reach the pixels —
    /// finish channels shape the material, not the texture, so keying by
    /// them would duplicate identical images on every slider edit.
    private struct Ink: Hashable {
        let face: CodableColor
        let pip: CodableColor
        let shape: DieShape
    }

    /// Face images per ink, drawn lazily and cached — identical for
    /// every die, so `materials(for:)` reuses them instead of re-rendering
    /// per spawn. Main-actor state: the controllers build dice on the
    /// main actor anyway, and a plain static dictionary read and written
    /// from Swift Testing's parallel workers is a data race — CI tripped
    /// on it once the M10 suites multiplied the readers.
    @MainActor private static var faceImageCache: [Ink: [UIImage]] = [:]

    /// The cached faces, 1…`shape.faceCount`, keyed by ink alone — the
    /// diffuse and emission channels both draw through here; a
    /// packed-emission ink that happens to match a diffuse ink shares the
    /// same images.
    @MainActor static func images(face: CodableColor, pip: CodableColor,
                                  shape: DieShape) -> [UIImage] {
        let key = Ink(face: face, pip: pip, shape: shape)
        if let cached = faceImageCache[key] { return cached }
        // Color sliders mint a key per sampled value — a long edit session
        // could grow the map without limit, so it resets past 16 entries.
        if faceImageCache.count >= 16 { faceImageCache.removeAll(keepingCapacity: false) }
        let drawn = (1...shape.faceCount).map {
            image(for: $0, shape: shape, face: face, pip: pip)
        }
        faceImageCache[key] = drawn
        return drawn
    }

    /// The diffuse channel — the RealityKit path binds the same images
    /// through `TextureResource`; generation stays in one place.
    @MainActor static func images(for appearance: DieAppearance,
                                  shape: DieShape) -> [UIImage] {
        images(face: appearance.faceColor, pip: appearance.pipColor, shape: shape)
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
                      shape: shape)
    }

    /// Runtime-drawn face: opaque fill + pips or a numeral. The fill must
    /// be opaque — transparent texture corners render as holes in the die
    /// face (the geometry's chamfer already provides the rounded look).
    static func image(for value: Int, shape: DieShape,
                      face: CodableColor, pip: CodableColor,
                      side: CGFloat = 256) -> UIImage {
        let size = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: size).image { _ in
            face.uiColor.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()

            switch shape {
            case .d6:
                pip.uiColor.setFill()
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
                    .foregroundColor: pip.uiColor,
                    .underlineStyle: (value == 6 || value == 9)
                        ? NSUnderlineStyle.single.rawValue : 0,
                    .underlineColor: pip.uiColor,
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
    @MainActor static func materials(for geometry: SCNGeometry, shape: DieShape,
                                     appearance: DieAppearance = Appearance.ivory.die) -> [SCNMaterial] {
        let images = images(for: appearance, shape: shape)
        let emissionImages = emissionImages(for: appearance, shape: shape)
        return materialAxes(of: geometry).map { direction in
            let value = DieFace.value(facing: direction, shape: shape)
            let material = SCNMaterial()
            material.lightingModel = .physicallyBased
            material.diffuse.contents = images[value - 1]
            material.roughness.contents = NSNumber(value: appearance.roughness)
            material.metalness.contents = NSNumber(value: appearance.metalness)
            material.clearCoat.contents = NSNumber(value: appearance.clearcoat)
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

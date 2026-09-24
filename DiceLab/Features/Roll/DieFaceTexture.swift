import SceneKit

/// Runtime-generated die faces: no asset catalog, one `UIImage` per value,
/// applied to the six material slots of an `SCNBox`.
///
/// Apple never documents which `materials` index covers which box face, so
/// instead of hardcoding an order we *derive* it: each geometry element's
/// mean vertex position is its outward normal. `DieFace.axes` stays the
/// value↔axis authority; this file maps axis→material slot, so visible
/// pips can never disagree with the reported face-up value.
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

    /// A face texture: rounded ivory square with black pips.
    static func image(for value: Int, side: CGFloat = 256) -> UIImage {
        let size = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor(white: 0.96, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size),
                         cornerRadius: side * 0.12).fill()

            UIColor.black.setFill()
            let margin = side * 0.24
            let step = (side - 2 * margin) / 2
            let radius = side * 0.085
            for pip in pipLayout(for: value) {
                let center = CGPoint(x: margin + step * CGFloat(pip.x),
                                     y: margin + step * CGFloat(pip.y))
                UIBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius,
                                            width: radius * 2, height: radius * 2)).fill()
            }
        }
    }

    /// Six materials in the box's own material order — the assignment is
    /// derived from geometry, never assumed (see type docs).
    static func materials(for box: SCNBox) -> [SCNMaterial] {
        materialAxes(of: box).map { axis in
            let material = SCNMaterial()
            material.lightingModel = .physicallyBased
            material.diffuse.contents = image(for: value(on: axis))
            material.roughness.contents = NSNumber(0.35)
            material.metalness.contents = NSNumber(0)
            return material
        }
    }

    /// Face value for an axis, via `DieFace.axes` — the single authority.
    static func value(on axis: SIMD3<Float>) -> Int {
        DieFace.axes.first { simd_equal($0.normal, axis) }!.value
    }

    /// The dominant outward axis of each material slot, in order. An SCNBox
    /// has ONE geometry element — six material slots map to contiguous
    /// triangle groups inside it (measured: +Z,+X,−Z,−X,+Y,−Y, two triangles
    /// per face). Each group's mean vertex position (from the box center)
    /// is its face normal; quantizing to the dominant component gives ±axes.
    static func materialAxes(of box: SCNBox) -> [SIMD3<Float>] {
        guard let vertices = box.sources(for: .vertex).first,
              let element = box.elements.first else { return [] }
        let indices = indicesOf(element)
        let perFace = indices.count / 6
        guard perFace > 0 else { return [] }
        return (0..<6).map { face in
            let group = indices[(face * perFace)..<((face + 1) * perFace)]
            return dominantAxis(of: meanVertex(group, in: vertices))
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

    private static func dominantAxis(of v: SIMD3<Float>) -> SIMD3<Float> {
        let absV = abs(v)
        if absV.x >= absV.y, absV.x >= absV.z { return SIMD3(sign(v.x), 0, 0) }
        if absV.y >= absV.z { return SIMD3(0, sign(v.y), 0) }
        return SIMD3(0, 0, sign(v.z))
    }

    private static func sign(_ x: Float) -> Float { x >= 0 ? 1 : -1 }
}

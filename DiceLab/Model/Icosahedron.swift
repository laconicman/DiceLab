import simd

/// The d20's shape as pure data: twelve unit-circumradius vertices,
/// twenty face triples, and the outward normal per face derived from
/// them. Engine layers build their own meshes and colliders from this;
/// the model never imports SceneKit or RealityKit.
enum Icosahedron {
    /// Cyclic permutations of (0, ±1, ±φ), normalized to unit
    /// circumradius so the data scales cleanly into either engine's
    /// world units.
    static let vertices: [SIMD3<Float>] = {
        let phi = (1 + Float(5).squareRoot()) / 2
        let raw: [SIMD3<Float>] = [
            [0, 1, phi], [0, -1, phi], [0, 1, -phi], [0, -1, -phi],
            [1, phi, 0], [-1, phi, 0], [1, -phi, 0], [-1, -phi, 0],
            [phi, 0, 1], [-phi, 0, 1], [phi, 0, -1], [-phi, 0, -1],
        ]
        return raw.map(simd_normalize)
    }()

    /// Vertex-index triples wound counter-clockwise seen from outside —
    /// and ordered in antipodal pairs: faces 2k and 2k + 1 have opposite
    /// normals. That adjacency is the convention the d20 value table
    /// (opposites summing to 21) relies on.
    static let faces: [SIMD3<Int>] = [
        [0, 1, 8], [2, 3, 11],
        [0, 8, 4], [3, 7, 11],
        [0, 4, 5], [3, 6, 7],
        [0, 5, 9], [3, 10, 6],
        [0, 9, 1], [2, 10, 3],
        [1, 6, 8], [2, 11, 5],
        [1, 7, 6], [2, 5, 4],
        [1, 9, 7], [2, 4, 10],
        [4, 8, 10], [7, 9, 11],
        [5, 11, 9], [6, 10, 8],
    ]

    /// Unit outward normal per face — the dual dodecahedron's vertex
    /// directions: (±1, ±1, ±1)/√3 plus cyclic permutations of
    /// (0, ±φ, ±1/φ). Computed from `vertices`/`faces` rather than
    /// typed, so the normals can't silently disagree with the geometry.
    static let normals: [SIMD3<Float>] = faces.map { face in
        let v0 = vertices[face.x], v1 = vertices[face.y], v2 = vertices[face.z]
        return simd_normalize(simd_cross(v1 - v0, v2 - v0))
    }
}

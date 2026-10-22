import simd

/// Which face of a die is up, as pure math — no SceneKit, so the M7
/// RealityKit port keeps it and tests run without a scene. Per-shape since
/// M10: `axes(for:)` is the normal↔value table, `value(facing:shape:)` the
/// resolver both engines and the texture mapper share.
enum DieFace {
    /// The cube's table: face values on the die's local axes, opposites
    /// adjacent and summing to 7. This ordering is a convention, not a
    /// claim about either engine's internals — `DieFaceTexture` maps
    /// textures onto material slots by deriving each slot's direction
    /// from geometry.
    private static let cube: [(normal: SIMD3<Float>, value: Int)] = [
        (SIMD3(1, 0, 0), 1), (SIMD3(-1, 0, 0), 6),
        (SIMD3(0, 1, 0), 2), (SIMD3(0, -1, 0), 5),
        (SIMD3(0, 0, 1), 3), (SIMD3(0, 0, -1), 4),
    ]

    /// The d20's values in `Icosahedron.faces` order, with the three
    /// conventions gaming d20s follow: antipodal pairs (2k, 2k + 1) sum
    /// to 21; the five faces meeting at every one of the 12 vertices
    /// sum to 52 or 53 — 5 × 10.5 is the ideal integers can't hit; and
    /// no two edge-adjacent faces carry consecutive values. Fairness is
    /// unaffected — a regular icosahedron lands on every face equally —
    /// this is what keeps the die from reading as a spindown, where the
    /// high numbers cluster around one vertex.
    private static let d20Values: [Int] = [
        1, 20, 7, 14, 11, 10, 18, 3, 16, 5, 8, 13, 15, 6, 12, 9, 19, 2, 4, 17,
    ]

    /// The normal→value table for a shape — the value↔normal authority.
    /// Opposite faces sit adjacent (indices 2k, 2k + 1) either way, so
    /// pairing rules are a stride-2 walk for both shapes.
    static func axes(for shape: DieShape) -> [(normal: SIMD3<Float>, value: Int)] {
        switch shape {
        case .d6: cube
        case .d20: zip(Icosahedron.normals, d20Values).map { ($0, $1) }
        }
    }

    /// The value whose normal best aligns with `direction` — largest dot
    /// product wins. For the cube the nearest of six axes *is* the old
    /// dominant-axis quantization, so the quantizer disappeared rather
    /// than growing a second resolver.
    static func value(facing direction: SIMD3<Float>, shape: DieShape) -> Int {
        axes(for: shape)
            .max(by: { simd_dot($0.normal, direction) < simd_dot($1.normal, direction) })!
            .value
    }

    /// The value on top: rotate world +Y into body space and take the
    /// nearest normal — the same math as scoring each normal's rotated
    /// `.y`. Pass `node.presentation.simdOrientation` — the presentation
    /// node is what the renderer actually draws mid-animation.
    static func up(of orientation: simd_quatf, shape: DieShape) -> Int {
        value(facing: orientation.inverse.act(SIMD3(0, 1, 0)), shape: shape)
    }
}

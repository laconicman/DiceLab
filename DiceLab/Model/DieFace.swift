import simd

/// Which face of a d6 is up, as pure math — no SceneKit, so the M7 RealityKit
/// port keeps it and tests run without a scene.
enum DieFace {
    /// Face values on the die's local axes; opposites sum to 7. The order
    /// matches `SCNBox`'s material order [+X, −X, +Y, −Y, +Z, −Z], which is
    /// what M5's face textures will map onto.
    static let axes: [(normal: SIMD3<Float>, value: Int)] = [
        (SIMD3(1, 0, 0), 1), (SIMD3(-1, 0, 0), 6),
        (SIMD3(0, 1, 0), 2), (SIMD3(0, -1, 0), 5),
        (SIMD3(0, 0, 1), 3), (SIMD3(0, 0, -1), 4),
    ]

    /// The value on top: the local face normal that best aligns with world +Y
    /// after `orientation`. Pass `node.presentation.simdOrientation` — the
    /// presentation node is what the renderer actually draws mid-animation.
    static func up(of orientation: simd_quatf) -> Int {
        axes.max { orientation.act($0.normal).y < orientation.act($1.normal).y }!.value
    }
}

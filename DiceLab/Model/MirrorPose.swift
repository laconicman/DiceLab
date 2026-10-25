import simd

/// The transform that puts a body's mirror image under a horizontal plane —
/// the RealityKit felt reflection (M12) is mirrored dice under a
/// see-through felt, because iOS RealityKit has no planar reflection pass.
/// Engine-free like `CameraOrbit`: `Transform` takes these three pieces as
/// is, and the test pins the geometry instead of a screenshot.
///
/// A reflection is an *improper* transform — no rotation reproduces it —
/// so the copy carries a negative scale on its own y axis, and the
/// rotation it carries is the original's conjugated by that mirror:
/// `M R M` for `M = diag(1, −1, 1)`, which flips the x and z imaginary
/// parts. Together, `R′ · (M v) = M · (R v)`: every vertex lands where the
/// mirror would put it.
enum MirrorPose {
    /// Local scale of the mirrored copy — flips the mesh in its own frame.
    /// Winding flips with it, so the copy's materials must cull *front*
    /// faces (measured: with default culling the copy renders inside-out
    /// yet looks solid — only the pip values give it away).
    static let scale = SIMD3<Float>(1, -1, 1)

    /// The body's position reflected across `y = planeY`.
    static func position(_ position: SIMD3<Float>, planeY: Float) -> SIMD3<Float> {
        SIMD3(position.x, 2 * planeY - position.y, position.z)
    }

    /// The rotation the mirrored copy carries: the original conjugated by
    /// the y-mirror. A rotation about axis `a` by `θ` becomes a rotation
    /// about the mirrored axis by `−θ` — reflection reverses handedness.
    static func orientation(_ orientation: simd_quatf) -> simd_quatf {
        simd_quatf(ix: -orientation.imag.x, iy: orientation.imag.y,
                   iz: -orientation.imag.z, r: orientation.real)
    }
}

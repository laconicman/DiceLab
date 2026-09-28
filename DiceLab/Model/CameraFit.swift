import Foundation
import simd

/// The framing math behind scripted camera fit (M9b) — engine-free value
/// functions so SceneKit and RealityKit compute the same answer in their
/// own units, and tests can pin the geometry without a renderer.
///
/// The contract: given the dice's positions, a vertical field of view, and
/// the viewport aspect, produce a camera position that puts every die
/// inside the frame. The camera's home orientation is fixed at build time,
/// so fitting is "slide along the view axis until the bounding box's
/// extents fit," never a re-aim; orientation is only ever damped back toward
/// home to unwind a user orbit, which the quaternion `damp` does safely.
enum CameraFit {

    /// The cluster's footprint on the felt: midpoint plus half-extents in
    /// x and z (the two axes the camera's fixed pose maps to screen width
    /// and height). `padding` is per-engine breathing room — a die's
    /// half-diagonal plus margin — added to each axis independently.
    ///
    /// A box, not a sphere: the sphere forces the cluster's widest span to
    /// fit the *narrower* FOV axis, so a line-shaped pair pays for radius
    /// it never uses and the dice land tiny. Per-axis extents fit each
    /// axis against its own half-FOV — dice stay fully framed with no
    /// dead margin.
    static func boundingBox(of points: [SIMD3<Float>], padding: Float)
        -> (center: SIMD3<Float>, extents: SIMD2<Float>)
    {
        guard !points.isEmpty else { return (.zero, .init(padding, padding)) }
        var lo = points[0], hi = points[0]
        for p in points.dropFirst() {
            lo = simd_min(lo, p)
            hi = simd_max(hi, p)
        }
        return ((lo + hi) / 2,
                .init((hi.x - lo.x) / 2 + padding, (hi.z - lo.z) / 2 + padding))
    }

    /// How far along the view axis the box's center must sit so both axes
    /// fit: `atan(e/d) <= halfFOV` per axis gives `d >= e/tan(halfFOV)`,
    /// and the distance is whichever axis asks more. In portrait the
    /// horizontal half-angle is small, so x-spreads price high; z-spreads
    /// ride the generous vertical FOV — the asymmetry the sphere wasted.
    static func requiredDistance(xExtent: Float, zExtent: Float,
                                 verticalFieldOfView: Float,
                                 aspect: Float) -> Float {
        // A not-yet-laid-out view feeds aspect 0 or NaN (0/0 geometry) —
        // either would propagate straight into the camera's transform,
        // and a NaN transform never recovers. Fall back to square.
        let safeAspect = (aspect.isFinite && aspect > 0) ? aspect : 1
        let halfV = verticalFieldOfView * .pi / 360
        let halfH = atan(tan(halfV) * safeAspect)
        return max(xExtent / tan(halfH), zExtent / tan(halfV))
    }

    /// Exponential approach toward a target — `rate` 5/s reaches ~99% in
    /// one second and, unlike a fixed-duration animation, tracks a moving
    /// target without restarting. This is the "one animation eases into
    /// another" mechanism: the target flips home↔fit on speed thresholds
    /// and the damped position follows continuously.
    static func damp(_ current: SIMD3<Float>, toward target: SIMD3<Float>,
                     rate: Float, dt: Float) -> SIMD3<Float> {
        current + (target - current) * (1 - exp(-rate * max(dt, 0)))
    }

    /// Quaternion version of `damp` — with the guard `simd_slerp` needs:
    /// it divides by `sin(θ)`, so identical quats (θ = 0) return NaN, and
    /// a NaN orientation blanks the frame *forever*. Near-equal → just
    /// adopt the target; non-finite inputs → snap, never propagate.
    static func damp(_ current: simd_quatf, toward target: simd_quatf,
                     rate: Float, dt: Float) -> simd_quatf {
        let s = 1 - exp(-rate * max(dt, 0))
        guard current.vector.w.isFinite, current.vector.x.isFinite,
              current.vector.y.isFinite, current.vector.z.isFinite
        else { return target }
        return simd_dot(current, target) > 0.9999 ? target
                                                  : simd_slerp(current, target, s)
    }
}

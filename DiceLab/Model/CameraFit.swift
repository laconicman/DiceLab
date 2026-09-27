import Foundation
import simd

/// The framing math behind scripted camera fit (M9b) — engine-free value
/// functions so SceneKit and RealityKit compute the same answer in their
/// own units, and tests can pin the geometry without a renderer.
///
/// The contract: given the dice's positions, a vertical field of view, and
/// the viewport aspect, produce a camera position that puts every die
/// inside the frame. The camera's home orientation is fixed at build time,
/// so fitting is "slide along the view axis until the bounding sphere
/// fits," never a re-aim; orientation is only ever damped back toward
/// home to unwind a user orbit, which the quaternion `damp` does safely.
enum CameraFit {

    /// The smallest sphere covering all dice: centroid plus enough radius
    /// for the farthest die's corner. `padding` is per-engine breathing room
    /// (a die's half-diagonal plus margin) in that engine's units.
    static func boundingSphere(of points: [SIMD3<Float>], padding: Float)
        -> (center: SIMD3<Float>, radius: Float)
    {
        guard !points.isEmpty else { return (.zero, padding) }
        let center = points.reduce(.zero, +) / Float(points.count)
        let radius = points.map { simd_distance($0, center) }.max() ?? 0
        return (center, radius + padding)
    }

    /// How far along the view axis the sphere's center must sit so the
    /// whole sphere fits the tighter of the vertical and horizontal FOV.
    /// A sphere of radius R at distance d subtends `asin(R/d)`; solving
    /// `asin(R/d) <= halfMin` gives `d >= R/sin(halfMin)`. Horizontal FOV
    /// derives from vertical through the aspect ratio — in portrait the
    /// horizontal is always the binding constraint.
    static func requiredDistance(radius: Float,
                                 verticalFieldOfView: Float,
                                 aspect: Float) -> Float {
        // A not-yet-laid-out view feeds aspect 0 or NaN (0/0 geometry) —
        // either would propagate straight into the camera's transform,
        // and a NaN transform never recovers. Fall back to square.
        let safeAspect = (aspect.isFinite && aspect > 0) ? aspect : 1
        let halfV = verticalFieldOfView * .pi / 360
        let halfH = atan(tan(halfV) * safeAspect)
        let halfMin = min(halfV, halfH)
        return radius / sin(halfMin)
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

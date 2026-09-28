import simd
import Testing
@testable import DiceLab

/// The camera-fit math is pure geometry — pin it so a bad framing change
/// shows up here instead of as a subtle device regression.
struct CameraFitTests {

    @Test func boundingBoxSinglePoint() {
        let box = CameraFit.boundingBox(of: [SIMD3<Float>(1, 2, 3)],
                                        padding: 0.5)
        #expect(box.center == SIMD3<Float>(1, 2, 3))
        #expect(box.extents == SIMD2<Float>(0.5, 0.5))
    }

    @Test func boundingBoxLinearPair() {
        // A spread along one axis only pays for it on that axis — the
        // point of the rewrite: the old sphere charged the same radius
        // for the perpendicular axis too.
        let box = CameraFit.boundingBox(
            of: [SIMD3<Float>(-2, 0, 0), SIMD3<Float>(2, 0, 0)],
            padding: 1)
        #expect(box.center == .zero)
        #expect(box.extents == SIMD2<Float>(3, 1))
    }

    @Test func boundingBoxEmpty() {
        let box = CameraFit.boundingBox(of: [], padding: 2)
        #expect(box.extents == SIMD2<Float>(2, 2))
    }

    @Test func requiredDistanceSquareViewport() {
        // 60° vertical FOV, aspect 1 → both half-angles 30°; an extent of
        // 1 on either axis needs d = 1/tan(30°) ≈ 1.732.
        let d = CameraFit.requiredDistance(xExtent: 1, zExtent: 1,
                                           verticalFieldOfView: 60,
                                           aspect: 1)
        #expect(abs(d - 1 / tan(.pi / 6)) < 0.001)
    }

    @Test func requiredDistancePaysOnlyTheBindingAxis() {
        // Tall cluster (z) vs wide cluster (x), square viewport — both
        // halve the same FOV, so symmetric answers. But a *line* of dice
        // is not the diagonal worst case the sphere priced: 5×1 needs
        // ~8.7, not r=√26/sin(30°) ≈ 10.2.
        let wide = CameraFit.requiredDistance(xExtent: 5, zExtent: 1,
                                              verticalFieldOfView: 60,
                                              aspect: 1)
        #expect(abs(wide - 5 / tan(.pi / 6)) < 0.01)
        #expect(wide < 0.9 * (sqrt(26 as Float) / sin(.pi / 6)))
        let tall = CameraFit.requiredDistance(xExtent: 1, zExtent: 5,
                                              verticalFieldOfView: 60,
                                              aspect: 1)
        #expect(abs(tall - 5 / tan(.pi / 6)) < 0.01)
    }

    @Test func requiredDistancePortraitBindsHorizontally() {
        // Aspect 0.5 shrinks the horizontal half-angle to
        // atan(tan30°·0.5) ≈ 16.1° → the same x extent needs ~3.5× the
        // square-viewport distance. The vertical axis is untouched.
        let d = CameraFit.requiredDistance(xExtent: 1, zExtent: 0,
                                           verticalFieldOfView: 60,
                                           aspect: 0.5)
        let expected: Float = 1 / (tan(.pi / 6) * 0.5)
        #expect(abs(d - expected) < 0.001)
        #expect(d > 2) // strictly farther than the square-viewport answer
    }

    @Test func dampConvergesAndRespectsZeroDt() {
        let current = SIMD3<Float>(0, 0, 0)
        let target = SIMD3<Float>(10, 0, 0)
        #expect(CameraFit.damp(current, toward: target, rate: 5, dt: 0) == current)
        let stepped = CameraFit.damp(current, toward: target, rate: 5, dt: 0.1)
        #expect(stepped.x > 0 && stepped.x < 10)
        // rate·dt = 0.5 → remaining fraction e^-0.5 ≈ 0.607
        #expect(abs(stepped.x - 10 * (1 - exp(-0.5))) < 0.001)
    }

    @Test func quatDampIdenticalQuatsStaysFinite() {
        // The M9b NaN: simd_slerp(q, q, t) divides by sin(θ)=0 → NaN
        // orientation → blank frame, permanently. The guard must return
        // the target instead.
        let q = simd_quaternion(-Float.pi / 2, SIMD3<Float>(1, 0, 0))
        let damped = CameraFit.damp(q, toward: q, rate: 5, dt: 0.016)
        #expect(damped.vector.w.isFinite && damped.vector.x.isFinite
                && damped.vector.y.isFinite && damped.vector.z.isFinite)
    }

    @Test func quatDampNaNInputSnapsToTarget() {
        let nan = simd_quatf(ix: .nan, iy: 0, iz: 0, r: 1)
        let target = simd_quaternion(-Float.pi / 2, SIMD3<Float>(1, 0, 0))
        let damped = CameraFit.damp(nan, toward: target, rate: 5, dt: 0.016)
        #expect(damped.vector.x.isFinite)
    }

    @Test func requiredDistanceBadAspectFallsBack() {
        // A 0×0 geometry callback feeds NaN; the fallback keeps the
        // camera transform finite.
        let d = CameraFit.requiredDistance(xExtent: 1, zExtent: 1,
                                           verticalFieldOfView: 60,
                                           aspect: .nan)
        #expect(d.isFinite && d > 0)
    }
}

import simd
import Testing
@testable import DiceLab

/// The camera-fit math is pure geometry — pin it so a bad framing change
/// shows up here instead of as a subtle device regression.
struct CameraFitTests {

    @Test func boundingSphereSinglePoint() {
        let sphere = CameraFit.boundingSphere(of: [SIMD3<Float>(1, 2, 3)],
                                              padding: 0.5)
        #expect(sphere.center == SIMD3<Float>(1, 2, 3))
        #expect(sphere.radius == 0.5)
    }

    @Test func boundingSphereSymmetricPair() {
        let sphere = CameraFit.boundingSphere(
            of: [SIMD3<Float>(-2, 0, 0), SIMD3<Float>(2, 0, 0)],
            padding: 1)
        #expect(sphere.center == .zero)
        #expect(sphere.radius == 3)
    }

    @Test func boundingSphereEmpty() {
        let sphere = CameraFit.boundingSphere(of: [], padding: 2)
        #expect(sphere.radius == 2)
    }

    @Test func requiredDistanceSquareViewport() {
        // 60° vertical FOV, aspect 1 → half-min is 30°; a unit sphere
        // needs d = 1/sin(30°) = 2.
        let d = CameraFit.requiredDistance(radius: 1,
                                           verticalFieldOfView: 60,
                                           aspect: 1)
        #expect(abs(d - 2) < 0.001)
    }

    @Test func requiredDistancePortraitBindsHorizontally() {
        // Aspect 0.5 shrinks the horizontal half-angle to
        // atan(tan30°·0.5) ≈ 16.1° → the same sphere needs ~3.6× distance.
        let d = CameraFit.requiredDistance(radius: 1,
                                           verticalFieldOfView: 60,
                                           aspect: 0.5)
        let expected: Float = 1 / sin(atan(tan(.pi / 6) * 0.5))
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
        let d = CameraFit.requiredDistance(radius: 1,
                                           verticalFieldOfView: 60,
                                           aspect: .nan)
        #expect(d.isFinite && d > 0)
    }
}

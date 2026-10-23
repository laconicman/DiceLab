import simd
import Testing
@testable import DiceLab

/// The orbit's spherical math is pure geometry — pin it so a sign or
/// clamp regression shows up here instead of as a felt-level device bug.
struct CameraOrbitTests {

    private let pivot = SIMD3<Float>(1, -0.08, 2)

    @Test func poseRoundTrips() {
        let poses = [
            CameraOrbit.Pose(azimuth: -2.0, elevation: 0.3, radius: 0.4),
            CameraOrbit.Pose(azimuth: 0.3, elevation: 1.2, radius: 1.7),
            CameraOrbit.Pose(azimuth: 2.9, elevation: 0.6, radius: 25),
        ]
        for pose in poses {
            let p = CameraOrbit.position(of: pose, about: pivot)
            let back = CameraOrbit.pose(of: p, about: pivot)
            let roundTrip = CameraOrbit.position(of: back, about: pivot)
            #expect(simd_distance(roundTrip, p) < 1e-4)
            #expect(abs(back.azimuth - pose.azimuth) < 1e-4)
            #expect(abs(back.elevation - pose.elevation) < 1e-4)
            #expect(abs(back.radius - pose.radius) < 1e-4)
        }
    }

    @Test func poleIsFinite() {
        // Straight above the pivot azimuth is degenerate — it must read
        // 0, not NaN, so the fit's straight-down pose can start a drag.
        let p = pivot + SIMD3<Float>(0, 5, 0)
        let pose = CameraOrbit.pose(of: p, about: pivot)
        #expect(abs(pose.elevation - .pi / 2) < 1e-4)
        #expect(pose.azimuth == 0)
        #expect(pose.radius == 5)
        #expect(simd_distance(CameraOrbit.position(of: pose, about: pivot),
                              p) < 1e-4)
    }

    @Test func floorStopsTheDive() {
        let start = CameraOrbit.Pose(azimuth: 0, elevation: .pi / 3,
                                     radius: 1)
        let pose = CameraOrbit.orbit(start, azimuthDelta: 0,
                                   elevationDelta: -.pi, radiusScale: 1,
                                   radiusRange: 0.1...4)
        #expect(pose.elevation == CameraOrbit.elevationRange.lowerBound)
        let p = CameraOrbit.position(of: pose, about: pivot)
        #expect(abs(p.y - pivot.y - pose.radius * sin(10 * .pi / 180)) < 1e-4)
        #expect(p.y > pivot.y)
    }

    @Test func ceilingStopsShortOfThePole() {
        let start = CameraOrbit.Pose(azimuth: 0, elevation: .pi / 3,
                                     radius: 1)
        let pose = CameraOrbit.orbit(start, azimuthDelta: 0,
                                   elevationDelta: .pi, radiusScale: 1,
                                   radiusRange: 0.1...4)
        #expect(pose.elevation == CameraOrbit.elevationRange.upperBound)
        #expect(pose.elevation < .pi / 2)
    }

    @Test func azimuthTurnsAboutTheUpAxis() {
        // Pins the sign convention of `position(of:)`: azimuth +π/2 from
        // the pivot's +Z side lands the camera on +X.
        let start = CameraOrbit.Pose(azimuth: 0, elevation: 0.4, radius: 2)
        let pose = CameraOrbit.orbit(start, azimuthDelta: .pi / 2,
                                   elevationDelta: 0, radiusScale: 1,
                                   radiusRange: 0.1...4)
        let p = CameraOrbit.position(of: pose, about: pivot)
        #expect(p.x - pivot.x > 0)
        #expect(abs(p.z - pivot.z) < 1e-4)
        #expect(abs(p.y - pivot.y - 2 * sin(0.4)) < 1e-4)
    }

    @Test func radiusClamps() {
        let start = CameraOrbit.Pose(azimuth: 0, elevation: 0.4, radius: 0.5)
        let zoomOut = CameraOrbit.orbit(start, azimuthDelta: 0,
                                        elevationDelta: 0, radiusScale: 1000,
                                        radiusRange: 0.1...4)
        #expect(zoomOut.radius == 4)
        let zoomIn = CameraOrbit.orbit(start, azimuthDelta: 0,
                                       elevationDelta: 0, radiusScale: 0,
                                       radiusRange: 0.1...4)
        #expect(zoomIn.radius == 0.1)
    }

    @Test func limitsStayShortOfThePole() {
        // Pins the measured finding: at a 90 maximum SceneKit's own
        // constraint silently stops being enforced.
        #expect(CameraOrbit.floorDegrees < CameraOrbit.ceilingDegrees)
        #expect(CameraOrbit.ceilingDegrees < 90)
    }

    @Test func degenerateRadiusIsFinite() {
        let pose = CameraOrbit.pose(of: pivot, about: pivot)
        #expect(pose.azimuth.isFinite && pose.elevation.isFinite
                && pose.radius.isFinite)
    }
}

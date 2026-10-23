import Foundation
import simd

/// The orbit math behind the camera floor (M11): a spherical camera pose
/// about a pivot plus the elevation band both engines honor. Engine-free
/// like `CameraFit` — both engines drive `Pose` from their own
/// `DragGesture`/`MagnifyGesture`, because neither stock camera control
/// survived device verification: SceneKit's `SCNCameraController` limits
/// are bypassed by SwiftUI `SceneView`'s real-finger gesture path, and
/// RealityKit's `.orbit` has no limit and keeps a hidden angle any clamp
/// fights (both measured on PavP).
enum CameraOrbit {
    /// Lowest elevation above the pivot's horizontal plane the orbit may
    /// reach, in degrees — the felt is never seen from below.
    static let floorDegrees: Float = 10
    /// Highest elevation, deliberately short of straight down: a turntable's
    /// basis degenerates at the pole — SceneKit's constraint silently stops
    /// being enforced at a 90 maximum (measured), and `look(at:)` has no up
    /// vector there. Only the fit parks the camera at 90°, and it writes the
    /// orientation directly.
    static let ceilingDegrees: Float = 89
    static var elevationRange: ClosedRange<Float> {
        (floorDegrees * .pi / 180)...(ceilingDegrees * .pi / 180)
    }

    /// Camera position relative to a pivot in spherical terms: azimuth about
    /// +Y (0 puts the camera on the pivot's +Z side), elevation above the
    /// horizontal plane, both radians; radius in the engine's units.
    struct Pose: Equatable {
        var azimuth: Float
        var elevation: Float
        var radius: Float
    }

    /// Spherical decomposition of a world position about a pivot. A camera
    /// straight above the pivot reads azimuth 0, not NaN — so the first
    /// drag can start from the fit's straight-down pose.
    static func pose(of position: SIMD3<Float>,
                     about pivot: SIMD3<Float>) -> Pose {
        let v = position - pivot
        let r = simd_length(v)
        guard r > 0 else {
            return Pose(azimuth: 0, elevation: .pi / 2, radius: 0)
        }
        return Pose(
            azimuth: atan2(v.x, v.z),
            elevation: asin(min(1, max(-1, v.y / r))),
            radius: r)
    }

    /// The inverse of `pose(of:about:)`.
    static func position(of pose: Pose,
                         about pivot: SIMD3<Float>) -> SIMD3<Float> {
        pivot + pose.radius * SIMD3<Float>(
            cos(pose.elevation) * sin(pose.azimuth),
            sin(pose.elevation),
            cos(pose.elevation) * cos(pose.azimuth))
    }

    /// One gesture step: rotate by the deltas (radians), scale the radius,
    /// clamp elevation to `elevationRange` and radius to `radiusRange`.
    static func orbit(_ pose: Pose, azimuthDelta: Float,
                      elevationDelta: Float, radiusScale: Float,
                      radiusRange: ClosedRange<Float>) -> Pose {
        Pose(
            azimuth: pose.azimuth + azimuthDelta,
            elevation: min(elevationRange.upperBound,
                           max(elevationRange.lowerBound,
                               pose.elevation + elevationDelta)),
            radius: min(radiusRange.upperBound,
                        max(radiusRange.lowerBound,
                            pose.radius * radiusScale)))
    }
}

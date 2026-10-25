import simd
import Testing
@testable import DiceLab

/// Pins the mirror transform the RealityKit felt reflection builds its dice
/// copies from: scale × conjugated rotation × reflected position must put
/// every vertex exactly where a mirror across the plane would.
struct MirrorPoseTests {
    private static let planeY: Float = -0.08

    /// The die's corners and face centers — the points whose mirror image
    /// decides what the copy shows.
    private static let vertices: [SIMD3<Float>] = [
        [1, 1, 1], [-1, 1, 1], [1, -1, 1], [1, 1, -1], [-1, -1, -1],
        [1, 0, 0], [0, 1, 0], [0, 0, 1], [0.3, -0.7, 0.2],
    ]

    private static let orientations: [simd_quatf] = [
        simd_quatf(angle: 0, axis: [0, 1, 0]),
        simd_quatf(angle: .pi / 2, axis: [1, 0, 0]),
        simd_quatf(angle: .pi / 3, axis: simd_normalize([0, 1, 0])),
        simd_quatf(angle: 2.1, axis: simd_normalize([0.3, -0.8, 0.5])),
        simd_quatf(angle: -0.7, axis: simd_normalize([-1, 0.2, 0.9])),
    ]

    /// For every orientation and vertex: the copy's world point equals the
    /// original's world point reflected across the plane.
    @Test("mirrored copy lands every vertex on the reflected world point")
    func mirrorsEveryVertex() {
        let position = SIMD3<Float>(0.03, 0.015, -0.02)
        for orientation in Self.orientations {
            let mirrored = MirrorPose.orientation(orientation)
            let mirroredPosition = MirrorPose.position(position, planeY: Self.planeY)
            for vertex in Self.vertices {
                let world = orientation.act(vertex) + position
                let expected = SIMD3<Float>(world.x, 2 * Self.planeY - world.y, world.z)
                let copy = mirrored.act(MirrorPose.scale * vertex) + mirroredPosition
                #expect(simd_distance(copy, expected) < 1e-5,
                        "orientation \(orientation) vertex \(vertex)")
            }
        }
    }

    /// Reflecting twice is the identity — a sanity check on the
    /// conjugation: the imaginary flips undo themselves.
    @Test("mirroring is an involution")
    func involution() {
        for orientation in Self.orientations {
            let twice = MirrorPose.orientation(MirrorPose.orientation(orientation))
            #expect(simd_distance(twice.vector, orientation.vector) < 1e-6)
        }
        let p = SIMD3<Float>(0.1, 0.2, 0.3)
        let twice = MirrorPose.position(MirrorPose.position(p, planeY: Self.planeY),
                                        planeY: Self.planeY)
        #expect(simd_distance(twice, p) < 1e-6)
    }

    /// The copy's rotation stays a unit quaternion — negative scale is the
    /// only improper part, so `Transform` decomposes nothing.
    @Test("mirrored orientation stays normalized")
    func normalized() {
        for orientation in Self.orientations {
            #expect(abs(MirrorPose.orientation(orientation).length - 1) < 1e-6)
        }
    }
}

import RealityKit
import simd
import Testing
@testable import DiceLab

/// RealityKit-side pins. `MeshResource` is `@MainActor`, so the suite is —
/// the same isolation the controller declares.
@MainActor
struct RealityTableTests {
    /// A `splitFaces` box gets one part per face; `materials(shape:)`
    /// maps each
    /// part's material index to a face value via the part centroid. This test
    /// is the M7 counterpart of `materialAxesCoverAllFaces`: all six faces
    /// must be covered, exactly once.
    @Test("the split-faces box's material slots cover all six faces")
    func materialSlotsCoverAllFaces() {
        let mesh = RealityTableController.dieMesh
        var seen: [Int: Int] = [:] // materialIndex → face value
        for model in mesh.contents.models {
            for part in model.parts {
                let direction = RealityTableController.centroid(of: part)
                seen[part.materialIndex] =
                    DieFace.value(facing: direction, shape: .d6)
            }
        }
        #expect(seen.count == 6)
        #expect(Set(seen.values) == Set(1...6))
    }

    /// The `.perFace` d20 mesh must produce twenty parts with twenty
    /// distinct material indices — the whole premise of the per-face
    /// assignment — and those parts must cover every value 1…20.
    @Test("the d20 mesh's twenty material slots cover all faces")
    func d20MaterialSlotsCoverAllFaces() {
        let mesh = RealityTableController.d20Mesh
        var seen: [Int: Int] = [:]
        for model in mesh.contents.models {
            for part in model.parts {
                let direction = RealityTableController.centroid(of: part)
                seen[part.materialIndex] =
                    DieFace.value(facing: direction, shape: .d20)
            }
        }
        #expect(seen.count == 20)
        #expect(Set(seen.values) == Set(1...20))
    }

    /// Every material slot ends up with a real face texture — count alone
    /// would pass on the blank pre-allocated fallback.
    @Test("materials fills every slot the mesh expects, all textured",
          arguments: [DieShape.d6, .d20])
    func materialsFillEverySlot(shape: DieShape) {
        let materials = RealityTableController.materials(
            shape: shape, appearance: Appearance.ivory.die)
        #expect(materials.count
                == RealityTableController.dieMesh(for: shape).expectedMaterialCount)
        #expect(materials.allSatisfy {
            ($0 as? PhysicallyBasedMaterial)?.baseColor.texture != nil
        })
    }

    /// Meter-scale mirror of `SpawnPositionTests`: centered, symmetric, and
    /// inside the ±0.10 bounds with half a die (0.015) to spare.
    @Test("N dice → N positions, centered inside the meter-scale bounds")
    func spawnPositions() {
        #expect(RealityTableController.spawnPositions(count: 0, shape: .d6).isEmpty)
        for count in 1...6 {
            let positions = RealityTableController.spawnPositions(count: count, shape: .d6)
            #expect(positions.count == count)
            #expect(positions[0].x == -positions[count - 1].x)
            #expect(positions.allSatisfy { abs($0.x) <= 0.085 })
            #expect(positions.allSatisfy { $0.z == 0 })
        }
    }

    /// The mirror of the SceneKit zig-zag, in meters: every pair of d20
    /// spawn slots clears 2 × 0.02 = 0.04, and each die keeps
    /// |x| ≤ 0.10 − 0.017 of wall clearance.
    @Test("d20 rows zig-zag past the die's own diameter")
    func d20ZigZag() {
        for count in 1...6 {
            let positions = RealityTableController.spawnPositions(count: count, shape: .d20)
            for (i, a) in positions.enumerated() {
                #expect(abs(a.x) <= 0.083)
                for b in positions[(i + 1)...] {
                    #expect(simd_distance(a, b) >= 0.04)
                }
            }
        }
    }
}

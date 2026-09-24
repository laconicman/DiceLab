import RealityKit
import simd
import Testing
@testable import DiceLab

/// RealityKit-side pins. `MeshResource` is `@MainActor`, so the suite is —
/// the same isolation the controller declares.
@MainActor
struct RealityTableTests {
    /// A `splitFaces` box gets one part per face; `materials(appearance:)`
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
                let axis = RealityTableController.dominantAxis(
                    of: RealityTableController.centroid(of: part))
                seen[part.materialIndex] = DieFaceTexture.value(on: axis)
            }
        }
        #expect(seen.count == 6)
        #expect(Set(seen.values) == Set(1...6))
    }

    /// Every material slot ends up with a real pip texture — count alone
    /// would pass on the blank pre-allocated fallback.
    @Test("materials fills every slot the mesh expects, all textured")
    func materialsFillEverySlot() {
        let materials = RealityTableController.materials(appearance: Appearance.ivory.die)
        #expect(materials.count == RealityTableController.dieMesh.expectedMaterialCount)
        #expect(materials.allSatisfy {
            ($0 as? PhysicallyBasedMaterial)?.baseColor.texture != nil
        })
    }

    /// Meter-scale mirror of `SpawnPositionTests`: centered, symmetric, and
    /// inside the ±0.10 bounds with half a die (0.015) to spare.
    @Test("N dice → N positions, centered inside the meter-scale bounds")
    func spawnPositions() {
        #expect(RealityTableController.spawnPositions(count: 0).isEmpty)
        for count in 1...6 {
            let positions = RealityTableController.spawnPositions(count: count)
            #expect(positions.count == count)
            #expect(positions[0].x == -positions[count - 1].x)
            #expect(positions.allSatisfy { abs($0.x) <= 0.085 })
        }
    }
}

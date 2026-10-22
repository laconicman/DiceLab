import SceneKit
import simd
import Testing
@testable import DiceLab

/// `DieFace.up` is the whole point of reading orientation — a die at rest must
/// report the face pointing world +Y. Every axis rotation pins one mapping.
struct UpFaceTests {
    private func rotated(_ angle: Float, axis: SIMD3<Float>) -> simd_quatf {
        simd_quatf(angle: angle, axis: simd_normalize(axis))
    }

    @Test("identity orientation shows the +Y face: 2")
    func identity() {
        #expect(DieFace.up(of: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), shape: .d6) == 2)
    }

    @Test("half turn about X puts the bottom face up: 5")
    func flippedAboutX() {
        #expect(DieFace.up(of: rotated(.pi, axis: SIMD3(1, 0, 0)), shape: .d6) == 5)
    }

    @Test("quarter turn about Z puts +X up: 1")
    func quarterAboutZ() {
        #expect(DieFace.up(of: rotated(.pi / 2, axis: SIMD3(0, 0, 1)), shape: .d6) == 1)
        #expect(DieFace.up(of: rotated(-.pi / 2, axis: SIMD3(0, 0, 1)), shape: .d6) == 6)
    }

    @Test("quarter turn about X puts −Z / +Z up: 4 / 3")
    func quarterAboutX() {
        #expect(DieFace.up(of: rotated(.pi / 2, axis: SIMD3(1, 0, 0)), shape: .d6) == 4)
        #expect(DieFace.up(of: rotated(-.pi / 2, axis: SIMD3(1, 0, 0)), shape: .d6) == 3)
    }

    @Test("a small tilt does not change the up face")
    func smallTilt() {
        #expect(DieFace.up(of: rotated(.pi / 8, axis: SIMD3(1, 0, 1)), shape: .d6) == 2)
    }

    /// Both tables keep opposite faces adjacent — a stride-2 walk checks
    /// the pairing convention for whatever the shape's face count is.
    @Test("opposite faces sum to faceCount + 1 for every antipodal pair",
          arguments: DieShape.allCases)
    func oppositesSum(shape: DieShape) {
        let axes = DieFace.axes(for: shape)
        for i in stride(from: 0, to: axes.count, by: 2) {
            #expect(axes[i].value + axes[i + 1].value == shape.faceCount + 1)
        }
    }

    /// The d6-side of `value(facing:)` — the direct resolver the material
    /// mappers now use. ±axes reproduce the old `dominantAxis` results,
    /// and an oblique direction resolves to its dominant axis.
    @Test("value(facing:) resolves cube axes and obliques to their faces")
    func cubeFacing() {
        #expect(DieFace.value(facing: SIMD3(1, 0, 0), shape: .d6) == 1)
        #expect(DieFace.value(facing: SIMD3(-1, 0, 0), shape: .d6) == 6)
        #expect(DieFace.value(facing: SIMD3(0, 1, 0), shape: .d6) == 2)
        #expect(DieFace.value(facing: SIMD3(0, -1, 0), shape: .d6) == 5)
        #expect(DieFace.value(facing: SIMD3(0, 0, 1), shape: .d6) == 3)
        #expect(DieFace.value(facing: SIMD3(0, 0, -1), shape: .d6) == 4)
        #expect(DieFace.value(facing: simd_normalize(SIMD3(2, 1, 0.5)),
                            shape: .d6) == 1)
        #expect(DieFace.value(facing: simd_normalize(SIMD3(0.2, -1, 0.9)),
                            shape: .d6) == 5)
    }

    /// Rotating each face normal onto world +Y must report that face's
    /// value — the rotation exercises the whole `up` path rather than
    /// asserting the table against itself.
    @Test("every d20 face reports its value when rotated to point up")
    func d20RotationPath() {
        for axis in DieFace.axes(for: .d20) {
            let upright = simd_quatf(from: axis.normal, to: SIMD3(0, 1, 0))
            #expect(DieFace.up(of: upright, shape: .d20) == axis.value)
        }
    }

    /// A π/16 tilt about a perpendicular axis stays inside the face's
    /// normal Voronoi cell — the reported value must not change. `cross`
    /// with +X is safe here: no d20 normal is axis-aligned.
    @Test("a small tilt does not change the d20 up face")
    func d20SmallTilt() {
        for axis in DieFace.axes(for: .d20) {
            let upright = simd_quatf(from: axis.normal, to: SIMD3(0, 1, 0))
            let tiltAxis = simd_normalize(
                simd_cross(axis.normal, SIMD3(1, 0, 0)))
            let tilt = rotated(.pi / 16, axis: tiltAxis)
            #expect(DieFace.up(of: tilt * upright, shape: .d20) == axis.value)
        }
    }
}

struct RollResultTests {
    @Test("total sums the faces")
    func total() {
        #expect(RollResult(faces: [2, 5, 3]).total == 10)
        #expect(RollResult(faces: []).total == 0)
    }

    @Test("equality is by outcome — id distinguishes events, not values")
    func equalityByOutcome() {
        #expect(RollResult(faces: [2, 5]) == RollResult(faces: [2, 5]))
        #expect(RollResult(faces: [2, 5]) != RollResult(faces: [1, 5]))
        // Distinct identities survive equal faces — history rows don't merge.
        #expect(RollResult(faces: [3]).id != RollResult(faces: [3]).id)
    }
}

struct PhysicsCategoryTests {
    @Test("die and table are distinct bits, and union combines them")
    func masks() {
        #expect(PhysicsCategory.die != .table)
        #expect(PhysicsCategory.die.union(.table).contains(.die))
        #expect(PhysicsCategory.die.union(.table).contains(.table))
        #expect(PhysicsCategory.die.isDisjoint(with: .table))
    }
}

/// `DiceTableController` is `@MainActor` — so the suite is, same rule as
/// RealityTableTests.
@MainActor
struct SpawnPositionTests {
    @Test("N dice → N positions, centered on the table midline")
    func countsAndSymmetry() {
        #expect(DiceTableController.spawnPositions(count: 0).isEmpty)
        for count in 1...6 {
            let positions = DiceTableController.spawnPositions(count: count)
            #expect(positions.count == count)
            let xs = positions.map(\.x)
            #expect(xs.first! == -xs.last!) // symmetric spread
            // Die is 3 units wide; a centered die needs |x| ≤ 10 − 1.5.
            #expect(xs.allSatisfy { abs($0) <= 8.5 })
        }
    }
}

struct HapticsTests {
    @Test("impulse normalizes into 0…1 and clamps at both ends")
    func intensityClamp() {
        #expect(HapticsController.normalizedIntensity(for: 0) == 0)
        #expect(HapticsController.normalizedIntensity(for: -5) == 0)
        #expect(HapticsController.normalizedIntensity(for: 100) == 1)
        #expect(HapticsController.normalizedIntensity(for: 12.5) == 0.5)
    }
}

/// The pip textures are drawn per material slot of `SCNBox`, but Apple never
/// documents which slot is which face — `materialAxes` derives it from
/// vertex data. These tests pin the derivation and the layout data itself.
struct DieFaceTextureTests {
    @Test("face value N draws exactly N pips, all inside the 3×3 grid")
    func pipCounts() {
        for value in 1...6 {
            let pips = DieFaceTexture.pipLayout(for: value)
            #expect(pips.count == value)
            #expect(pips.allSatisfy { (0...2).contains($0.x) && (0...2).contains($0.y) })
        }
        #expect(DieFaceTexture.pipLayout(for: 0).isEmpty)
        #expect(DieFaceTexture.pipLayout(for: 7).isEmpty)
    }

    @Test("an SCNBox's six material slots cover all six axes exactly once")
    func materialAxesCoverAllFaces() {
        let box = SCNBox(width: 3, height: 3, length: 3, chamferRadius: 0.1)
        let axes = DieFaceTexture.materialAxes(of: box)
        #expect(axes.count == 6)
        #expect(Set(axes) == Set(DieFace.axes(for: .d6).map(\.normal)))
    }

    @Test("every derived material slot resolves to a face value 1…6")
    func everySlotHasAValue() {
        let box = SCNBox(width: 3, height: 3, length: 3, chamferRadius: 0.1)
        let values = DieFaceTexture.materialAxes(of: box).map(DieFaceTexture.value(on:))
        #expect(Set(values) == Set(1...6))
    }
}

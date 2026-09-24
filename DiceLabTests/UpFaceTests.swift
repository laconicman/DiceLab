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
        #expect(DieFace.up(of: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)) == 2)
    }

    @Test("half turn about X puts the bottom face up: 5")
    func flippedAboutX() {
        #expect(DieFace.up(of: rotated(.pi, axis: SIMD3(1, 0, 0))) == 5)
    }

    @Test("quarter turn about Z puts +X up: 1")
    func quarterAboutZ() {
        #expect(DieFace.up(of: rotated(.pi / 2, axis: SIMD3(0, 0, 1))) == 1)
        #expect(DieFace.up(of: rotated(-.pi / 2, axis: SIMD3(0, 0, 1))) == 6)
    }

    @Test("quarter turn about X puts −Z / +Z up: 4 / 3")
    func quarterAboutX() {
        #expect(DieFace.up(of: rotated(.pi / 2, axis: SIMD3(1, 0, 0))) == 4)
        #expect(DieFace.up(of: rotated(-.pi / 2, axis: SIMD3(1, 0, 0))) == 3)
    }

    @Test("a small tilt does not change the up face")
    func smallTilt() {
        #expect(DieFace.up(of: rotated(.pi / 8, axis: SIMD3(1, 0, 1))) == 2)
    }

    @Test("opposite faces sum to 7 for every axis pair")
    func oppositesSumToSeven() {
        for i in stride(from: 0, to: DieFace.axes.count, by: 2) {
            #expect(DieFace.axes[i].value + DieFace.axes[i + 1].value == 7)
        }
    }
}

struct RollResultTests {
    @Test("total sums the faces")
    func total() {
        #expect(RollResult(faces: [2, 5, 3]).total == 10)
        #expect(RollResult(faces: []).total == 0)
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

struct HapticsTests {
    @Test("impulse normalizes into 0…1 and clamps at both ends")
    func intensityClamp() {
        #expect(HapticsController.normalizedIntensity(for: 0) == 0)
        #expect(HapticsController.normalizedIntensity(for: -5) == 0)
        #expect(HapticsController.normalizedIntensity(for: 100) == 1)
        #expect(HapticsController.normalizedIntensity(for: HapticsController.maxImpulse / 2) == 0.5)
    }
}

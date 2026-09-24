import Foundation

/// Named bits for SceneKit's physics masks.
///
/// Three `SCNPhysicsBody` masks read these categories: `categoryBitMask` says
/// what a body *is*, `collisionBitMask` says what it *bounces off*,
/// `contactTestBitMask` says which intersections *report contacts* to the
/// delegate. `SCNNode.categoryBitMask` is a different mask entirely — it gates
/// rendering (lights, cameras, techniques) and never touches physics.
struct PhysicsCategory: OptionSet {
    let rawValue: Int

    static let die   = PhysicsCategory(rawValue: 1 << 0)
    static let table = PhysicsCategory(rawValue: 1 << 1)
}

import Foundation

/// A color the model layer can persist — plain 0…1 RGBA, no framework types.
/// Bridging to `UIColor`/`SwiftUI.Color` lives with the consumers that need it
/// (`DieFaceTexture`, the editor), keeping `Model/` engine-free.
struct CodableColor: Codable, Equatable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1
}

/// Everything about how a die looks that isn't its shape — face ink and
/// finish. All three finish channels exist on both engines
/// (`SCNMaterial.roughness`/`metalness`/`clearCoat` ↔
/// `PhysicallyBasedMaterial`'s scalar parameters), so one slider set
/// translates faithfully.
struct DieAppearance: Codable, Equatable, Hashable {
    var faceColor: CodableColor
    var pipColor: CodableColor
    var roughness: Double = 0.35
    var metalness: Double = 0
    var clearcoat: Double = 0
}

/// The playing surface: a flat color, or a user photo kept on disk by
/// `FeltImageStore` — the model records only *that* an image is wanted,
/// not the image itself (UserDefaults is no place for textures).
struct FeltAppearance: Codable, Equatable, Hashable {
    var color: CodableColor
    var usesImage = false
}

/// Named lighting rigs. Each engine maps a preset onto its own light rig —
/// intensities and shadow dials differ, the *mood* is the shared contract:
/// studio = the tuned default, soft = broad flat fill, dramatic = hard key,
/// deep shadows.
enum LightingPreset: String, Codable, CaseIterable, Hashable {
    case studio, soft, dramatic
}

/// The complete look of the table: dice, felt, lighting.
struct Appearance: Codable, Equatable, Hashable {
    var die: DieAppearance
    var felt: FeltAppearance
    var lighting: LightingPreset
}

/// What the appearance editor selects: a named preset, or `custom` carrying
/// its own full `Appearance`. The legacy `Theme.custom(die:surface:)` idea —
/// picking a preset fills the fields, editing any field flips to custom.
enum Theme: Codable, Equatable, Hashable {
    case ivory, onyx, custom(Appearance)

    var appearance: Appearance {
        switch self {
        case .ivory: .ivory
        case .onyx: .onyx
        case .custom(let appearance): appearance
        }
    }
}

extension Appearance {
    /// The casino classic — white die, black pips, green felt.
    static let ivory = Appearance(
        die: DieAppearance(faceColor: CodableColor(red: 0.96, green: 0.96, blue: 0.96),
                           pipColor: CodableColor(red: 0, green: 0, blue: 0)),
        felt: FeltAppearance(color: CodableColor(red: 0.05, green: 0.30, blue: 0.15)),
        lighting: .studio)

    /// Inverted — black die, white pips, same felt.
    static let onyx = Appearance(
        die: DieAppearance(faceColor: CodableColor(red: 0.10, green: 0.10, blue: 0.10),
                           pipColor: CodableColor(red: 1, green: 1, blue: 1)),
        felt: FeltAppearance(color: CodableColor(red: 0.05, green: 0.30, blue: 0.15)),
        lighting: .studio)
}

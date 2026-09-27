import Foundation

/// A color the model layer can persist — plain 0…1 RGBA, no framework types.
/// Bridging to `UIColor`/`SwiftUI.Color` lives with the consumers that need it
/// (`DieFaceTexture`, the editor), keeping `Model/` engine-free.
struct CodableColor: Codable, Equatable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    /// Component-wise multiply, clamped to 0…1 — emission packing divides
    /// by the peak intensity, so a stored intensity above the supported
    /// ceiling still lands inside texture range instead of wrapping.
    func scaled(by factor: Double) -> CodableColor {
        func clamp(_ c: Double) -> Double { min(max(c * factor, 0), 1) }
        return CodableColor(red: clamp(red), green: clamp(green),
                            blue: clamp(blue), alpha: alpha)
    }
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
    var emission = EmissionAppearance()

    init(faceColor: CodableColor, pipColor: CodableColor,
         roughness: Double = 0.35, metalness: Double = 0,
         clearcoat: Double = 0, emission: EmissionAppearance = EmissionAppearance()) {
        self.faceColor = faceColor
        self.pipColor = pipColor
        self.roughness = roughness
        self.metalness = metalness
        self.clearcoat = clearcoat
        self.emission = emission
    }

    /// All fields decode leniently — the synthesized decoder would bounce
    /// any payload missing a key (e.g. an M8–M9c theme has no `emission`)
    /// back to the default theme, silently discarding the user's edits.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        faceColor = try container.decode(CodableColor.self, forKey: .faceColor)
        pipColor = try container.decode(CodableColor.self, forKey: .pipColor)
        roughness = try container.decodeIfPresent(Double.self, forKey: .roughness) ?? 0.35
        metalness = try container.decodeIfPresent(Double.self, forKey: .metalness) ?? 0
        clearcoat = try container.decodeIfPresent(Double.self, forKey: .clearcoat) ?? 0
        emission = try container.decodeIfPresent(EmissionAppearance.self, forKey: .emission)
            ?? EmissionAppearance()
    }
}

/// Per-part self-illumination: face and pips emit independently, so both
/// "glowing pips on a dark die" and "glowing body, dark pips" are
/// expressible. Intensity 0 means the part doesn't emit.
struct EmissionAppearance: Codable, Equatable, Hashable {
    var faceColor = CodableColor(red: 1, green: 1, blue: 1)
    var faceIntensity = 0.0
    var pipColor = CodableColor(red: 1, green: 1, blue: 1)
    var pipIntensity = 0.0

    /// The editor's slider ceiling and the material clamp. Beyond ~2 the
    /// emission washes out the face texture on both engines.
    static let maxIntensity = 2.0

    /// Both engine materials pair ONE scalar intensity with ONE texture,
    /// but the model has two intensities (face, pips). The split: texture
    /// pixels carry each part's tint × intensity ÷ peak (the *ratio*), and
    /// `intensity` carries the clamped peak (the *magnitude*). Ratios
    /// survive the flattening, and 8-bit texture pixels keep full color
    /// resolution at low intensities instead of banding.
    var peak: Double { max(faceIntensity, pipIntensity) }

    /// The scalar the material carries — the peak, capped at the range
    /// the engines can express.
    var intensity: Double { min(peak, Self.maxIntensity) }

    /// Texture-space emission for the face area: tint scaled by its share
    /// of the peak, so `texture × intensity` reproduces faceIntensity.
    var packedFace: CodableColor {
        faceColor.scaled(by: peak > 0 ? faceIntensity / peak : 0)
    }

    /// Same packing for the pips.
    var packedPips: CodableColor {
        pipColor.scaled(by: peak > 0 ? pipIntensity / peak : 0)
    }

    init(faceColor: CodableColor = CodableColor(red: 1, green: 1, blue: 1),
         faceIntensity: Double = 0,
         pipColor: CodableColor = CodableColor(red: 1, green: 1, blue: 1),
         pipIntensity: Double = 0) {
        self.faceColor = faceColor
        self.faceIntensity = faceIntensity
        self.pipColor = pipColor
        self.pipIntensity = pipIntensity
    }

    /// Lenient like the rest of the model — partial or missing emission
    /// payloads decode to "no emission" instead of failing the theme.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        faceColor = try container.decodeIfPresent(CodableColor.self, forKey: .faceColor)
            ?? CodableColor(red: 1, green: 1, blue: 1)
        faceIntensity = try container.decodeIfPresent(Double.self, forKey: .faceIntensity) ?? 0
        pipColor = try container.decodeIfPresent(CodableColor.self, forKey: .pipColor)
            ?? CodableColor(red: 1, green: 1, blue: 1)
        pipIntensity = try container.decodeIfPresent(Double.self, forKey: .pipIntensity) ?? 0
    }
}

/// The playing surface: a flat color, or a user photo kept on disk by
/// `UserImageStore` — the model records only *that* an image is wanted,
/// not the image itself (UserDefaults is no place for textures).
struct FeltAppearance: Codable, Equatable, Hashable {
    var color: CodableColor
    var usesImage = false
    /// Bumped after every photo save. `theme`'s change guard skips
    /// re-materialing on equal values — same `usesImage` with a *new* file
    /// must still differ, or a replaced photo would never reach the felt.
    var revision = 0

    init(color: CodableColor, usesImage: Bool = false, revision: Int = 0) {
        self.color = color
        self.usesImage = usesImage
        self.revision = revision
    }

    /// `revision`/`usesImage` decode leniently — payloads written before a
    /// field existed shouldn't bounce a stored theme back to the default.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        color = try container.decode(CodableColor.self, forKey: .color)
        usesImage = try container.decodeIfPresent(Bool.self, forKey: .usesImage) ?? false
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
    }
}

/// Named lighting rigs. Each engine maps a preset onto its own light rig —
/// intensities and shadow dials differ, the *mood* is the shared contract:
/// studio = the tuned default, soft = broad flat fill, dramatic = hard key,
/// deep shadows.
enum LightingPreset: String, Codable, CaseIterable, Hashable {
    case studio, soft, dramatic
}

/// What surrounds the table. Presets are procedural gradients drawn at
/// runtime (no assets — same rule as die faces); on engines with IBL the
/// backdrop image doubles as the environment light source, so the choice
/// is lighting, not just wallpaper. `none` keeps the flat-black look.
enum BackdropPreset: String, Codable, CaseIterable, Hashable {
    case none, graphite, dusk, ember
}

/// The backdrop channel: a procedural preset, or a user photo kept on disk
/// by `UserImageStore` — the model records only *that* an image is wanted,
/// same as `FeltAppearance`.
struct BackdropAppearance: Codable, Equatable, Hashable {
    var preset: BackdropPreset = .none
    var usesImage = false
    /// Same `revision` trick as the felt: a replaced photo differs only by
    /// this counter, or `theme`'s equality guard would swallow the update.
    var revision = 0

    init(preset: BackdropPreset = .none, usesImage: Bool = false, revision: Int = 0) {
        self.preset = preset
        self.usesImage = usesImage
        self.revision = revision
    }

    /// Lenient decode — payloads written before a field existed shouldn't
    /// bounce a stored theme back to the default.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preset = try container.decodeIfPresent(BackdropPreset.self, forKey: .preset) ?? .none
        usesImage = try container.decodeIfPresent(Bool.self, forKey: .usesImage) ?? false
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
    }
}

/// The complete look of the table: dice, felt, lighting, backdrop.
struct Appearance: Codable, Equatable, Hashable {
    var die: DieAppearance
    var felt: FeltAppearance
    var lighting: LightingPreset
    var backdrop = BackdropAppearance()

    init(die: DieAppearance, felt: FeltAppearance, lighting: LightingPreset,
         backdrop: BackdropAppearance = BackdropAppearance()) {
        self.die = die
        self.felt = felt
        self.lighting = lighting
        self.backdrop = backdrop
    }

    /// `backdrop` decodes leniently — M8–M9c themes predate it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        die = try container.decode(DieAppearance.self, forKey: .die)
        felt = try container.decode(FeltAppearance.self, forKey: .felt)
        lighting = try container.decode(LightingPreset.self, forKey: .lighting)
        backdrop = try container.decodeIfPresent(BackdropAppearance.self, forKey: .backdrop)
            ?? BackdropAppearance()
    }
}

/// What the appearance editor selects: a named preset, or `custom` carrying
/// its own full `Appearance`. The legacy `Theme.custom(die:surface:)` idea —
/// picking a preset fills the fields, editing any field flips to custom.
enum Theme: Codable, Equatable, Hashable {
    case ivory, onyx, custom(Appearance)

    /// Payload-free case identity — picker tags must be stable while a
    /// custom theme's fields mutate under it. Binding a `Picker` to the
    /// full `Theme` means every slider tick produces a selection that
    /// equals no tag (SwiftUI logs "invalid selection" per tick).
    enum Kind: String, CaseIterable {
        case ivory, onyx, custom
    }

    var kind: Kind {
        switch self {
        case .ivory: .ivory
        case .onyx: .onyx
        case .custom: .custom
        }
    }

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

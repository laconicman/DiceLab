import Foundation
import Testing
import UIKit
@testable import DiceLab

/// Model-layer pins for the appearance system: persistence round-trips,
/// the M6 skin→theme migration, and per-appearance texture keying.
struct AppearanceTests {

    /// A custom theme must survive the UserDefaults JSON round-trip intact —
    /// preset name *and* every edited field.
    @Test("Theme Codable round-trips, including .custom payload")
    func themeRoundTrip() throws {
        let custom = Appearance(
            die: DieAppearance(faceColor: CodableColor(red: 0.2, green: 0.3, blue: 0.8),
                               pipColor: CodableColor(red: 1, green: 0.9, blue: 0.1),
                               roughness: 0.8, metalness: 0.4, clearcoat: 0.6),
            felt: FeltAppearance(color: CodableColor(red: 0.1, green: 0.1, blue: 0.4),
                                 usesImage: true),
            lighting: .dramatic)
        let theme = Theme.custom(custom)

        let defaults = try #require(UserDefaults(suiteName: "AppearanceTests.roundTrip"))
        defaults.removePersistentDomain(forName: "AppearanceTests.roundTrip")
        TableSettings.persist(theme, defaults: defaults)

        #expect(TableSettings.storedTheme(defaults: defaults) == theme)
    }

    /// M6 stored a raw skin name; the model got richer. The old key still
    /// resolves — a user who picked onyx keeps onyx.
    @Test("legacy settings.skin migrates to the matching theme preset")
    func skinMigration() throws {
        let defaults = try #require(UserDefaults(suiteName: "AppearanceTests.migration"))
        defaults.removePersistentDomain(forName: "AppearanceTests.migration")
        defaults.set("onyx", forKey: TableSettings.skin)
        #expect(TableSettings.storedTheme(defaults: defaults) == .onyx)
        defaults.set("ivory", forKey: TableSettings.skin)
        #expect(TableSettings.storedTheme(defaults: defaults) == .ivory)
        // No key at all → the default preset.
        defaults.removeObject(forKey: TableSettings.skin)
        #expect(TableSettings.storedTheme(defaults: defaults) == .ivory)
    }

    /// A stored theme wins over the legacy key — migration happens once,
    /// not on every read.
    @Test("stored theme takes precedence over the legacy skin key")
    func storedThemeWins() throws {
        let defaults = try #require(UserDefaults(suiteName: "AppearanceTests.precedence"))
        defaults.removePersistentDomain(forName: "AppearanceTests.precedence")
        defaults.set("onyx", forKey: TableSettings.skin)
        TableSettings.persist(.ivory, defaults: defaults)
        #expect(TableSettings.storedTheme(defaults: defaults) == .ivory)
    }

    /// Different die appearances must draw different face images — the cache
    /// is keyed by the value, so editing a custom theme can't leak preset art.
    @Test("face images differ between appearances")
    func imagesAreAppearanceKeyed() {
        var dark = Appearance.ivory.die
        dark.faceColor = CodableColor(red: 0.1, green: 0.1, blue: 0.1)
        dark.pipColor = CodableColor(red: 1, green: 1, blue: 1)
        let ivoryFaces = DieFaceTexture.images(for: Appearance.ivory.die)
        let darkFaces = DieFaceTexture.images(for: dark)
        #expect(ivoryFaces.count == 6 && darkFaces.count == 6)
        #expect(ivoryFaces[0].pngData() != darkFaces[0].pngData())
    }

    /// Payloads written before `revision` existed must still decode — a
    /// stored custom theme that bounced to default would silently lose the
    /// user's look on upgrade. M9d added `emission` and `backdrop`; the same
    /// M8-era payload must still decode, with the new channels defaulted.
    @Test("felt payloads without revision still decode")
    func legacyFeltPayload() throws {
        let json = #"{"custom":{"_0":{"die":{"faceColor":{"red":1,"green":1,"blue":1,"alpha":1},"pipColor":{"red":0,"green":0,"blue":0,"alpha":1},"roughness":0.35,"metalness":0,"clearcoat":0},"felt":{"color":{"red":0.05,"green":0.3,"blue":0.15,"alpha":1},"usesImage":true},"lighting":"studio"}}}"#
        let theme = try JSONDecoder().decode(Theme.self, from: Data(json.utf8))
        guard case .custom(let appearance) = theme else {
            Issue.record("expected .custom, got \(theme)")
            return
        }
        #expect(appearance.felt.usesImage && appearance.felt.revision == 0)
        // Fields that didn't exist when the payload was written land on
        // their defaults, not on a decode failure.
        #expect(appearance.die.emission == EmissionAppearance())
        #expect(appearance.backdrop == BackdropAppearance())
    }

    /// Presets resolve to real appearances — the editor's pickers bind
    /// through `theme.appearance`, so a preset that returned nothing would
    /// blank the table.
    @Test("presets resolve to appearances")
    func presetsResolve() {
        #expect(Theme.ivory.appearance == .ivory)
        #expect(Theme.onyx.appearance == .onyx)
        #expect(LightingPreset.allCases.count == 3)
    }

    /// The speech format is user-facing prose — pin it so a refactor can't
    /// quietly turn "3 plus 3 plus 1 equals 7" into "sum 7".
    @Test("speech text reads faces and total")
    func speechText() {
        #expect(SpeechController.text(for: RollResult(faces: [3, 3, 1]))
                == "3 plus 3 plus 1 equals 7")
        #expect(SpeechController.text(for: RollResult(faces: [6])) == "6 equals 6")
    }

    /// The wire format is synthesized enum Codable — `{"custom":{"_0":…}}`.
    /// Pin the literal shape: a hand-written payload (e.g. injected via
    /// `defaults write -data` for QA) must decode through the real type.
    @Test("hand-written custom theme JSON decodes")
    func literalCustomJSON() throws {
        let json = #"{"custom":{"_0":{"die":{"faceColor":{"red":0.1,"green":0.5,"blue":0.9,"alpha":1},"pipColor":{"red":1,"green":0.9,"blue":0,"alpha":1},"roughness":0.15,"metalness":0.9,"clearcoat":0.8},"felt":{"color":{"red":0.35,"green":0.05,"blue":0.08,"alpha":1},"usesImage":false},"lighting":"dramatic"}}}"#
        let theme = try JSONDecoder().decode(Theme.self, from: Data(json.utf8))
        guard case .custom(let appearance) = theme else {
            Issue.record("expected .custom, got \(theme)")
            return
        }
        #expect(appearance.die.metalness == 0.9)
        #expect(appearance.lighting == .dramatic)
    }

    /// Emission packing is the contract the material code depends on:
    /// texture pixels carry each part's share of the peak, the material
    /// scalar carries the clamped peak. Face-vs-pip ratios must survive.
    @Test("emission packs ratio into texture and magnitude into intensity")
    func emissionPacking() {
        // Equal intensities: packed colors are the raw tints.
        var emission = EmissionAppearance(
            faceColor: CodableColor(red: 0.5, green: 0.5, blue: 0.5), faceIntensity: 1,
            pipColor: CodableColor(red: 1, green: 1, blue: 1), pipIntensity: 1)
        #expect(emission.peak == 1 && emission.intensity == 1)
        #expect(emission.packedPips == CodableColor(red: 1, green: 1, blue: 1))

        // Glowing pips on a dark body: face ratio 0 → packed black.
        emission = EmissionAppearance(faceIntensity: 0, pipIntensity: 1.5)
        #expect(emission.packedFace == CodableColor(red: 0, green: 0, blue: 0))
        #expect(emission.packedPips == CodableColor(red: 1, green: 1, blue: 1))
        #expect(emission.intensity == 1.5)

        // Asymmetric: face at 4× the pips — the texture holds 1:0.25 while
        // the scalar clamps at maxIntensity, so 4:1 still lands on screen.
        emission = EmissionAppearance(
            faceColor: CodableColor(red: 1, green: 1, blue: 1), faceIntensity: 4,
            pipColor: CodableColor(red: 1, green: 1, blue: 1), pipIntensity: 1)
        #expect(emission.packedFace == CodableColor(red: 1, green: 1, blue: 1))
        #expect(emission.packedPips == CodableColor(red: 0.25, green: 0.25, blue: 0.25))
        #expect(emission.intensity == EmissionAppearance.maxIntensity)

        // Nothing emits → peak and intensity are 0, no texture needed.
        #expect(EmissionAppearance().peak == 0)
        #expect(EmissionAppearance().intensity == 0)
    }

    /// `peak == 0` must not mint emission textures at all — the material
    /// leaves the channel off; above zero, the emission image is drawn and
    /// is *not* the diffuse image.
    @Test("emission images exist only when something emits")
    func emissionImagesGate() {
        #expect(DieFaceTexture.emissionImages(for: Appearance.ivory.die) == nil)
        var die = Appearance.ivory.die
        die.emission.pipIntensity = 1
        let emission = DieFaceTexture.emissionImages(for: die)
        #expect(emission?.count == 6)
        #expect(emission?[0].pngData()
                != DieFaceTexture.images(for: die)[0].pngData())
    }

    /// The editor gates every material control on `theme.kind == .custom` —
    /// pin the mapping it reads: presets report their own kind, custom
    /// reports custom regardless of payload.
    @Test("theme kind drives the editor's material-control visibility")
    func themeKindGate() {
        #expect(Theme.ivory.kind == .ivory)
        #expect(Theme.onyx.kind == .onyx)
        #expect(Theme.custom(.ivory).kind == .custom)
    }

    /// `.none` produces no image (flat-black look preserved), presets draw
    /// a 2:1 equirect, and a picked-but-missing photo falls back to the
    /// preset rather than a broken texture.
    @Test("backdrop resolves to preset gradients, photo, or nil")
    func backdropResolve() {
        #expect(BackdropImage.resolve(BackdropAppearance()) == nil)
        let graphite = BackdropImage.image(for: .graphite)
        #expect(graphite != nil)
        if let graphite {
            #expect(graphite.size.width / graphite.size.height == 2)
        }
        // `usesImage` with no file on disk must degrade to the preset —
        // same contract as the felt's missing-photo fallback. Clear first:
        // an earlier run's leftover file would flip the fallback.
        UserImageStore.backdrop.clear()
        let missing = BackdropAppearance(preset: .dusk, usesImage: true)
        #expect(BackdropImage.resolve(missing)?.pngData()
                == BackdropImage.image(for: .dusk)?.pngData())
    }

    /// The user photo stores round-trip through Documents — save → load →
    /// clear — and a cleared store must actually report empty.
    @Test("user image stores round-trip and clear")
    func imageStoreRoundTrip() {
        for store in [UserImageStore.felt, UserImageStore.backdrop] {
            store.clear()
            #expect(store.load() == nil)
            let pixel = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { ctx in
                UIColor.red.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            }
            store.save(pixel)
            #expect(store.load() != nil)
            store.clear()
            #expect(store.load() == nil)
        }
    }
}

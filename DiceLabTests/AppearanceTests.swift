import Foundation
import Testing
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

    /// Presets resolve to real appearances — the editor's pickers bind
    /// through `theme.appearance`, so a preset that returned nothing would
    /// blank the table.
    @Test("presets resolve to appearances")
    func presetsResolve() {
        #expect(Theme.ivory.appearance == .ivory)
        #expect(Theme.onyx.appearance == .onyx)
        #expect(LightingPreset.allCases.count == 3)
    }
}

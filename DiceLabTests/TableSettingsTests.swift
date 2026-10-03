import Foundation
import Testing
@testable import DiceLab

/// Pins for the shared `settings.*` contract — every user choice the table
/// owns must round-trip through UserDefaults, because the other engine reads
/// the same slots when it activates.
struct TableSettingsTests {

    /// Fresh isolated suite per test — a shared domain would leak between
    /// tests and, worse, into the app's real defaults.
    private func freshDefaults(_ name: String) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// The unset default is 1 die; a stored value wins and clamps to 1…6.
    @Test("die count defaults to 1, round-trips, and clamps")
    func dieCount() throws {
        let defaults = try freshDefaults("TableSettingsTests.dieCount")
        #expect(TableSettings.storedDieCount(defaults: defaults) == 1)
        defaults.set(4, forKey: TableSettings.dieCount)
        #expect(TableSettings.storedDieCount(defaults: defaults) == 4)
        defaults.set(99, forKey: TableSettings.dieCount)
        #expect(TableSettings.storedDieCount(defaults: defaults) == 6)
    }

    /// Sound predates its own key — a legacy muted-haptics user must not
    /// gain sound on upgrade. Pinned twice because the migration is silent.
    @Test("sound falls back to the legacy haptics key")
    func soundMigration() throws {
        let defaults = try freshDefaults("TableSettingsTests.sound")
        #expect(TableSettings.storedSound(defaults: defaults))
        defaults.set(false, forKey: TableSettings.haptics)
        #expect(!TableSettings.storedSound(defaults: defaults))
        // An explicit sound choice beats the legacy value it inherited from.
        defaults.set(true, forKey: TableSettings.sound)
        #expect(TableSettings.storedSound(defaults: defaults))
    }

    /// Volume is newer than the toggles: an absent key must read as full
    /// loudness (the baseline testers wanted louder), and stored values
    /// clamp to the slider's 0…1 like the other dials.
    @Test("sound volume defaults to full, round-trips, and clamps")
    func soundVolume() throws {
        let defaults = try freshDefaults("TableSettingsTests.soundVolume")
        #expect(TableSettings.storedSoundVolume(defaults: defaults) == 1)
        defaults.set(0.3, forKey: TableSettings.soundVolume)
        #expect(TableSettings.storedSoundVolume(defaults: defaults) == 0.3)
        defaults.set(-4, forKey: TableSettings.soundVolume)
        #expect(TableSettings.storedSoundVolume(defaults: defaults) == 0)
        defaults.set(99, forKey: TableSettings.soundVolume)
        #expect(TableSettings.storedSoundVolume(defaults: defaults) == 1)
    }
}

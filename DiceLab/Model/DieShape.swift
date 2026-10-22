import Foundation

/// Which polyhedron the dice on a table take. One shape per table, like
/// `dieCount` — not a per-die choice: a mixed-shape throw would make the
/// reported totals incomparable.
enum DieShape: String, CaseIterable, Codable, Identifiable {
    case d6, d20

    var id: Self { self }

    var faceCount: Int {
        switch self {
        case .d6: 6
        case .d20: 20
        }
    }

    /// Display name — `String(localized:)` is Foundation, so Model/ stays
    /// engine-free; a `rawValue.capitalized` label couldn't reach the
    /// string catalog at all. The names stay "d6"/"d20" in English.
    var title: String {
        switch self {
        case .d6: String(localized: "dieShape.d6",
                         defaultValue: "d6",
                         comment: "Die shape picker option — six-sided cube")
        case .d20: String(localized: "dieShape.d20",
                          defaultValue: "d20",
                          comment: "Die shape picker option — twenty-sided icosahedron")
        }
    }
}

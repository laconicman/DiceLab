import Foundation

/// The outcome of a settled throw: one face value per die, in spawn order.
/// `Identifiable` so roll history can key rows by event, not by value —
/// two rolls can land identical faces and still be distinct entries.
struct RollResult: Equatable, Identifiable {
    let id = UUID()
    let faces: [Int]

    var total: Int { faces.reduce(0, +) }
}

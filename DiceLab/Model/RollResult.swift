/// The outcome of a settled throw: one face value per die, in spawn order.
struct RollResult: Equatable {
    let faces: [Int]

    var total: Int { faces.reduce(0, +) }
}

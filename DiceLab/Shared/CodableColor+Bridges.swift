import SwiftUI
import UIKit

/// `CodableColor` ↔ framework colors. The model type stays pure data
/// (`Model/` carries no framework types); every consumer that needs a real
/// color gets it here, in one place.
extension CodableColor {
    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    init(_ uiColor: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
    }

    init(_ color: Color) {
        self.init(UIColor(color))
    }
}

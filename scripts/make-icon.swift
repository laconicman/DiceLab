// Generates a 1024x1024 App Store icon: SF Symbol die on a colored background.
// Run: swift scripts/make-icon.swift
import AppKit

let side = 1024
let out = "DiceLab/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: side,
    pixelsHigh: side,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else { fatalError("no bitmap rep") }
rep.size = NSSize(width: side, height: side) // draw at 1x: 1 point == 1 pixel

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

NSColor(calibratedRed: 0.13, green: 0.45, blue: 0.27, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: side, height: side).fill()

if let die = NSImage(systemSymbolName: "die.face.5", accessibilityDescription: nil) {
    die.isTemplate = true
    NSColor.white.set()
    let face: CGFloat = 640
    let origin = (CGFloat(side) - face) / 2
    die.draw(in: NSRect(x: origin, y: origin, width: face, height: face))
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("could not render icon")
}
try png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")

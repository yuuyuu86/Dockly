// Renders Resources/AppIcon.icns. Run with:  swift Tools/MakeIcon.swift
import AppKit

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setAllowsAntialiasing(true)

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let squircle = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.055, dy: size * 0.055),
                                xRadius: size * 0.225, yRadius: size * 0.225)
    ctx.saveGState()
    squircle.addClip()
    let bg = NSGradient(colors: [
        NSColor(srgbRed: 0.36, green: 0.55, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.56, green: 0.35, blue: 0.95, alpha: 1),
    ])!
    bg.draw(in: rect, angle: -68)

    // A soft highlight across the top, the way glass catches light.
    let gloss = NSGradient(colors: [NSColor(white: 1, alpha: 0.28),
                                    NSColor(white: 1, alpha: 0)])!
    gloss.draw(in: CGRect(x: 0, y: size * 0.55, width: size, height: size * 0.45), angle: -90)
    ctx.restoreGState()

    // The dock plate.
    let plate = CGRect(x: size * 0.155, y: size * 0.30,
                       width: size * 0.69, height: size * 0.235)
    let platePath = NSBezierPath(roundedRect: plate,
                                 xRadius: plate.height * 0.36, yRadius: plate.height * 0.36)
    NSColor(white: 1, alpha: 0.22).setFill()
    platePath.fill()
    NSColor(white: 1, alpha: 0.45).setStroke()
    platePath.lineWidth = max(1, size * 0.006)
    platePath.stroke()

    // Three tiles and one wider "widget" tile.
    let tileSide = plate.height * 0.52
    let gap = tileSide * 0.42
    var x = plate.minX + gap
    let y = plate.midY - tileSide / 2
    for _ in 0..<3 {
        let t = NSBezierPath(roundedRect: CGRect(x: x, y: y, width: tileSide, height: tileSide),
                             xRadius: tileSide * 0.3, yRadius: tileSide * 0.3)
        NSColor(white: 1, alpha: 0.95).setFill()
        t.fill()
        x += tileSide + gap
    }
    let widget = CGRect(x: x, y: y, width: plate.maxX - gap - x, height: tileSide)
    if widget.width > 0 {
        let w = NSBezierPath(roundedRect: widget,
                             xRadius: tileSide * 0.3, yRadius: tileSide * 0.3)
        NSColor(white: 1, alpha: 0.55).setFill()
        w.fill()
    }

    image.unlockFocus()
    return image
}

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? fm.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(Int, String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"),
    (512, "icon_256x256@2x"), (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]

for (px, name) in variants {
    let img = drawIcon(size: CGFloat(px))
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try? png.write(to: iconset.appendingPathComponent("\(name).png"))
}
print("wrote \(iconset.path)")

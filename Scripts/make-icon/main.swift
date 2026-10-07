// Renders the app icon from the locomotive sprite. Called by Scripts/bundle.sh.
// Usage: make-icon <output.iconset directory>

import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func render(size: Int) -> CGImage {
    let s = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .none

    // macOS icon shape: rounded square with a little breathing room.
    let inset = s * 0.08
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = CGPath(roundedRect: rect, cornerWidth: s * 0.19, cornerHeight: s * 0.19, transform: nil)
    ctx.addPath(path)
    ctx.clip()
    let colors = [NSColor(hex: 0xF4E7C3).cgColor, NSColor(hex: 0xE8CF8E).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

    // Track across the lower third.
    let tile = Pixel.image(Sprite.trackTile)
    let px = rect.width / 34   // pixel size: the loco is 26 px wide, leave margins
    let trackY = rect.minY + rect.height * 0.26
    var x = rect.minX - px * 8
    while x < rect.maxX {
        ctx.draw(tile, in: CGRect(x: x, y: trackY, width: px * 8, height: px * 3))
        x += px * 8
    }

    // The locomotive, centred.
    let loco = Pixel.image(Sprite.locomotive)
    let w = px * 26, h = px * 16
    ctx.draw(loco, in: CGRect(x: rect.midX - w / 2, y: trackY + px * 3, width: w, height: h))
    return ctx.makeImage()!
}

for (name, size) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    let rep = NSBitmapImageRep(cgImage: render(size: size))
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: outDir.appendingPathComponent("icon_\(name).png"))
}
print("icon rendered to \(outDir.path)")

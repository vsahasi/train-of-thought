// Renders the README hero: an animated SVG of the train, built from the same
// sprites the app uses. No scripts in the SVG, only CSS animations, so it
// plays inside GitHub's <img> sandbox.
//
// Usage: make-hero <output.svg>

import AppKit
import TrainCore

let out = URL(fileURLWithPath: CommandLine.arguments[1])

// Scene in sprite pixels.
let cars: [Car] = (0..<6).map { Rules.car(at: $0) }
let gap = 2
let carW = Sprite.boxcar[0].count
let locoW = Sprite.locomotive[0].count
let trainW = locoW + cars.count * (carW + gap)
let margin = 10
let sceneW = trainW + margin * 2
let spriteH = 16
let trackH = 3
let smokeRoom = 12
let sceneH = smokeRoom + spriteH + trackH + 1

func hex(_ c: NSColor) -> String {
    let c = c.usingColorSpace(.sRGB)!
    return String(format: "#%02X%02X%02X", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
}

var svg = ""
func emit(_ s: String) { svg += s + "\n" }

/// Rects for one sprite, horizontal runs merged, hubs emitted separately
/// with a class per wheel frame so CSS can walk the highlight around.
func sprite(_ rows: [String], palette: Pixel.Palette, x ox: Int, y oy: Int, id: String) -> String {
    var body = ""
    let frames = Sprite.wheelFrames(rows)
    let base = frames[0].map { Array($0) }
    for (r, row) in base.enumerated() {
        var c = 0
        while c < row.count {
            let ch = row[c]
            if ch == "." || ch == "Q" { c += 1; continue }
            var run = 1
            while c + run < row.count, row[c + run] == ch { run += 1 }
            if let color = palette.colors[ch] {
                body += "<rect x=\"\(ox + c)\" y=\"\(oy + r)\" width=\"\(run)\" height=\"1\" fill=\"\(hex(color))\"/>"
            }
            c += run
        }
    }
    // Hubs: one rect per frame per wheel, toggled by CSS.
    for (f, frame) in frames.enumerated() {
        for (r, row) in frame.enumerated() {
            for (c, ch) in row.enumerated() where ch == "Q" {
                body += "<rect class=\"h\(f)\" x=\"\(ox + c)\" y=\"\(oy + r)\" width=\"1\" height=\"1\" fill=\"\(hex(palette.colors["Q"]!))\"/>"
            }
        }
    }
    return "<g id=\"\(id)\">\(body)</g>"
}

emit("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(sceneW) \(sceneH)\" width=\"\(sceneW * 4)\" height=\"\(sceneH * 4)\" shape-rendering=\"crispEdges\" role=\"img\" aria-label=\"A pixel-art train with six cars chugging along a track\">")
emit("""
<style>
  .h0,.h1,.h2,.h3 { animation: hub 0.28s steps(1) infinite; }
  .h1 { animation-delay: -0.07s; } .h2 { animation-delay: -0.14s; } .h3 { animation-delay: -0.21s; }
  @keyframes hub { 0% { opacity: 1 } 25% { opacity: 0 } 100% { opacity: 0 } }
  .car { animation: bob 0.56s steps(1) infinite; }
  @keyframes bob { 0% { transform: translateY(0) } 25% { transform: translateY(-1px) } 50% { transform: translateY(0) } 100% { transform: translateY(0) } }
  .track { animation: scroll 0.22s linear infinite; }
  @keyframes scroll { from { transform: translateX(0) } to { transform: translateX(-8px) } }
  .puff { animation: puff 1.8s ease-out infinite; opacity: 0; }
  @keyframes puff {
    0% { transform: translate(0,0) scale(1); opacity: .9 }
    100% { transform: translate(-9px,-12px) scale(2.6); opacity: 0 }
  }
</style>
""")

// Track, two tiles wider than the scene so the scroll loop is seamless.
let tileW = Sprite.trackTile[0].count
let trackY = smokeRoom + spriteH
var track = ""
let tiles = sceneW / tileW + 3
for i in 0..<tiles {
    for (r, row) in Sprite.trackTile.enumerated() {
        var c = 0
        let chars = Array(row)
        while c < chars.count {
            let ch = chars[c]
            if ch == "." { c += 1; continue }
            var run = 1
            while c + run < chars.count, chars[c + run] == ch { run += 1 }
            track += "<rect x=\"\(i * tileW + c)\" y=\"\(trackY + r)\" width=\"\(run)\" height=\"1\" fill=\"\(hex(Pixel.Palette.standard.colors[ch]!))\"/>"
            c += run
        }
    }
}
emit("<g class=\"track\">\(track)</g>")

// Cars trail the locomotive, which leads on the right.
let locoX = sceneW - margin - locoW
emit(sprite(Sprite.locomotive, palette: .standard, x: locoX, y: smokeRoom, id: "loco"))
for (i, car) in cars.enumerated() {
    let x = locoX - (i + 1) * (carW + gap)
    let g = sprite(Sprite.car(car.kind), palette: car.isGold ? .gold : .standard, x: x, y: smokeRoom, id: "car\(i)")
    emit("<g class=\"car\" style=\"animation-delay:-\(Double(i + 1) * 0.09)s\">\(g)</g>")
    // Coupler.
    emit("<rect x=\"\(x + carW)\" y=\"\(smokeRoom + 11)\" width=\"\(gap)\" height=\"1\" fill=\"\(hex(Pixel.Palette.standard.colors["K"]!))\"/>")
}

// Smoke from the chimney (columns 18–22, row 2 of the locomotive).
let chimneyX = locoX + 20
let chimneyY = smokeRoom + 1
for i in 0..<4 {
    emit("<g class=\"puff\" style=\"animation-delay:-\(Double(i) * 0.45)s; transform-origin: \(chimneyX)px \(chimneyY)px\"><rect x=\"\(chimneyX - 1)\" y=\"\(chimneyY - 1)\" width=\"2\" height=\"2\" fill=\"#B8B8BE\" opacity=\"0.9\"/></g>")
}

emit("</svg>")
try! svg.write(to: out, atomically: true, encoding: .utf8)
print("hero written to \(out.path) (\(svg.utf8.count) bytes)")

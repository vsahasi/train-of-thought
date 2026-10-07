import AppKit

/// Turns ASCII art into crisp pixel-art images.
///
/// One character per pixel, `.` is transparent, every other character looks
/// up a colour in `Palette`. Images are rendered at 1 px per pixel; layers
/// scale them up with `.nearest` filtering so the pixels stay square.
enum Pixel {
    /// How many points one sprite pixel covers on screen. Set from the
    /// size preference; the scene relayouts when it changes.
    static var scale: CGFloat = 2

    struct Palette {
        var colors: [Character: NSColor]

        static let standard = Palette(colors: [
            "K": NSColor(hex: 0x1C1B22),  // outline
            "R": NSColor(hex: 0xD9413A),  // red
            "r": NSColor(hex: 0xA12A26),
            "Y": NSColor(hex: 0xF5C543),  // gold
            "y": NSColor(hex: 0xC9962A),
            "B": NSColor(hex: 0x4A7BE0),  // blue
            "b": NSColor(hex: 0x2F55A8),
            "G": NSColor(hex: 0x4CAF5A),  // green
            "g": NSColor(hex: 0x2F7D3A),
            "O": NSColor(hex: 0xEC8B3C),  // orange
            "o": NSColor(hex: 0xB8622A),
            "P": NSColor(hex: 0xB07CD8),  // purple
            "p": NSColor(hex: 0x7A4FA3),
            "N": NSColor(hex: 0x8C6239),  // wood
            "n": NSColor(hex: 0x5E4024),
            "W": NSColor(hex: 0xF7F4EC),  // white
            "L": NSColor(hex: 0xBFE3F5),  // window glass
            "S": NSColor(hex: 0x9AA0AA),  // steel
            "s": NSColor(hex: 0x5A606B),
            "D": NSColor(hex: 0x3A3D45),  // wheel
            "Q": NSColor(hex: 0xB8BEC8),  // wheel hub highlight
            "T": NSColor(hex: 0x7A7F8A),  // rail
            "t": NSColor(hex: 0x4F3A28),  // sleeper
        ])

        /// A palette where body colours are swapped for gold.
        static let gold: Palette = {
            var p = standard
            for (from, to): (Character, Character) in [("B", "Y"), ("b", "y"), ("G", "Y"), ("g", "y"), ("O", "Y"), ("o", "y"), ("P", "Y"), ("p", "y"), ("N", "Y"), ("n", "y")] {
                p.colors[from] = standard.colors[to]
            }
            return p
        }()
    }

    private static var cache: [String: CGImage] = [:]

    /// Renders rows of characters to an image. Rows must be equal length.
    static func image(_ rows: [String], palette: Palette = .standard, cacheKey: String? = nil) -> CGImage {
        if let key = cacheKey, let hit = cache[key] { return hit }
        let height = rows.count
        let width = rows.first?.count ?? 0
        precondition(rows.allSatisfy { $0.count == width }, "sprite rows must be the same width")

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.interpolationQuality = .none
        for (rowIndex, row) in rows.enumerated() {
            // Core Graphics draws from the bottom; row 0 is the top of the art.
            let y = height - 1 - rowIndex
            for (x, ch) in row.enumerated() where ch != "." {
                guard let color = palette.colors[ch] else { continue }
                context.setFillColor(color.cgColor)
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        let image = context.makeImage()!
        if let key = cacheKey { cache[key] = image }
        return image
    }

    static func size(of rows: [String]) -> CGSize {
        CGSize(width: CGFloat(rows.first?.count ?? 0) * scale, height: CGFloat(rows.count) * scale)
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

import AppKit
import TrainCore

/// The pixel art. One character per pixel, `.` is transparent, letters are
/// colours from `Pixel.Palette`. Every sprite is 16 rows tall and stands
/// on the bottom row; the track runs underneath.
///
/// Wheels are drawn as a `KDDK` row over a `KDQK` row. `Q` is the hub
/// highlight; `Sprite.wheelFrames` walks it around the wheel to animate.
///
/// To add a car: draw it here, add a case to `CarKind` in TrainCore, and
/// map it in `Sprite.car(_:)`. That is the whole contribution.
enum Sprite {
    static let locomotive: [String] = [
        "..........................",
        "..........................",
        ".KKKKKKK.........KKKKKKK..",
        "KRRRRRRRK........KsSSSsK..",
        "KRKLLLKRK.........KSSSK...",
        "KRKLLLKRK...KKK...KSSSK...",
        "KRKLLLKRKKKKKRRRKKKKKKKK..",
        "KRRRRRRRKRRRRRRRRRRRRRRRKK",
        "KRRRRRRRKRRRRRRRRRRRRRRRYK",
        "KRRRRRRRKRRRRRRRRRRRRRRRYK",
        "KrrrrrrrKrrrrrrrrrrrrrrrKK",
        "KKKKKKKKKKKKKKKKKKKKKKKKKK",
        ".KSSSSSSSSSSSSSSSSSSSSSKKK",
        "..KDDK....KDDK....KDDK.KK.",
        "..KDQK....KDQK....KDQK..K.",
        "...KK......KK......KK.....",
    ]

    static let boxcar: [String] = [
        "....................",
        "....................",
        "....................",
        ".KKKKKKKKKKKKKKKKKK.",
        "KBBBBBBBBBBBBBBBBBBK",
        "KBBBBBBKBBBBKBBBBBBK",
        "KBBBBBBKBBBBKBBBBBBK",
        "KBBBBBBKBbbBKBBBBBBK",
        "KBBBBBBKBBBBKBBBBBBK",
        "KBBBBBBKBBBBKBBBBBBK",
        "KbbbbbbKbbbbKbbbbbbK",
        "KKKKKKKKKKKKKKKKKKKK",
        ".KSSSSSSSSSSSSSSSSK.",
        "..KDDK........KDDK..",
        "..KDQK........KDQK..",
        "...KK..........KK...",
    ]

    static let tanker: [String] = [
        "....................",
        "....................",
        "........KKKK........",
        "....KKKKOOOOKKKK....",
        "..KKOOOOOOOOOOOOKK..",
        ".KOOOWWOOOOOOOOOOOK.",
        "KOOOOWOOOOOOOOOOOOOK",
        "KOOOOOOOOOOOOOOOOOOK",
        "KOOOOOOOOOOOOOOOOOOK",
        ".KooooooooooooooooK.",
        "..KKooooooooooooKK..",
        "..K.KKKKKKKKKKKK.K..",
        ".KSSSSSSSSSSSSSSSSK.",
        "..KDDK........KDDK..",
        "..KDQK........KDQK..",
        "...KK..........KK...",
    ]

    static let hopper: [String] = [
        "....................",
        "....................",
        "....................",
        "KKKKKKKKKKKKKKKKKKKK",
        "KGGGGGGGGGGGGGGGGGGK",
        "KGGKGGGGKGGGGKGGGGGK",
        "KGGKGGGGKGGGGKGGGGGK",
        "KGGKGGGGKGGGGKGGGGGK",
        "KGGKGGGGKGGGGKGGGGGK",
        ".KggKggggKggggKgggK.",
        "..KgggggggggggggggK.",
        "...KKKKKKKKKKKKKKK..",
        ".KSSSSSSSSSSSSSSSSK.",
        "..KDDK........KDDK..",
        "..KDQK........KDQK..",
        "...KK..........KK...",
    ]

    static let passenger: [String] = [
        "....................",
        "....................",
        "..KKKKKKKKKKKKKKKK..",
        ".KPPPPPPPPPPPPPPPPK.",
        "KPPPPPPPPPPPPPPPPPPK",
        "KPKLLKPKLLKPKLLKPLPK",
        "KPKLLKPKLLKPKLLKPLPK",
        "KPKLLKPKLLKPKLLKPLPK",
        "KPKKKKPKKKKPKKKKPLPK",
        "KPPPPPPPPPPPPPPPPLPK",
        "KppppppppppppppppppK",
        "KKKKKKKKKKKKKKKKKKKK",
        ".KSSSSSSSSSSSSSSSSK.",
        "..KDDK........KDDK..",
        "..KDQK........KDQK..",
        "...KK..........KK...",
    ]

    static let flatbed: [String] = [
        "....................",
        "....................",
        "....................",
        "....................",
        "....................",
        "..KKKKKK............",
        "..KOOOOK....KKKKK...",
        "..KOKKOK....KNNNK...",
        "..KOOOOK....KNKNK...",
        "..KOKKOK....KNNNK...",
        "..KOOOOK....KnnnK...",
        "KKKKKKKKKKKKKKKKKKKK",
        ".KNNNNNNNNNNNNNNNNK.",
        "..KDDK........KDDK..",
        "..KDQK........KDQK..",
        "...KK..........KK...",
    ]

    /// A puff of smoke, tinted and scaled by the emitter.
    static let puff: [String] = [
        ".WW.",
        "WWWW",
        "WWWW",
        ".WW.",
    ]

    /// One tile of track: a rail with a sleeper under it. Tiles repeat.
    static let trackTile: [String] = [
        "TTTTTTTT",
        "..ttt...",
        "..ttt...",
    ]

    /// The bar between two cars.
    static let coupler: [String] = [
        "KK",
    ]

    static func car(_ kind: CarKind) -> [String] {
        switch kind {
        case .boxcar: return boxcar
        case .tanker: return tanker
        case .hopper: return hopper
        case .passenger: return passenger
        case .flatbed: return flatbed
        }
    }

    /// Four frames with the wheel hub walked clockwise: bottom-right,
    /// bottom-left, top-left, top-right. Clockwise is forwards for a
    /// train heading right.
    static func wheelFrames(_ rows: [String]) -> [[String]] {
        var grid = rows.map { Array($0) }
        var hubs: [(row: Int, col: Int)] = []
        for (r, row) in grid.enumerated() {
            for (c, ch) in row.enumerated() where ch == "Q" {
                hubs.append((r, c))
                grid[r][c] = "D"
            }
        }
        let offsets: [(Int, Int)] = [(0, 0), (0, -1), (-1, -1), (-1, 0)]
        return offsets.map { (dr, dc) in
            var frame = grid
            for hub in hubs {
                frame[hub.row + dr][hub.col + dc] = "Q"
            }
            return frame.map { String($0) }
        }
    }

    /// Images for every wheel frame of a sprite, cached.
    static func frames(_ rows: [String], gold: Bool, key: String) -> [CGImage] {
        wheelFrames(rows).enumerated().map { index, frame in
            Pixel.image(frame, palette: gold ? .gold : .standard, cacheKey: "\(key)-\(gold)-\(index)")
        }
    }
}

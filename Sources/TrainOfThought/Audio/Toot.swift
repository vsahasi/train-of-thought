import AppKit

/// Tiny 8-bit sounds, synthesized on first use so the repo ships no audio
/// files. Each one is a WAV in memory handed to `NSSound`.
final class Toot {
    enum Kind: String, CaseIterable {
        case couple
        case whistle
        case derail
        case nearMiss
    }

    private var sounds: [Kind: NSSound] = [:]
    private var chug: NSSound?
    private let sampleRate = 22_050.0

    /// A looping chuff-chuff while the train moves.
    func startChugging() {
        if chug == nil {
            let sound = NSSound(data: chugData())
            sound?.loops = true
            sound?.volume = 0.6
            chug = sound
        }
        if chug?.isPlaying != true {
            chug?.play()
        }
    }

    func stopChugging() {
        chug?.stop()
    }

    func play(_ kind: Kind) {
        let sound = sounds[kind] ?? make(kind)
        sounds[kind] = sound
        sound.stop()
        sound.play()
    }

    private func make(_ kind: Kind) -> NSSound {
        NSSound(data: data(for: kind)) ?? NSSound()
    }

    /// The chug loop as a WAV in memory.
    private func chugData() -> Data {
        wav(chugSamples())
    }

    private func chugSamples() -> [Float] {
        // Four chuffs per bar, the first two a little louder.
        render(duration: 0.72) { t, _ in
            let beat = t.truncatingRemainder(dividingBy: 0.18)
            let which = Int(t / 0.18)
            let accent = which % 2 == 0 ? 1.0 : 0.7
            let hiss = Double.random(in: -1...1) * exp(-beat * 28)
            let knock = sin(2 * .pi * 90 * beat) * exp(-beat * 45)
            return (hiss * 0.22 + knock * 0.3) * accent
        }
    }

    /// One sound as a WAV file in memory.
    private func data(for kind: Kind) -> Data {
        let samples: [Float]
        switch kind {
        case .couple:
            // A clack: a short burst of noise over a low thump.
            samples = render(duration: 0.09) { t, p in
                let thump = sin(2 * .pi * 110 * t) * exp(-t * 40)
                let noise = Double.random(in: -1...1) * exp(-t * 60) * 0.5
                return (thump + noise) * (1 - p) * 0.6
            }
        case .whistle:
            // Two-note steam whistle with a little vibrato.
            samples = render(duration: 0.42) { t, p in
                let vibrato = 1 + 0.01 * sin(2 * .pi * 6 * t)
                let a = square(2 * .pi * 523 * vibrato * t)
                let b = square(2 * .pi * 659 * vibrato * t)
                let env = min(1, t * 40) * (p < 0.8 ? 1 : (1 - p) * 5)
                return (a + b) * 0.12 * env
            }
        case .derail:
            // A descending slide with a crunch.
            samples = render(duration: 0.55) { t, p in
                let freq = 520 * pow(0.22, p)
                let tone = square(2 * .pi * freq * t) * 0.18
                let crunch = Double.random(in: -1...1) * exp(-t * 7) * 0.35
                return (tone + crunch) * (1 - p)
            }
        case .nearMiss:
            // A quick double chirp.
            samples = render(duration: 0.22) { t, p in
                let freq: Double = t < 0.1 ? 880 : 1175
                let gate: Double = (t < 0.08 || (t > 0.11 && t < 0.2)) ? 1 : 0
                return square(2 * .pi * freq * t) * 0.1 * gate * (1 - p * 0.5)
            }
        }
        return wav(samples)
    }

    private func square(_ phase: Double) -> Double {
        sin(phase) >= 0 ? 1 : -1
    }

    /// Calls `voice` with the time in seconds and progress 0…1.
    private func render(duration: Double, voice: (Double, Double) -> Double) -> [Float] {
        let count = Int(duration * sampleRate)
        return (0..<count).map { i in
            let t = Double(i) / sampleRate
            return Float(max(-1, min(1, voice(t, Double(i) / Double(count)))))
        }
    }

    private func wav(_ samples: [Float]) -> Data {
        var pcm = Data(capacity: samples.count * 2)
        for s in samples {
            var v = Int16(s * 32_000)
            pcm.append(Data(bytes: &v, count: 2))
        }
        var data = Data()
        func put(_ s: String) { data.append(s.data(using: .ascii)!) }
        func put32(_ v: UInt32) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 4)) }
        func put16(_ v: UInt16) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 2)) }
        put("RIFF"); put32(UInt32(36 + pcm.count)); put("WAVE")
        put("fmt "); put32(16); put16(1); put16(1)
        put32(UInt32(sampleRate)); put32(UInt32(sampleRate) * 2); put16(2); put16(16)
        put("data"); put32(UInt32(pcm.count))
        data.append(pcm)
        return data
    }
}

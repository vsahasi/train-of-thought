import AppKit
import QuartzCore
import TrainCore

/// The train, drawn with Core Animation.
///
/// Everything that moves is a repeating CA animation: wheels and bob on
/// each car, the scrolling track, the smoke emitter. Once they are set up,
/// the render server does the work and this process sits at roughly zero
/// CPU. Coupling, braking, near misses and the wreck are explicit
/// animations layered on top.
///
/// Coordinates: the locomotive lives at x = 0 inside `trainLayer`; cars
/// trail into negative x. Moving the train means moving `trainLayer`.
final class TrainScene: NSView {
    /// Sprite, track, and room for smoke above. Depends on the pixel scale.
    static var height: CGFloat { (16 + 3 + 20) * Pixel.scale }

    private var scale: CGFloat { Pixel.scale }
    private var trackHeight: CGFloat { 3 * scale }
    private var spriteHeight: CGFloat { 16 * scale }
    private var couplerWidth: CGFloat { 2 * scale }
    private var tileWidth: CGFloat { 8 * scale }
    /// Where the locomotive starts.
    var leftMargin: CGFloat = 28
    private let rightMargin: CGFloat = 28

    private let trackLayer = CALayer()
    private let trainLayer = CALayer()
    private var locoLayer: CALayer?
    private var carLayers: [CALayer] = []
    private var couplerLayers: [CALayer] = []
    private let smoke = CAEmitterLayer()
    private let puff = CAEmitterCell()

    private(set) var isMoving = true
    private(set) var isWrecking = false
    private(set) var isRerouting = false
    var isBusy: Bool { isWrecking || isRerouting }

    /// When nothing has happened for a while the train fades back so it
    /// stops pulling your eye. Events bring it forward again.
    var fadesWhenQuiet = true { didSet { noteActivity() } }
    private let quietOpacity: Float = 0.42
    private let quietAfter: TimeInterval = 6
    private var fadeWork: DispatchWorkItem?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.addSublayer(trackLayer)
        layer?.addSublayer(trainLayer)
        trainLayer.anchorPoint = .zero
        trainLayer.masksToBounds = false
        configureSmoke()
        trainLayer.addSublayer(smoke)
        relayout()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { false }

    // MARK: Layout

    /// Call when the window's width or the pixel scale changes.
    func relayout() {
        let width = bounds.width
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutTrack(width: width)
        trainLayer.frame = CGRect(x: trainOriginX(forCars: carLayers.count), y: trackHeight, width: locoWidth, height: spriteHeight)
        // Chimney: columns 18–22, row 2 of the locomotive sprite.
        smoke.emitterPosition = CGPoint(x: 20.5 * scale, y: spriteHeight - 2 * scale)
        CATransaction.commit()
    }

    private var locoWidth: CGFloat { Pixel.size(of: Sprite.locomotive).width }
    private var carWidth: CGFloat { Pixel.size(of: Sprite.boxcar).width }
    private var carPitch: CGFloat { carWidth + couplerWidth }

    /// Points per second. A longer train has more momentum.
    private var speed: CGFloat {
        (36 + 1.6 * CGFloat(min(carLayers.count, 24))) * scale
    }

    /// Where the train layer's origin (the locomotive's left edge) sits for
    /// a given number of cars: the train grows rightward until the
    /// locomotive reaches the right margin, then the tail runs off-screen.
    private func trainOriginX(forCars count: Int) -> CGFloat {
        let wanted = leftMargin + CGFloat(count) * carPitch
        let maxOrigin = bounds.width - rightMargin - locoWidth
        return min(wanted, maxOrigin)
    }

    private func layoutTrack(width: CGFloat) {
        let tiles = Int((width / tileWidth).rounded(.up)) + 2
        let tile = Pixel.image(Sprite.trackTile, cacheKey: "track")
        let tileW = Sprite.trackTile[0].count
        let tileH = Sprite.trackTile.count
        let context = CGContext(
            data: nil, width: tileW * tiles, height: tileH, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        for i in 0..<tiles {
            context.draw(tile, in: CGRect(x: i * tileW, y: 0, width: tileW, height: tileH))
        }
        trackLayer.contents = context.makeImage()
        trackLayer.magnificationFilter = .nearest
        trackLayer.minificationFilter = .nearest
        trackLayer.anchorPoint = .zero
        trackLayer.frame = CGRect(x: 0, y: 0, width: CGFloat(tiles) * tileWidth, height: trackHeight)
        updateTrackSpeed()
    }

    private func updateTrackSpeed() {
        trackLayer.removeAnimation(forKey: "scroll")
        let scroll = CABasicAnimation(keyPath: "position.x")
        scroll.fromValue = 0
        scroll.toValue = -tileWidth
        scroll.duration = CFTimeInterval(tileWidth / speed)
        scroll.repeatCount = .infinity
        trackLayer.add(scroll, forKey: "scroll")
        if !isMoving {
            freezeMotion()
        }
    }

    // MARK: Building the train

    /// Replaces whatever is on screen with this train, no animation.
    func rebuild(cars: [Car]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        removeTrainLayers()
        let loco = makeSpriteLayer(Sprite.locomotive, gold: false, key: "loco", bobPhase: 0)
        loco.frame = CGRect(x: 0, y: 0, width: locoWidth, height: spriteHeight)
        trainLayer.insertSublayer(loco, below: smoke)
        locoLayer = loco
        for car in cars {
            appendCarLayer(car)
        }
        trainLayer.frame.origin.x = trainOriginX(forCars: cars.count)
        CATransaction.commit()
        updateTrackSpeed()
        if isMoving {
            setBirthRate(normalBirthRate)
        } else {
            freezeMotion()
        }
    }

    /// A new train rolls in from the left.
    func arrive(cars: [Car]) {
        rebuild(cars: cars)
        setMoving(true)
        let target = trainOriginX(forCars: cars.count)
        // Cars trail to the left of the locomotive, so with the nose at the
        // screen edge the whole train is already off-screen.
        let start = -locoWidth - 2 * scale
        let roll = CABasicAnimation(keyPath: "position.x")
        roll.fromValue = start
        roll.toValue = target
        roll.duration = 1.0
        roll.timingFunction = CAMediaTimingFunction(name: .easeOut)
        trainLayer.add(roll, forKey: "roll")
        burstSmoke(rate: 30, for: 0.6)
        noteActivity()
    }

    /// Couples a car onto the tail, with a jolt through the train.
    func couple(_ car: Car) {
        guard locoLayer != nil else { return }
        let layer = appendCarLayer(car)
        let count = carLayers.count

        // The new car slides in from behind and fades up.
        let slide = CABasicAnimation(keyPath: "position.x")
        slide.fromValue = layer.position.x - carPitch * 1.5
        slide.toValue = layer.position.x
        slide.duration = 0.5
        slide.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.3
        layer.add(slide, forKey: "slide")
        layer.add(fade, forKey: "fade")

        // The whole train pulls forward one car length.
        let from = trainLayer.frame.origin.x
        let to = trainOriginX(forCars: count)
        trainLayer.frame.origin.x = to
        if to != from {
            let pull = CASpringAnimation(keyPath: "position.x")
            pull.fromValue = from
            pull.toValue = to
            pull.damping = 14
            pull.stiffness = 120
            pull.mass = 1
            pull.initialVelocity = 0
            pull.duration = pull.settlingDuration
            trainLayer.add(pull, forKey: "pull")
        }

        // Jolt: every existing car bumps back then forward, tail first.
        for (index, existing) in (carLayers.dropLast() + [locoLayer!]).reversed().enumerated() {
            let jolt = CAKeyframeAnimation(keyPath: "transform.translation.x")
            jolt.values = [0, -scale, scale / 2, 0]
            jolt.keyTimes = [0, 0.3, 0.7, 1]
            jolt.duration = 0.28
            // Layers that have been frozen and thawed carry a shifted clock, so
            // schedule in the layer's own time, never in absolute time.
            jolt.beginTime = existing.convertTime(CACurrentMediaTime(), from: nil) + 0.4 + Double(index) * 0.03
            jolt.isAdditive = true
            existing.add(jolt, forKey: "jolt")
        }
        updateTrackSpeed()
        burstSmoke(rate: 24, for: 0.5)
        noteActivity()
    }

    /// Everything tumbles off the track. Calls `completion` once the rails
    /// are clear.
    func derail(completion: @escaping () -> Void) {
        guard let loco = locoLayer else { completion(); return }
        isWrecking = true
        noteActivity()
        thawMotion()
        isMoving = true
        setBirthRate(0)
        trainLayer.removeAnimation(forKey: "pull")
        trainLayer.removeAnimation(forKey: "roll")

        let victims: [CALayer] = [loco] + carLayers
        var rng = SystemRandomNumberGenerator()
        for (index, layer) in victims.enumerated() {
            layer.removeAnimation(forKey: "wheels")
            layer.removeAnimation(forKey: "bob")
            let now = layer.convertTime(CACurrentMediaTime(), from: nil)
            let delay = Double(index) * 0.045
            let dir: CGFloat = Bool.random(using: &rng) ? 1 : -1
            let spin = CGFloat.random(in: 0.9...2.6, using: &rng) * dir
            let hop = CGFloat.random(in: 9...19, using: &rng) * scale
            let drift = CGFloat.random(in: -20...25, using: &rng) * scale

            let rotate = CABasicAnimation(keyPath: "transform.rotation.z")
            rotate.fromValue = 0
            rotate.toValue = spin
            let rise = CAKeyframeAnimation(keyPath: "transform.translation.y")
            rise.values = [0, hop, -Self.height - 80]
            rise.keyTimes = [0, 0.22, 1]
            rise.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn)]
            let slide = CABasicAnimation(keyPath: "transform.translation.x")
            slide.fromValue = 0
            slide.toValue = drift
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [1, 1, 0]
            fade.keyTimes = [0, 0.75, 1]

            let group = CAAnimationGroup()
            group.animations = [rotate, rise, slide, fade]
            group.duration = 1.35
            group.beginTime = now + delay
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false
            layer.add(group, forKey: "wreck")
        }
        for coupler in couplerLayers {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.duration = 0.3
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false
            coupler.add(fade, forKey: "wreck")
        }
        burstSmoke(rate: 90, for: 0.35)

        let total = 1.35 + Double(victims.count) * 0.045 + 0.25
        DispatchQueue.main.asyncAfter(deadline: .now() + total) { [weak self] in
            guard let self = self else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.removeTrainLayers()
            CATransaction.commit()
            self.isWrecking = false
            completion()
        }
    }

    /// A lone locomotive leaves for another line: it simply drives off to
    /// the right. No drama, nothing was lost.
    func reroute(completion: @escaping () -> Void) {
        guard locoLayer != nil else { completion(); return }
        isRerouting = true
        thawMotion()
        isMoving = true
        setBirthRate(normalBirthRate * 3)
        trainLayer.removeAnimation(forKey: "pull")
        trainLayer.removeAnimation(forKey: "roll")
        let from = trainLayer.frame.origin.x
        let to = bounds.width + 40
        let drive = CABasicAnimation(keyPath: "position.x")
        drive.fromValue = from
        drive.toValue = to
        drive.duration = 0.6
        drive.timingFunction = CAMediaTimingFunction(name: .easeIn)
        drive.fillMode = .forwards
        drive.isRemovedOnCompletion = false
        trainLayer.add(drive, forKey: "drive")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in
            guard let self = self else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.removeTrainLayers()
            self.trainLayer.removeAnimation(forKey: "drive")
            CATransaction.commit()
            self.isRerouting = false
            completion()
        }
    }

    /// Removes the train without ceremony (pause, retirement at the station).
    func clear() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        removeTrainLayers()
        CATransaction.commit()
        setBirthRate(0)
    }

    // MARK: Motion

    /// Braking or parked: the track and wheels freeze and the smoke stops.
    /// Moving again: everything picks back up.
    func setMoving(_ moving: Bool) {
        guard moving != isMoving else { return }
        isMoving = moving
        if moving {
            thawMotion()
            setBirthRate(normalBirthRate)
        } else {
            freezeMotion()
            setBirthRate(0)
        }
        noteActivity()
    }

    /// Came back inside the grace: the train shudders.
    func nearMiss() {
        guard let loco = locoLayer else { return }
        for (index, layer) in ([loco] + carLayers).enumerated() {
            let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
            shake.values = [0, -scale, scale, -scale / 2, scale / 2, 0]
            shake.duration = 0.4
            shake.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + Double(index) * 0.02
            shake.isAdditive = true
            layer.add(shake, forKey: "shake")
        }
        burstSmoke(rate: 40, for: 0.3)
        noteActivity()
    }

    // MARK: Attention

    /// Something happened: show the train at full strength, then let it
    /// fade back if nothing else does.
    func noteActivity() {
        fadeWork?.cancel()
        setOpacity(1, duration: 0.2)
        guard fadesWhenQuiet else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.setOpacity(self.quietOpacity, duration: 1.4)
        }
        fadeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + quietAfter, execute: work)
    }

    private func setOpacity(_ value: Float, duration: TimeInterval) {
        guard let layer = layer, layer.opacity != value else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = layer.presentation()?.opacity ?? layer.opacity
        fade.toValue = value
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.opacity = value
        layer.add(fade, forKey: "attention")
    }

    // MARK: Private

    private var motionLayers: [CALayer] {
        [trackLayer] + (locoLayer.map { [$0] } ?? []) + carLayers
    }

    private func freezeMotion() {
        for layer in motionLayers where layer.speed != 0 {
            let paused = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.speed = 0
            layer.timeOffset = paused
        }
    }

    private func thawMotion() {
        for layer in motionLayers where layer.speed == 0 {
            let paused = layer.timeOffset
            layer.speed = 1
            layer.timeOffset = 0
            layer.beginTime = 0
            let sincePause = layer.convertTime(CACurrentMediaTime(), from: nil) - paused
            layer.beginTime = sincePause
        }
    }

    @discardableResult
    private func appendCarLayer(_ car: Car) -> CALayer {
        let index = carLayers.count
        let rows = Sprite.car(car.kind)
        let layer = makeSpriteLayer(rows, gold: car.isGold, key: "car-\(car.kind.rawValue)", bobPhase: Double(index + 1) * 0.09)
        let x = -CGFloat(index + 1) * carPitch
        layer.frame = CGRect(x: x, y: 0, width: carWidth, height: spriteHeight)
        trainLayer.insertSublayer(layer, below: smoke)
        carLayers.append(layer)

        let coupler = CALayer()
        coupler.contents = Pixel.image(Sprite.coupler, cacheKey: "coupler")
        coupler.magnificationFilter = .nearest
        coupler.frame = CGRect(x: x + carWidth, y: 4 * scale, width: couplerWidth, height: scale)
        trainLayer.insertSublayer(coupler, below: smoke)
        couplerLayers.append(coupler)
        if !isMoving {
            freezeMotion()
        }
        return layer
    }

    private func makeSpriteLayer(_ rows: [String], gold: Bool, key: String, bobPhase: Double) -> CALayer {
        let frames = Sprite.frames(rows, gold: gold, key: key)
        let layer = CALayer()
        layer.contents = frames[0]
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .nearest
        layer.contentsGravity = .resize

        let wheels = CAKeyframeAnimation(keyPath: "contents")
        wheels.values = frames
        wheels.calculationMode = .discrete
        wheels.duration = 0.28
        wheels.repeatCount = .infinity
        layer.add(wheels, forKey: "wheels")

        let bob = CAKeyframeAnimation(keyPath: "transform.translation.y")
        bob.values = [0, scale, 0, 0]
        bob.keyTimes = [0, 0.25, 0.5, 1]
        bob.calculationMode = .discrete
        bob.duration = 0.56
        bob.repeatCount = .infinity
        bob.timeOffset = bobPhase
        bob.isAdditive = true
        layer.add(bob, forKey: "bob")
        return layer
    }

    private func removeTrainLayers() {
        locoLayer?.removeFromSuperlayer()
        locoLayer = nil
        carLayers.forEach { $0.removeFromSuperlayer() }
        carLayers.removeAll()
        couplerLayers.forEach { $0.removeFromSuperlayer() }
        couplerLayers.removeAll()
    }

    private let normalBirthRate: Float = 4

    private func configureSmoke() {
        smoke.emitterShape = .point
        smoke.renderMode = .oldestFirst
        smoke.zPosition = 10

        puff.name = "puff"
        puff.contents = Pixel.image(Sprite.puff, cacheKey: "puff")
        puff.birthRate = normalBirthRate
        puff.lifetime = 1.7
        puff.lifetimeRange = 0.4
        puff.velocity = 26
        puff.velocityRange = 8
        puff.emissionLongitude = .pi / 2
        puff.emissionRange = 0.3
        puff.xAcceleration = -34
        puff.yAcceleration = 6
        puff.scale = 1.0
        puff.scaleRange = 0.3
        puff.scaleSpeed = 1.1
        puff.alphaSpeed = -0.55
        puff.color = NSColor(white: 0.8, alpha: 0.85).cgColor
        puff.magnificationFilter = CALayerContentsFilter.nearest.rawValue
        smoke.emitterCells = [puff]
    }

    private func burstSmoke(rate: Float, for seconds: TimeInterval) {
        guard locoLayer != nil else { return }
        setBirthRate(rate)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self = self else { return }
            self.setBirthRate((self.isMoving && !self.isBusy && self.locoLayer != nil) ? self.normalBirthRate : 0)
        }
    }

    /// Cells are copied when assigned to the emitter, so later changes
    /// have to go through the emitter's key path.
    private func setBirthRate(_ rate: Float) {
        smoke.setValue(rate, forKeyPath: "emitterCells.puff.birthRate")
    }
}

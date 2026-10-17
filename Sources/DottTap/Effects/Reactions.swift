import AppKit
import QuartzCore

/// On-screen reactions drawn in a click-through overlay. The overlay only exists while an
/// effect is playing, so it costs nothing when idle.
@MainActor
final class Reactions {
    private var window: NSWindow?
    private var root: CALayer?
    private var hideWork: DispatchWorkItem?
    private var activeUntil: Date = .distantPast

    // Stateful effects
    private var combo = 0
    private var comboLayer: CATextLayer?
    private var comboReset: DispatchWorkItem?
    private var ball: BallSim?
    private var stack: [CALayer] = []
    private var stackReset: DispatchWorkItem?
    private var hole: CALayer?
    private var holeSize: CGFloat = 0
    private var holeReset: DispatchWorkItem?

    func play(_ kind: ActionKind, text: String, knockCount: Int) {
        guard let root = prepare() else { return }
        let bounds = root.bounds
        switch kind {
        case .reactFlash: flash(in: root)
        case .reactShockwave: shockwave(in: root, at: CGPoint(x: bounds.midX, y: bounds.midY))
        case .reactGlitch: glitch(in: root)
        case .reactText: showText(text.isEmpty ? "KNOCK KNOCK" : text, in: root)
        case .reactConfetti: confetti(in: root)
        case .reactBall: bounceBall(in: root)
        case .reactCombo: comboHit(in: root)
        case .reactStack: dropBlock(in: root)
        case .reactBlackHole: blackHole(in: root)
        case .reactRandom:
            let pick: [ActionKind] = [.reactFlash, .reactShockwave, .reactGlitch, .reactConfetti, .reactText]
            play(pick.randomElement()!, text: ["KNOCK!", "Who's there?", "👋", "BOOP"].randomElement()!, knockCount: knockCount)
            return
        default: break
        }
    }

    // MARK: Overlay lifetime

    private func prepare() -> CALayer? {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let screen else { return nil }
        if window == nil || window?.screen != screen {
            window?.orderOut(nil)
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            w.isReleasedWhenClosed = false
            let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            w.contentView = view
            w.setFrame(screen.frame, display: false)
            window = w
            root = view.layer
            comboLayer = nil; ball = nil; stack = []; hole = nil; holeSize = 0; combo = 0
        }
        window?.orderFrontRegardless()
        return root
    }

    /// Keeps the overlay up for at least `seconds`, then removes it.
    private func keepAlive(_ seconds: TimeInterval) {
        let until = Date().addingTimeInterval(seconds)
        if until > activeUntil { activeUntil = until }
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, Date() >= self.activeUntil.addingTimeInterval(-0.05) else { return }
            self.window?.orderOut(nil)
            self.root?.sublayers?.forEach { $0.removeFromSuperlayer() }
            self.comboLayer = nil; self.ball?.stop(); self.ball = nil
            self.stack = []; self.hole = nil; self.holeSize = 0
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, activeUntil.timeIntervalSinceNow) + 0.05, execute: work)
    }

    private func remove(_ layer: CALayer, after seconds: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { layer.removeFromSuperlayer() }
        keepAlive(seconds)
    }

    private var scale: CGFloat { window?.screen?.backingScaleFactor ?? 2 }

    // MARK: Effects

    private func flash(in root: CALayer) {
        let l = CALayer()
        l.frame = root.bounds
        l.backgroundColor = NSColor.white.cgColor
        l.opacity = 0
        root.addSublayer(l)
        let a = CAKeyframeAnimation(keyPath: "opacity")
        a.values = [0, 0.6, 0]
        a.keyTimes = [0, 0.12, 1]
        a.duration = 0.32
        l.add(a, forKey: "flash")
        remove(l, after: 0.34)
    }

    private func shockwave(in root: CALayer, at center: CGPoint, color: NSColor = .white) {
        let radius = hypot(root.bounds.width, root.bounds.height) * 0.6
        for (i, delay) in [0.0, 0.09].enumerated() {
            let ring = CAShapeLayer()
            let r: CGFloat = 40
            ring.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: nil)
            ring.position = center
            ring.fillColor = nil
            ring.strokeColor = color.withAlphaComponent(i == 0 ? 0.85 : 0.5).cgColor
            ring.lineWidth = i == 0 ? 10 : 5
            ring.shadowColor = NSColor.systemTeal.cgColor
            ring.shadowRadius = 12
            ring.shadowOpacity = 0.8
            ring.shadowOffset = .zero
            ring.opacity = 0
            root.addSublayer(ring)

            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.1
            grow.toValue = radius / r
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [1, 0.8, 0]
            fade.keyTimes = [0, 0.4, 1]
            let width = CABasicAnimation(keyPath: "lineWidth")
            width.fromValue = ring.lineWidth
            width.toValue = 1
            let g = CAAnimationGroup()
            g.animations = [grow, fade, width]
            g.duration = 0.75
            g.beginTime = CACurrentMediaTime() + delay
            g.timingFunction = CAMediaTimingFunction(name: .easeOut)
            g.fillMode = .backwards
            ring.add(g, forKey: "wave")
            remove(ring, after: 0.75 + delay + 0.05)
        }
    }

    private func glitch(in root: CALayer) {
        let b = root.bounds
        let colors: [NSColor] = [.systemPink, .cyan, .systemGreen, .white, .black]
        for _ in 0..<14 {
            let h = CGFloat.random(in: 4...46)
            let band = CALayer()
            band.frame = CGRect(x: 0, y: .random(in: 0...(b.height - h)), width: b.width, height: h)
            band.backgroundColor = colors.randomElement()!.withAlphaComponent(.random(in: 0.25...0.7)).cgColor
            band.compositingFilter = ["differenceBlendMode", "screenBlendMode", "multiplyBlendMode"].randomElement()
            band.opacity = 0
            root.addSublayer(band)
            let x = CAKeyframeAnimation(keyPath: "position.x")
            x.values = (0..<6).map { _ in b.midX + .random(in: -60...60) }
            x.calculationMode = .discrete
            let o = CAKeyframeAnimation(keyPath: "opacity")
            o.values = (0..<6).map { _ in Float.random(in: 0...1) } + [0]
            o.calculationMode = .discrete
            let g = CAAnimationGroup()
            g.animations = [x, o]
            g.duration = 0.38
            g.beginTime = CACurrentMediaTime() + .random(in: 0...0.08)
            g.fillMode = .backwards
            band.add(g, forKey: "glitch")
            remove(band, after: 0.5)
        }
        // A quick chromatic tint over everything.
        let tint = CALayer()
        tint.frame = b
        tint.backgroundColor = NSColor.systemPink.withAlphaComponent(0.12).cgColor
        tint.compositingFilter = "differenceBlendMode"
        tint.opacity = 0
        root.addSublayer(tint)
        let t = CAKeyframeAnimation(keyPath: "opacity")
        t.values = [1, 0, 1, 0, 1, 0]
        t.calculationMode = .discrete
        t.duration = 0.3
        tint.add(t, forKey: "tint")
        remove(tint, after: 0.32)
    }

    private func showText(_ text: String, in root: CALayer) {
        let t = CATextLayer()
        let font = NSFont.systemFont(ofSize: min(140, root.bounds.width / CGFloat(max(4, text.count)) * 1.6), weight: .black)
        t.string = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: NSColor.white,
            .strokeColor: NSColor.black.withAlphaComponent(0.35), .strokeWidth: -2,
        ])
        t.alignmentMode = .center
        t.contentsScale = scale
        let h = font.pointSize * 1.3
        t.frame = CGRect(x: 0, y: root.bounds.midY - h / 2, width: root.bounds.width, height: h)
        t.shadowColor = NSColor.black.cgColor
        t.shadowOpacity = 0.5
        t.shadowRadius = 18
        t.shadowOffset = .zero
        t.opacity = 0
        root.addSublayer(t)
        let s = CASpringAnimation(keyPath: "transform.scale")
        s.fromValue = 0.4; s.toValue = 1
        s.damping = 9; s.stiffness = 220; s.mass = 1
        s.duration = 1.6
        let o = CAKeyframeAnimation(keyPath: "opacity")
        o.values = [0, 1, 1, 0]
        o.keyTimes = [0, 0.08, 0.75, 1]
        o.duration = 1.6
        let g = CAAnimationGroup()
        g.animations = [s, o]
        g.duration = 1.6
        t.add(g, forKey: "text")
        remove(t, after: 1.62)
    }

    private func confetti(in root: CALayer) {
        let e = CAEmitterLayer()
        e.emitterPosition = CGPoint(x: root.bounds.midX, y: root.bounds.maxY + 10)
        e.emitterSize = CGSize(width: root.bounds.width, height: 1)
        e.emitterShape = .line
        e.beginTime = CACurrentMediaTime()
        let colors: [NSColor] = [.systemPink, .systemYellow, .systemTeal, .systemPurple, .systemOrange, .systemGreen]
        e.emitterCells = colors.map { color in
            let c = CAEmitterCell()
            c.contents = Self.confettiImage(color)
            c.birthRate = 28
            c.lifetime = 5
            c.velocity = 260
            c.velocityRange = 120
            c.emissionLongitude = -.pi / 2
            c.emissionRange = .pi / 5
            c.yAcceleration = -260
            c.spin = 3
            c.spinRange = 6
            c.scale = 0.6
            c.scaleRange = 0.3
            return c
        }
        root.addSublayer(e)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { e.birthRate = 0 }
        remove(e, after: 5)
    }

    private static func confettiImage(_ color: NSColor) -> CGImage? {
        let img = NSImage(size: NSSize(width: 14, height: 8), flipped: false) { r in
            color.setFill()
            NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2).fill()
            return true
        }
        return img.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private func bounceBall(in root: CALayer) {
        if ball == nil {
            let size: CGFloat = 120
            let layer = CAGradientLayer()
            layer.type = .conic
            layer.startPoint = CGPoint(x: 0.5, y: 0.5)
            layer.endPoint = CGPoint(x: 0.5, y: 0)
            layer.colors = [NSColor.systemPink, .systemOrange, .systemYellow, .systemGreen, .systemTeal, .systemBlue, .systemPurple, .systemPink].map(\.cgColor)
            layer.frame = CGRect(x: root.bounds.midX - size / 2, y: root.bounds.height * 0.6, width: size, height: size)
            layer.cornerRadius = size / 2
            layer.masksToBounds = true
            let shine = CAGradientLayer()
            shine.type = .radial
            shine.frame = layer.bounds
            shine.colors = [NSColor.white.withAlphaComponent(0.55).cgColor, NSColor.clear.cgColor]
            shine.startPoint = CGPoint(x: 0.35, y: 0.7)
            shine.endPoint = CGPoint(x: 0.95, y: 0.05)
            layer.addSublayer(shine)
            root.addSublayer(layer)
            ball = BallSim(layer: layer, bounds: root.bounds) { [weak self] in
                self?.ball = nil
            }
        }
        ball?.kick()
        keepAlive(ball?.remaining ?? 5)
    }

    private func comboHit(in root: CALayer) {
        combo += 1
        if comboLayer == nil {
            let t = CATextLayer()
            t.alignmentMode = .center
            t.contentsScale = scale
            t.frame = CGRect(x: 0, y: root.bounds.height * 0.72, width: root.bounds.width, height: 130)
            t.shadowColor = NSColor.systemOrange.cgColor
            t.shadowOpacity = 1
            t.shadowRadius = 20
            t.shadowOffset = .zero
            root.addSublayer(t)
            comboLayer = t
        }
        guard let t = comboLayer else { return }
        let knockout = combo >= 10
        let label = knockout ? "KNOCKOUT!" : (combo == 1 ? "KNOCK" : "COMBO ×\(combo)")
        let hue = CGFloat(min(combo, 10)) / 10
        let color = NSColor(hue: 0.12 - hue * 0.12, saturation: 0.9, brightness: 1, alpha: 1)
        t.string = NSAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: 64 + CGFloat(min(combo, 10)) * 5, weight: .black),
            .foregroundColor: color,
        ])
        t.opacity = 1
        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = 1.35; pop.toValue = 1
        pop.damping = 8; pop.stiffness = 300
        pop.duration = 0.6
        t.add(pop, forKey: "pop")
        let shake = CAKeyframeAnimation(keyPath: "position.x")
        shake.values = [0, -8, 8, -4, 0].map { t.position.x + CGFloat($0) * CGFloat(min(combo, 10)) / 4 }
        shake.duration = 0.25
        t.add(shake, forKey: "shake")

        comboReset?.cancel()
        if knockout {
            flash(in: root)
            shockwave(in: root, at: CGPoint(x: root.bounds.midX, y: root.bounds.midY), color: .systemOrange)
            combo = 0
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, let t = self.comboLayer else { return }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1; fade.toValue = 0; fade.duration = 0.3
            t.add(fade, forKey: "fade")
            t.opacity = 0
            self.combo = 0
        }
        comboReset = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (knockout ? 1.2 : 1.8), execute: work)
        keepAlive(knockout ? 1.6 : 2.2)
    }

    private func dropBlock(in root: CALayer) {
        let size: CGFloat = 70
        let columns = max(1, Int(root.bounds.width / (size + 8)))
        // Fill columns near the middle first, so the stack looks like a pile.
        let mid = columns / 2
        let heights = (0..<columns).map { c in stack.filter { Int(($0.position.x - 4) / (size + 8)) == c }.count }
        let candidates = (0..<columns).sorted { abs($0 - mid) + heights[$0] * 2 < abs($1 - mid) + heights[$1] * 2 }
        guard let col = candidates.first(where: { heights[$0] < 10 }) else { return }
        let block = CALayer()
        block.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        block.cornerRadius = 14
        block.backgroundColor = [NSColor.systemPink, .systemOrange, .systemYellow, .systemGreen, .systemTeal, .systemPurple].randomElement()!.cgColor
        block.borderColor = NSColor.white.withAlphaComponent(0.5).cgColor
        block.borderWidth = 2
        let x = CGFloat(col) * (size + 8) + 4 + size / 2
        let y = CGFloat(heights[col]) * (size + 4) + size / 2 + 4
        block.position = CGPoint(x: x, y: y)
        root.addSublayer(block)
        let fall = CABasicAnimation(keyPath: "position.y")
        fall.fromValue = root.bounds.height + size
        fall.toValue = y
        fall.duration = 0.45
        fall.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 0, 1, 1)
        let squash = CAKeyframeAnimation(keyPath: "transform")
        squash.values = [CATransform3DIdentity, CATransform3DMakeScale(1.15, 0.85, 1), CATransform3DIdentity].map { NSValue(caTransform3D: $0) }
        squash.beginTime = CACurrentMediaTime() + 0.45
        squash.duration = 0.18
        block.add(fall, forKey: "fall")
        block.add(squash, forKey: "squash")
        stack.append(block)

        stackReset?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            for b in self.stack {
                let drop = CABasicAnimation(keyPath: "position.y")
                drop.toValue = -size
                drop.duration = .random(in: 0.4...0.8)
                drop.timingFunction = CAMediaTimingFunction(name: .easeIn)
                drop.fillMode = .forwards
                drop.isRemovedOnCompletion = false
                b.add(drop, forKey: "away")
            }
            let gone = self.stack
            self.stack = []
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { gone.forEach { $0.removeFromSuperlayer() } }
        }
        stackReset = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
        keepAlive(5)
    }

    private func blackHole(in root: CALayer) {
        let center = CGPoint(x: root.bounds.midX, y: root.bounds.midY)
        if hole == nil {
            let h = CAGradientLayer()
            h.type = .radial
            h.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.systemPurple.withAlphaComponent(0.6).cgColor, NSColor.clear.cgColor]
            h.locations = [0, 0.45, 0.62, 1]
            h.startPoint = CGPoint(x: 0.5, y: 0.5)
            h.endPoint = CGPoint(x: 1, y: 1)
            h.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
            h.position = center
            let swirl = CAGradientLayer()
            swirl.type = .conic
            swirl.startPoint = CGPoint(x: 0.5, y: 0.5)
            swirl.endPoint = CGPoint(x: 0.5, y: 0)
            swirl.colors = [NSColor.clear, NSColor.systemPurple.withAlphaComponent(0.5), .clear, NSColor.systemIndigo.withAlphaComponent(0.5), .clear].map(\.cgColor)
            swirl.frame = h.bounds
            swirl.cornerRadius = 5
            swirl.masksToBounds = true
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0; spin.toValue = -2 * Double.pi
            spin.duration = 1.4
            spin.repeatCount = .infinity
            swirl.add(spin, forKey: "spin")
            h.addSublayer(swirl)
            root.addSublayer(h)
            hole = h
            holeSize = 0
        }
        guard let h = hole else { return }
        let maxSize = min(root.bounds.width, root.bounds.height) * 0.9
        holeSize = min(maxSize, holeSize + 110)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.35)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        h.bounds = CGRect(x: 0, y: 0, width: holeSize, height: holeSize)
        h.sublayers?.first?.frame = h.bounds
        h.sublayers?.first?.cornerRadius = holeSize / 2
        CATransaction.commit()

        holeReset?.cancel()
        let collapse = { [weak self] in
            guard let self, let h = self.hole else { return }
            let shrink = CABasicAnimation(keyPath: "transform.scale")
            shrink.toValue = 0.01
            shrink.duration = 0.35
            shrink.timingFunction = CAMediaTimingFunction(name: .easeIn)
            shrink.fillMode = .forwards
            shrink.isRemovedOnCompletion = false
            h.add(shrink, forKey: "collapse")
            self.hole = nil
            self.holeSize = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                h.removeFromSuperlayer()
                if let root = self.root {
                    self.shockwave(in: root, at: center, color: .systemPurple)
                    self.flash(in: root)
                }
            }
        }
        if holeSize >= maxSize {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { collapse() }
            keepAlive(1.8)
        } else {
            let work = DispatchWorkItem(block: collapse)
            holeReset = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
            keepAlive(3.8)
        }
    }
}

/// Tiny physics loop for the bouncing ball; runs only while the ball moves.
@MainActor
private final class BallSim {
    let layer: CALayer
    let bounds: CGRect
    var vx: CGFloat = 0, vy: CGFloat = 0
    var timer: Timer?
    var restingSince: Date?
    var lastKick = Date()
    let onDone: () -> Void

    init(layer: CALayer, bounds: CGRect, onDone: @escaping () -> Void) {
        self.layer = layer
        self.bounds = bounds
        self.onDone = onDone
    }

    var remaining: TimeInterval { 6 }

    func kick() {
        vy = .random(in: 1500...2000)
        vx += .random(in: -700...700)
        lastKick = Date()
        restingSince = nil
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.step(1.0 / 60) }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func step(_ dt: CGFloat) {
        var p = layer.position
        let r = layer.bounds.width / 2
        vy -= 3200 * dt
        p.x += vx * dt
        p.y += vy * dt
        if p.y - r < 0 { p.y = r; vy = -vy * 0.62; vx *= 0.92; if abs(vy) < 90 { vy = 0 } }
        if p.x - r < 0 { p.x = r; vx = -vx * 0.8 }
        if p.x + r > bounds.width { p.x = bounds.width - r; vx = -vx * 0.8 }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.position = p
        layer.transform = CATransform3DRotate(layer.transform, -vx * dt / r, 0, 0, 1)
        CATransaction.commit()

        let resting = vy == 0 && p.y <= r + 1
        if resting { vx *= 0.9 }
        if resting && restingSince == nil { restingSince = Date() }
        if Date().timeIntervalSince(lastKick) > 5.5 {
            stop()
            layer.removeFromSuperlayer()
            onDone()
        }
    }
}

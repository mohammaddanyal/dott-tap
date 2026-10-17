import Foundation
import simd

/// What a single knock looked like to the sensor. Used to tell surfaces apart.
struct KnockFeatures: Codable, Hashable {
    var peak: Float          // g, high-passed magnitude
    var ex: Float            // share of energy on each axis (sums to 1)
    var ey: Float
    var ez: Float
    var sx: Float            // direction of the first jolt per axis (-1...1)
    var sy: Float
    var sz: Float
    var decayMs: Float       // how long it rings above a quarter of the peak
    var lowShare: Float      // share of energy below ~13 Hz (lid wobble)
    var rateHz: Float

    /// Vector used by the surface classifier. Direction of the shake (which axis, which
    /// way) carries most of the weight because it doesn't change with how hard you knock;
    /// ring time and wobble do, so they only nudge.
    var vector: [Float] {
        [ex * 2, ey * 2, ez * 2, sx * 1.5, sy * 1.5, sz * 1.5,
         log2(max(decayMs, 5) / 40) * 0.35, lowShare]
    }
}

struct DetectorTuning {
    /// Knock must be this many times above the background noise...
    var noiseMultiple: Float = 7
    /// ...and at least this strong in g.
    var minPeak: Float = 0.008
    /// Anything above this is a slap or a drop; ignored unless `allowHard`.
    var maxPeak: Float = 3.0
    /// Longest ring we still accept; longer means the Mac is being moved or shaken.
    var maxDecayMs: Float = 220
    /// Gravity shift (g) that means the Mac was lifted or tilted, not knocked.
    var maxTilt: Float = 0.06
}

/// Turns the raw 3-axis stream into individual knock events. Runs on the sensor thread,
/// allocates nothing per sample and does a handful of multiply-adds per report.
final class KnockDetector {
    var onKnock: ((Double, KnockFeatures) -> Void)?
    /// Something moved: the engine uses this to raise the sample rate for a moment.
    var onActivity: ((Double) -> Void)?
    /// Rejected spike with the reason, for the live test view.
    var onReject: ((Double, String, Float) -> Void)?

    private let lock = NSLock()
    private var _tuning = DetectorTuning()
    var tuning: DetectorTuning {
        get { lock.lock(); defer { lock.unlock() }; return _tuning }
        set { lock.lock(); _tuning = newValue; lock.unlock() }
    }

    // Live level for the test graph (written here, read by UI).
    let monitor = LevelMonitor()

    // Filter state
    private var lastT: Double = 0
    private var prevX: Float = 0, prevY: Float = 0, prevZ: Float = 0
    private var hpX: Float = 0, hpY: Float = 0, hpZ: Float = 0
    private var lastHPX: Float = 0, lastHPY: Float = 0, lastHPZ: Float = 0
    private var lpX: Float = 0, lpY: Float = 0, lpZ: Float = 0   // ~30 ms low-pass
    private var gX: Float = 0, gY: Float = 0, gZ: Float = -1     // gravity, ~0.6 s
    private var noise: Float = 0.002
    private var warmup = 0
    // Smoothed (15 ms RMS) envelope of the high-passed magnitude, and how sharply the signal
    // changes from one sample to the next. Used to spot a new knock inside a ringing one.
    private var envSq: Float = 0
    private var env: Float = 0
    private var jerk: Float = 0

    // Ring buffer of recent high-passed samples for pre-trigger context
    private static let ringSize = 32
    private var ring = [SIMD4<Float>](repeating: .zero, count: ringSize) // hp x,y,z + low-band magnitude²
    private var ringIdx = 0

    // Capture state
    private var capturing = false
    private var captureStart: Double = 0
    private var captureThreshold: Float = 0
    private var lastAboveFloor: Double = 0
    private var peak: Float = 0
    private var peakT: Double = 0
    private var eX: Float = 0, eY: Float = 0, eZ: Float = 0, eLow: Float = 0
    // The first ~20 ms of the knock, to read which way the Mac was first pushed.
    private static let firstSlots = 24
    private var firstHP = [SIMD3<Float>](repeating: .zero, count: firstSlots)
    private var firstCount = 0
    private var lastAbove: Double = 0
    private var gravityBefore = SIMD3<Float>(0, 0, -1)
    private var lastOnset: Double = -10
    private var captureSamples = 0
    private var envPeak: Float = 0
    private var envMinAfterPeak: Float = 0
    private var attackJerk: Float = 0
    private var attackT: Double = -10
    private var captureTuning = DetectorTuning()

    // A knock rings for 30–150 ms. Capture until it has died down, so the tail is never
    // mistaken for a second knock.
    private let minCapture = 0.05
    private let maxCapture = 0.26
    private let quietHold = 0.02
    private let firstJoltLength = 0.02   // seconds used for jolt direction
    private let refractory = 0.08        // minimum spacing between knock onsets
    // Echo guard: right after a knock, the bar for the next one starts high and decays.
    private var echoPeak: Float = 0
    private var echoT: Double = -10
    // Last time the Mac was moved or shaken; knocks right after that are ignored.
    private var lastDisturbance: Double = -10

    /// True while a knock is ringing out and its verdict isn't in yet. Sensor thread only.
    var isCapturing: Bool { capturing }

    func reset() {
        warmup = 0
        capturing = false
        lastT = 0
        env = 0
        envSq = 0
    }

    func process(t: Double, x: Float, y: Float, z: Float) {
        var dt = Float(t - lastT)
        let gap = lastT == 0 || dt > 0.08 || dt <= 0
        lastT = t
        if gap {
            // First sample, or the stream paused / changed rate: restart filters around here.
            prevX = x; prevY = y; prevZ = z
            hpX = 0; hpY = 0; hpZ = 0
            lpX = x; lpY = y; lpZ = z
            if warmup == 0 { gX = x; gY = y; gZ = z }
            capturing = false
            warmup = max(warmup, 1)
            return
        }
        dt = min(dt, 0.02)

        // ~13 Hz one-pole high-pass: keeps the knock, drops posture and slow motion.
        let aHP: Float = 0.012 / (0.012 + dt)
        hpX = aHP * (hpX + x - prevX)
        hpY = aHP * (hpY + y - prevY)
        hpZ = aHP * (hpZ + z - prevZ)
        prevX = x; prevY = y; prevZ = z

        // ~30 ms low-pass, used for the "low band" (lid wobble) and tilt check.
        let aLP: Float = dt / (0.03 + dt)
        lpX += aLP * (x - lpX); lpY += aLP * (y - lpY); lpZ += aLP * (z - lpZ)

        let m2 = hpX * hpX + hpY * hpY + hpZ * hpZ
        let m = m2.squareRoot()
        envSq += min(1, dt / 0.015) * (m2 - envSq)
        env = envSq.squareRoot()
        let jx = hpX - lastHPX, jy = hpY - lastHPY, jz = hpZ - lastHPZ
        jerk = (jx * jx + jy * jy + jz * jz).squareRoot() * (0.00125 / dt)   // per 800 Hz step
        lastHPX = hpX; lastHPY = hpY; lastHPZ = hpZ
        let lowX = lpX - gX, lowY = lpY - gY, lowZ = lpZ - gZ
        let low2 = lowX * lowX + lowY * lowY + lowZ * lowZ

        ring[ringIdx] = SIMD4(hpX, hpY, hpZ, low2)
        ringIdx = (ringIdx + 1) & (Self.ringSize - 1)
        monitor.push(m)

        if warmup < 60 {
            // Let the filters settle after a start or a gap.
            warmup += 1
            let aG: Float = min(1, dt / 0.15)
            gX += aG * (x - gX); gY += aG * (y - gY); gZ += aG * (z - gZ)
            noise += (dt / 0.5) * (m - noise)
            return
        }

        if capturing {
            let elapsed = t - captureStart
            if elapsed <= 0.015 { attackJerk = max(attackJerk, jerk) }
            if env > envPeak { envPeak = env; envMinAfterPeak = env }
            envMinAfterPeak = min(envMinAfterPeak, env)
            // A second knock landing while the first still rings: close the first one here and
            // start the next, so quick double and triple knocks aren't merged. Either the ring
            // has faded and the signal comes back strong, or there's an attack nearly as sharp
            // as the first knock's that grows big within 8 ms. A ring that swells and fades on
            // its own (common on desks) does neither.
            if elapsed > 0.08 && jerk > 0.5 * attackJerk && envMinAfterPeak < 0.5 * envPeak { attackT = t }
            let faded = envMinAfterPeak < 0.25 * envPeak && env > max(0.55 * envPeak, captureThreshold * 0.7)
            let attacked = t - attackT < 0.008 && m > 0.55 * peak
            if elapsed > 0.08 && (faded || attacked) {
                let tune = captureTuning, threshold = captureThreshold
                finishCapture(t: t, stillRinging: false)
                beginCapture(t: t, dt: dt, tuning: tune, threshold: threshold)
                accumulate(t: t, m: m, low2: low2, dt: dt)
                return
            }
            accumulate(t: t, m: m, low2: low2, dt: dt)
            if m > max(peak * 0.12, captureThreshold * 0.5) { lastAboveFloor = t }
            if elapsed >= maxCapture {
                finishCapture(t: t, stillRinging: m > peak * 0.25)
            } else if elapsed >= minCapture && t - lastAboveFloor >= quietHold {
                finishCapture(t: t, stillRinging: false)
            }
            return
        }

        // Quiet: follow gravity and the noise floor.
        let aG = dt / 0.6
        gX += aG * (x - gX); gY += aG * (y - gY); gZ += aG * (z - gZ)
        // Rise slowly, fall faster, so one bump doesn't deafen us for seconds.
        let aN = m > noise ? dt / 4 : dt / 1.5
        noise += aN * (m - noise)
        noise = max(noise, 0.0004)

        let tune = tuning
        var threshold = max(tune.minPeak, tune.noiseMultiple * noise)
        let sinceLast = Float(t - echoT)
        if sinceLast < 0.6 { threshold = max(threshold, echoPeak * 0.6 * exp(-sinceLast / 0.12)) }
        if m > threshold * 0.5 { onActivity?(t) }
        if m > threshold && t - lastOnset > refractory {
            beginCapture(t: t, dt: dt, tuning: tune, threshold: threshold)
            accumulate(t: t, m: m, low2: low2, dt: dt)
        }
    }

    private func beginCapture(t: Double, dt: Float, tuning: DetectorTuning, threshold: Float) {
        capturing = true
        captureTuning = tuning
        captureStart = t
        captureThreshold = threshold
        lastAboveFloor = t
        lastOnset = t
        captureSamples = 0
        peak = 0
        envPeak = env
        envMinAfterPeak = env
        attackJerk = jerk
        attackT = -10
        eX = 0; eY = 0; eZ = 0; eLow = 0
        firstCount = 0
        gravityBefore = SIMD3(gX, gY, gZ)
        // Include a few samples from just before the threshold crossing in the energy.
        let pre = min(Self.ringSize - 1, max(1, Int(0.006 / Double(dt))))
        for k in 1...pre {
            let s = ring[(ringIdx - 1 - k + Self.ringSize * 2) & (Self.ringSize - 1)]
            eX += s.x * s.x * dt; eY += s.y * s.y * dt; eZ += s.z * s.z * dt; eLow += s.w * dt
        }
    }

    private func accumulate(t: Double, m: Float, low2: Float, dt: Float) {
        captureSamples += 1
        eX += hpX * hpX * dt; eY += hpY * hpY * dt; eZ += hpZ * hpZ * dt; eLow += low2 * dt
        if t - captureStart <= firstJoltLength && firstCount < Self.firstSlots {
            firstHP[firstCount] = SIMD3(hpX, hpY, hpZ)
            firstCount += 1
        }
        if m > peak { peak = m; peakT = t }
        if m > peak * 0.25 { lastAbove = t }
    }

    private func finishCapture(t: Double, stillRinging: Bool) {
        capturing = false
        echoPeak = peak
        echoT = t
        let tune = captureTuning
        let decayMs = Float(lastAbove - peakT) * 1000
        let tilt = simd_length(SIMD3(lpX, lpY, lpZ) - gravityBefore)
        let eHigh = eX + eY + eZ
        let total = max(eHigh + eLow, 1e-12)

        // Still ringing hard at the end of the window: shaking, walking, a bump.
        if stillRinging || decayMs > tune.maxDecayMs { lastDisturbance = t; onReject?(captureStart, "long", peak); return }
        if tilt > tune.maxTilt { lastDisturbance = t; onReject?(captureStart, "moved", peak); return }
        if captureStart - lastDisturbance < 0.8 { onReject?(captureStart, "handling", peak); return }
        if peak > tune.maxPeak { onReject?(captureStart, "too hard", peak); return }

        // Direction of the first big push: the first sample that reaches half of the opening
        // swing. Reading it this way ignores what's left of an earlier knock still ringing.
        var first = SIMD3<Float>(0, 0, 1)
        var biggest: Float = 0
        for i in 0..<firstCount { biggest = max(biggest, simd_length(firstHP[i])) }
        for i in 0..<firstCount where simd_length(firstHP[i]) >= biggest * 0.5 {
            first = firstHP[i] / max(simd_length(firstHP[i]), 1e-9)
            break
        }
        let features = KnockFeatures(
            peak: peak,
            ex: eX / max(eHigh, 1e-12), ey: eY / max(eHigh, 1e-12), ez: eZ / max(eHigh, 1e-12),
            sx: first.x, sy: first.y, sz: first.z,
            decayMs: decayMs,
            lowShare: eLow / total,
            rateHz: Float(Double(captureSamples) / max(t - captureStart, 0.001)))
        onKnock?(captureStart, features)
    }
}

/// Lock-free-ish ring of recent magnitudes the UI can draw. Only written while `enabled`.
final class LevelMonitor {
    static let size = 1600
    private let lock = NSLock()
    private var values = [Float](repeating: 0, count: size)
    private var index = 0
    var enabled = false

    func push(_ v: Float) {
        guard enabled else { return }
        lock.lock()
        values[index] = v
        index = (index + 1) % Self.size
        lock.unlock()
    }

    func snapshot() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        return Array(values[index...] + values[..<index])
    }
}

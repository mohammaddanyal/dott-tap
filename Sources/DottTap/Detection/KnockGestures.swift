import CoreGraphics
import Foundation

/// Groups chassis knocks into single, double and triple gestures on the sensor thread, timed
/// by the sensor's own sample clock. The decision to stop waiting for another knock is made
/// by the samples themselves, so a busy main thread or App Nap can't cut a triple short.
final class KnockGestures {
    struct Config {
        var gap: Double = 0.45
        /// Highest knock count that does something, per surface, for the app in front.
        var maxCount: [Surface: Int] = [:]
        var classifier = SurfaceClassifier(examples: [:])
        var ignoreTyping = true
        var minPeak: Float = 0.04
        var calibrating = false
    }

    struct Knock {
        var t: Double
        var surface: Surface
        var guess: Surface
        var confidence: Double
        var features: KnockFeatures
    }

    enum Event {
        case knock(Knock)
        case rejected(reason: String, features: KnockFeatures?, peak: Float)
        case teach(KnockFeatures)
        case gesture(count: Int, surface: Surface, peak: Float)
    }

    /// Called on the sensor thread.
    var onEvent: ((Event) -> Void)?

    private let lock = NSLock()
    private var _config = Config()
    var config: Config {
        get { lock.lock(); defer { lock.unlock() }; return _config }
        set { lock.lock(); _config = newValue; lock.unlock() }
    }

    private var knocks: [Knock] = []

    init() { knocks.reserveCapacity(8) }

    /// A knock the detector accepted. `t` is when it started, on the sensor clock.
    func knock(at t: Double, features f: KnockFeatures) {
        let c = config
        let sinceOnset = Clock.now() - t
        if c.ignoreTyping {
            // Seconds between the last key and the knock (negative: the key came after it).
            let key = min(Self.since(.keyDown), Self.since(.keyUp), Self.since(.flagsChanged)) - sinceOnset
            if key < 0.32 && key > -0.2 { onEvent?(.rejected(reason: "typing", features: f, peak: f.peak)); return }
        }
        let click = min(Self.since(.leftMouseDown), Self.since(.leftMouseUp), Self.since(.rightMouseDown)) - sinceOnset
        if click < 0.25 && click > -0.15 { onEvent?(.rejected(reason: "click", features: f, peak: f.peak)); return }

        if c.calibrating { onEvent?(.teach(f)); return }

        // Knocks of one gesture land with similar force. A much weaker or stronger hit is a
        // bump or the lid swinging, so it starts a new gesture instead of adding to this one.
        if let first = knocks.first, f.peak < first.features.peak * 0.3 || f.peak > first.features.peak * 3.3 {
            fire(c)
        }

        let r = c.classifier.classify(f)
        let k = Knock(t: t, surface: r.confidence >= 0.35 ? r.surface : .anywhere,
                      guess: r.surface, confidence: r.confidence, features: f)
        knocks.append(k)
        onEvent?(.knock(k))

        let limit = c.maxCount[gestureSurface] ?? c.maxCount[.anywhere] ?? 3
        if knocks.count >= min(3, max(1, limit)) { fire(c) }
    }

    /// Every sample: once the window after the last knock has passed and nothing is ringing,
    /// the gesture is complete.
    func tick(_ t: Double, capturing: Bool) {
        guard let last = knocks.last, !capturing else { return }
        let c = config
        if t - last.t > c.gap { fire(c) }
    }

    func cancel() { knocks.removeAll(keepingCapacity: true) }

    /// Surface for the whole gesture. The first knock counts 1.5 times: it's read with the Mac
    /// at rest, while later ones can still carry the ring of the one before. So a double
    /// follows its first knock, and a triple follows the other two only if they agree.
    private var gestureSurface: Surface {
        guard let first = knocks.first else { return .anywhere }
        var weight: [Surface: Double] = [:]
        for (i, k) in knocks.enumerated() {
            weight[k.surface, default: 0] += (k.surface == .anywhere ? 0.2 : 1) * (i == 0 ? 1.5 : 1)
        }
        let best = weight.max { a, b in a.value == b.value ? b.key == first.surface : a.value < b.value }
        return best?.key ?? first.surface
    }

    private func fire(_ c: Config) {
        guard !knocks.isEmpty else { return }
        let count = min(knocks.count, 3)
        let surface = gestureSurface
        let peak = knocks.map(\.features.peak).max() ?? 0
        // A lone knock recognised confidently as a surface the user taught is deliberate even
        // when soft (palm rest knocks often are). Otherwise a single must be clearly firm,
        // because one stray bump is the easiest accident to make.
        let taughtAndSure = surface != .anywhere && knocks.allSatisfy { $0.surface == surface && $0.confidence >= 0.5 }
        knocks.removeAll(keepingCapacity: true)
        if count == 1 && peak < c.minPeak * 1.5 && !taughtAndSure {
            onEvent?(.rejected(reason: "light single", features: nil, peak: peak))
            return
        }
        onEvent?(.gesture(count: count, surface: surface, peak: peak))
    }

    private static func since(_ type: CGEventType) -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: type)
    }
}

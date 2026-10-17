import Foundation

/// Tells screen, desk and palm-rest knocks apart using a few example knocks the user
/// recorded on each. Nearest-neighbour over scale-free features: cheap and it adapts to
/// each Mac, desk and hinge.
struct SurfaceClassifier {
    var examples: [Surface: [KnockFeatures]]

    struct Result {
        var surface: Surface
        var confidence: Double   // 0...1
    }

    var isTrained: Bool { examples.values.filter { $0.count >= 3 }.count >= 1 }

    func classify(_ f: KnockFeatures) -> Result {
        let trained = examples.filter { $0.value.count >= 3 }
        guard !trained.isEmpty else { return Result(surface: .anywhere, confidence: 0) }
        let v = f.vector

        // Score each surface by the mean distance to its three closest examples.
        var scores: [(Surface, Float)] = trained.map { surface, list in
            let near = list.map { distance(v, $0.vector) }.sorted().prefix(3)
            return (surface, near.reduce(0, +) / Float(near.count))
        }
        scores.sort { $0.1 < $1.1 }
        let (best, d1) = scores[0]

        // A knock far from everything learned (somewhere new) falls back to Anywhere.
        let limit = max(typicalSpread(for: best) * 4, 1.6)
        if d1 > limit { return Result(surface: .anywhere, confidence: 0) }

        guard scores.count > 1 else {
            // Only one surface learned: accept it when the knock is close to its examples.
            return Result(surface: best, confidence: d1 < limit * 0.75 ? 0.8 : 0.3)
        }
        // How much closer the best surface is than the runner-up.
        let d2 = scores[1].1
        return Result(surface: best, confidence: Double(max(0, 1 - d1 / max(d2, 1e-6))))
    }

    /// Leave-one-out accuracy, shown after training so the user knows if it learned well.
    func selfTestAccuracy() -> Double? {
        let all = examples.flatMap { s, list in list.map { (s, $0) } }
        guard examples.filter({ $0.value.count >= 3 }).count >= 2 else { return nil }
        var right = 0
        for (i, (surface, f)) in all.enumerated() {
            var others = examples
            if var list = others[surface] {
                let idx = all[..<i].filter { $0.0 == surface }.count
                list.remove(at: idx)
                others[surface] = list
            }
            if SurfaceClassifier(examples: others).classify(f).surface == surface { right += 1 }
        }
        return Double(right) / Double(all.count)
    }

    private func typicalSpread(for surface: Surface) -> Float {
        guard let list = examples[surface], list.count >= 2 else { return 0.4 }
        var sum: Float = 0, n: Float = 0
        for i in 0..<list.count {
            var best = Float.greatestFiniteMagnitude
            for j in 0..<list.count where j != i { best = min(best, distance(list[i].vector, list[j].vector)) }
            sum += best; n += 1
        }
        return sum / n
    }

    private func distance(_ a: [Float], _ b: [Float]) -> Float {
        var s: Float = 0
        for i in 0..<min(a.count, b.count) { let d = a[i] - b[i]; s += d * d }
        return s.squareRoot()
    }
}

/// Groups knocks into single / double / triple gestures. Main thread.
final class GestureRecognizer {
    struct Gesture {
        var count: Int
        var surface: Surface
        var source: KnockSource
        var peak: Float
    }

    var gap: TimeInterval = 0.38
    var maxCount: (Surface) -> Int = { _ in 3 }
    var onGesture: ((Gesture) -> Void)?
    /// Called for every knock that joins a gesture (drives combo-style reactions and the HUD).
    var onKnock: ((Int, Surface) -> Void)?

    private var count = 0
    private var votes: [Surface: Int] = [:]
    private var firstSurface: Surface = .anywhere
    private var source: KnockSource = .chassis
    private var lastTime: TimeInterval = 0
    private var firstPeak: Float = 0
    private var maxPeak: Float = 0
    private var pending: DispatchWorkItem?

    /// - Parameters:
    ///   - time: when the knock physically happened (same clock as `Clock.now`).
    func knock(at time: TimeInterval, surface: Surface, source: KnockSource, peak: Float = 0) {
        if count > 0, time - lastTime > gap + 0.05 { fire() }
        // Knocks of one gesture land with similar force; a much weaker or stronger hit is
        // a bump or the lid swinging, so it starts over instead of turning 1 into 2.
        if count > 0, peak > 0, firstPeak > 0, peak < firstPeak * 0.3 || peak > firstPeak * 3.3 {
            fire()
        }
        if count == 0 { firstSurface = surface; votes = [:]; self.source = source; firstPeak = peak; maxPeak = 0 }
        maxPeak = max(maxPeak, peak)
        count += 1
        votes[surface, default: 0] += 1
        lastTime = time
        onKnock?(count, currentSurface)
        pending?.cancel()

        if count >= 3 || count >= maxCount(currentSurface) {
            fire()
            return
        }
        schedule(after: max(0.05, gap - (Clock.now() - time)))
    }

    func cancel() {
        pending?.cancel()
        count = 0
    }

    /// The sensor felt the start of something that may be the next knock of this gesture.
    /// Its verdict takes up to ~0.3 s, so hold the gesture open until then.
    func onsetStarted(at time: TimeInterval) {
        guard count > 0, time - lastTime <= gap + 0.05 else { return }
        schedule(after: 0.35)
    }

    /// That jolt turned out not to be a knock: finish the gesture now if its time is up.
    func onsetRejected() {
        guard count > 0 else { return }
        schedule(after: max(0.02, gap - (Clock.now() - lastTime)))
    }

    private func schedule(after seconds: TimeInterval) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.fire() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private var currentSurface: Surface {
        let ranked = votes.sorted { $0.value == $1.value ? $0.key == firstSurface : $0.value > $1.value }
        // Mixed surfaces in one gesture: trust the first knock.
        if let top = ranked.first, top.key != .anywhere { return votes.count > 1 && top.value == 1 ? firstSurface : top.key }
        return ranked.first?.key ?? firstSurface
    }

    private func fire() {
        pending?.cancel()
        pending = nil
        guard count > 0 else { return }
        let g = Gesture(count: min(count, 3), surface: currentSurface, source: source, peak: maxPeak)
        count = 0
        votes = [:]
        onGesture?(g)
    }
}

enum KnockSource: String {
    case chassis, trackpad, phone
}

enum Clock {
    private static let ticksToSeconds: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()
    /// Same clock as the sensor's HID timestamps.
    static func now() -> TimeInterval { Double(mach_absolute_time()) * ticksToSeconds }
}

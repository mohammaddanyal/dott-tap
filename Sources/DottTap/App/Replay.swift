import Foundation

/// `DottTap --replay <file>` runs a recorded sensor stream through the knock detector and
/// gesture grouping and prints what they find. Used to tune detection without knocking.
/// The file is a sequence of records: Float64 seconds, Float32 x, y, z (g), UInt8 flags.
enum Replay {
    static func run(path: String, calibration: [Surface: [KnockFeatures]]) {
        guard let data = FileManager.default.contents(atPath: path) else { print("can't read", path); return }
        let detector = KnockDetector()
        var tune = DetectorTuning()
        tune.noiseMultiple = KnockFeel.normal.base.multiple
        tune.minPeak = KnockFeel.normal.base.minPeak
        tune.maxPeak = 2.5
        detector.tuning = tune
        let gestures = KnockGestures()
        var config = KnockGestures.Config()
        config.minPeak = tune.minPeak
        config.ignoreTyping = false
        config.classifier = SurfaceClassifier(examples: calibration)
        config.maxCount = Dictionary(uniqueKeysWithValues: Surface.allCases.map { ($0, 3) })
        gestures.config = config

        var t0: Double?
        func rel(_ t: Double) -> String { String(format: "%8.3f", t - (t0 ?? t)) }
        detector.onKnock = { t, f in gestures.knock(at: t, features: f) }
        detector.onReject = { t, reason, peak in print(rel(t), "reject", reason, String(format: "%.3f", peak)) }
        gestures.onEvent = { e in
            switch e {
            case .knock(let k):
                print(rel(k.t), "knock", String(format: "%.3f g", k.features.peak), k.surface.rawValue,
                      String(format: "(guess %@ %.2f) jolt %+.2f %+.2f %+.2f", k.guess.rawValue, k.confidence, k.features.sx, k.features.sy, k.features.sz))
            case .rejected(let reason, _, let peak): print("         reject", reason, String(format: "%.3f", peak))
            case .teach: break
            case .gesture(let count, let surface, let peak):
                print("         GESTURE", count, surface.rawValue, String(format: "%.3f", peak))
            }
        }
        let size = 8 + 4 * 3 + 1
        data.withUnsafeBytes { raw in
            var i = 0
            while i + size <= raw.count {
                let t = raw.loadUnaligned(fromByteOffset: i, as: Double.self)
                let x = raw.loadUnaligned(fromByteOffset: i + 8, as: Float.self)
                let y = raw.loadUnaligned(fromByteOffset: i + 12, as: Float.self)
                let z = raw.loadUnaligned(fromByteOffset: i + 16, as: Float.self)
                if t0 == nil { t0 = t }
                detector.process(t: t, x: x, y: y, z: z)
                gestures.tick(t, capturing: detector.isCapturing)
                i += size
            }
        }
    }
}

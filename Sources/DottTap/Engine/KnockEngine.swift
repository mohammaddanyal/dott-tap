import AppKit
import Combine
import CoreGraphics

struct KnockLog: Identifiable {
    let id = UUID()
    var date = Date()
    var text: String
    var detail: String
    var accepted: Bool
}

/// Wires sensor → detector → surface → gesture → action, and decides when to listen.
@MainActor
final class KnockEngine: ObservableObject {
    static let shared = KnockEngine()
    /// Rendering screenshots: never touch the sensor.
    static var snapshotMode = false

    enum State: Equatable {
        case off
        case listening(Int)
        case paused(String)
        case unsupported
    }

    @Published private(set) var state: State = .off
    @Published private(set) var lastGesture: String = "No knocks yet"
    @Published private(set) var log: [KnockLog] = []
    @Published private(set) var calibrating: Surface?
    @Published private(set) var calibrationCount = 0
    @Published private(set) var pausedUntil: Date?
    @Published private(set) var phoneURLs: [String] = []
    let calibrationTarget = 8

    let sensorSupported = AccelSensor.isSupported
    let detector = KnockDetector()
    private let sensor = AccelSensor()
    private lazy var rates = RateController(sensor: sensor)
    private let recognizer = GestureRecognizer()
    private let store = Store.shared
    private let runner = ActionRunner.shared
    private let reactions = Reactions()
    private let hud = HUD()
    private let power = PowerMonitor()
    private let trackpad = TrackpadTapMode()
    private let phone = PhoneRemote()
    private var classifier = SurfaceClassifier(examples: [:])
    private let events = EventLog()
    private var pauseTimer: Timer?
    private var permissionTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    func start() {
        runner.reactions = reactions
        runner.onPauseRequest = { [weak self] seconds in self?.pause(for: seconds) }

        // Sensor thread: every report goes through the detector; nothing touches the main thread
        // unless a knock-shaped event survives.
        let detector = self.detector
        let rates = self.rates
        sensor.onSample = { t, x, y, z in
            detector.process(t: t, x: x, y: y, z: z)
            rates.tick(t)
        }
        detector.onActivity = { t in rates.activity(t) }
        detector.onOnset = { [weak self] t in
            DispatchQueue.main.async { self?.recognizer.onsetStarted(at: t) }
        }
        detector.onKnock = { [weak self] t, f in
            DispatchQueue.main.async { self?.handleKnock(at: t, features: f) }
        }
        detector.onReject = { [weak self] t, reason, peak in
            DispatchQueue.main.async {
                self?.recognizer.onsetRejected()
                self?.note(String(format: "Ignored (%@)", reason), String(format: "%.3f g", peak), false)
                self?.events.write(["kind": "reject", "reason": reason, "peak": peak], nil)
            }
        }

        recognizer.maxCount = { [weak self] surface in
            guard let self else { return 3 }
            return self.store.maxCount(surface: surface, bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        }
        recognizer.onGesture = { [weak self] g in
            guard let self else { return }
            // One stray bump is the easiest accident, so a lone knock must be clearly firmer
            // than the minimum. Doubles and triples are rare by chance and keep the normal bar.
            if g.count == 1 && g.source == .chassis && g.peak < self.detector.tuning.minPeak * 1.5 {
                self.note("Ignored (light single)", String(format: "%.3f g", g.peak), false)
                self.events.write(["kind": "reject", "reason": "light single", "peak": g.peak], nil)
                return
            }
            self.perform(count: g.count, surface: g.surface, source: g.source)
        }
        recognizer.onKnock = { [weak self] n, _ in
            guard let self, self.store.settings.soundFeedback else { return }
            NSSound(named: n == 1 ? "Tink" : "Pop")?.play()
        }

        trackpad.onTap = { [weak self] in
            self?.recognizer.knock(at: Clock.now(), surface: .anywhere, source: .trackpad)
        }
        phone.onGesture = { [weak self] n, s in self?.perform(count: n, surface: s, source: .phone) }

        power.onChange = { [weak self] in self?.applyPolicy() }
        power.start()
        events.write(["kind": "launch", "accessibility": ActionRunner.hasAccessibility,
                      "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""], nil)

        store.$settings
            .removeDuplicates()
            .sink { [weak self] s in
                // Store publishes in willSet; apply on the next turn so we read the new value.
                DispatchQueue.main.async { self?.apply(s) }
            }
            .store(in: &cancellables)
        store.$calibration
            .sink { [weak self] c in self?.classifier = SurfaceClassifier(examples: c) }
            .store(in: &cancellables)
    }

    // MARK: Settings & power policy

    private func apply(_ s: Settings) {
        let base = s.feel.base
        let scale = Float(pow(2, s.fineTune))
        var tune = DetectorTuning()
        tune.noiseMultiple = base.multiple * scale
        tune.minPeak = base.minPeak * Float(pow(2, s.fineTune * 1.5))
        tune.maxPeak = (s.feel == .slap || s.allowHardHits) ? 100 : 2.5
        detector.tuning = tune
        recognizer.gap = s.gapMs / 1000
        phone.gapMs = Int(s.gapMs)

        permissionTimer?.invalidate()
        permissionTimer = nil
        if s.trackpadMode && ActionRunner.hasAccessibility {
            trackpad.modifier = s.trackpadModifier
            trackpad.start()
        } else {
            trackpad.stop()
            if s.trackpadMode {
                // Start Trackpad Tap Mode as soon as Accessibility is granted.
                permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, ActionRunner.hasAccessibility else { return }
                        self.apply(self.store.settings)
                    }
                }
            }
        }
        if s.phoneRemote {
            if !phone.isRunning || phone.port != s.phonePort || phone.token != s.phoneToken {
                phone.start(port: s.phonePort, token: s.phoneToken)
            }
        } else {
            phone.stop()
        }
        phoneURLs = phone.isRunning ? phone.urls : []
        applyPolicy()
    }

    func applyPolicy() {
        if Self.snapshotMode { state = .listening(200); return }
        let s = store.settings
        let reason: String? = {
            if !s.enabled { return "" }
            if let until = pausedUntil, until > Date() { return "Paused" }
            if power.systemSleeping { return "Mac asleep" }
            if power.screensAsleep { return "Display off" }
            if power.locked { return "Screen locked" }
            if s.pauseOnLowBattery && power.onBattery && power.batteryPercent <= 10 { return "Low battery" }
            return nil
        }()

        guard sensorSupported else {
            state = s.enabled ? .unsupported : .off
            return
        }
        if let reason {
            if sensor.isRunning { sensor.stop(); detector.reset() }
            state = reason.isEmpty ? .off : .paused(reason)
            return
        }
        let mode: PowerMode = power.lowPowerMode && s.powerMode != .precision ? .saver : s.powerMode
        // Live test and surface training want full detail.
        let wantsDetail = detector.monitor.enabled || calibrating != nil
        let r = wantsDetail ? (idle: 800, burst: 800) : mode.rates
        rates.configure(idle: r.idle, burst: r.burst)
        if !sensor.isRunning {
            detector.reset()
            if !sensor.start(rateHz: r.idle) { state = .unsupported; return }
        }
        state = .listening(r.idle)
    }

    func pause(for seconds: TimeInterval) {
        pausedUntil = Date().addingTimeInterval(seconds)
        pauseTimer?.invalidate()
        pauseTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pausedUntil = nil
                self?.applyPolicy()
            }
        }
        applyPolicy()
    }

    func resume() {
        pauseTimer?.invalidate()
        pausedUntil = nil
        applyPolicy()
    }

    func setLiveMonitoring(_ on: Bool) {
        detector.monitor.enabled = on
        applyPolicy()
    }

    // MARK: Knocks

    private func handleKnock(at t: TimeInterval, features f: KnockFeatures) {
        let s = store.settings
        let sinceOnset = Clock.now() - t
        if s.ignoreWhileTyping {
            // Seconds between the last key/click and the knock (negative = it came after).
            let key = min(Self.since(.keyDown), Self.since(.keyUp), Self.since(.flagsChanged)) - sinceOnset
            if key < 0.32 && key > -0.2 { recognizer.onsetRejected(); note("Ignored (typing)", String(format: "%.3f g", f.peak), false); events.write(["kind": "reject", "reason": "typing"], f); return }
        }
        let click = min(Self.since(.leftMouseDown), Self.since(.leftMouseUp), Self.since(.rightMouseDown)) - sinceOnset
        if click < 0.25 && click > -0.15 { recognizer.onsetRejected(); note("Ignored (click)", String(format: "%.3f g", f.peak), false); events.write(["kind": "reject", "reason": "click"], f); return }

        if let surface = calibrating {
            var c = store.calibration
            c[surface, default: []].append(f)
            store.calibration = c
            events.write(["kind": "teach", "surface": surface.rawValue], f)
            calibrationCount += 1
            hud.show(symbol: surface.symbol, title: "\(calibrationCount) of \(calibrationTarget)", subtitle: surface.title)
            if calibrationCount >= calibrationTarget { stopCalibration() }
            return
        }

        let r = classifier.classify(f)
        let surface: Surface = r.confidence >= 0.35 ? r.surface : .anywhere
        note("Knock · \(surface.title)",
             String(format: "%.3f g · %@ %.0f%%", f.peak, r.surface.title, r.confidence * 100), true)
        recognizer.knock(at: t, surface: surface, source: .chassis, peak: f.peak)
        events.write(["kind": "knock", "surface": surface.rawValue, "guess": r.surface.rawValue, "conf": r.confidence], f)
    }

    private func perform(count: Int, surface: Surface, source: KnockSource) {
        let app = NSWorkspace.shared.frontmostApplication
        let spec = store.action(count: count, surface: surface, bundleID: app?.bundleIdentifier) ?? .none
        let name = ["", "Single", "Double", "Triple"][count]
        let place = surface == .anywhere ? (source == .chassis ? "" : " · \(source == .trackpad ? "Trackpad" : "Phone")") : " · \(surface.title)"
        lastGesture = "\(name) knock\(place)"
        events.write(["kind": "gesture", "count": count, "surface": surface.rawValue, "source": source.rawValue, "action": spec.kind.rawValue], nil)
        // Only confirm knocks that did something; a stray bump should stay invisible.
        if store.settings.showHUD && spec.kind != .none && spec.kind.category != .reactions {
            hud.show(symbol: spec.kind.symbol, title: "\(name) knock\(place)", subtitle: spec.summary)
        }
        if spec.kind != .none {
            if spec.kind.needsAccessibility && !ActionRunner.hasAccessibility {
                events.write(["kind": "blocked", "action": spec.kind.rawValue, "reason": "accessibility"], nil)
                hud.show(symbol: "lock.shield", title: "Needs Accessibility", subtitle: "Open Dott Tap settings to allow it")
                return
            }
            runner.run(spec, knockCount: count)
        }
    }

    /// Sample state for screenshots.
    func seedDemo() {
        state = .listening(200)
        lastGesture = "Double knock · Desk"
        classifier = SurfaceClassifier(examples: store.calibration)
        let now = Date()
        let rows: [(String, String, Bool, TimeInterval)] = [
            ("Knock · Screen", "0.240 g · Screen 71%", true, 4),
            ("Ignored (typing)", "0.046 g", false, 9),
            ("Knock · Desk", "0.160 g · Desk 68%", true, 15),
            ("Knock · Desk", "0.190 g · Desk 70%", true, 15.2),
            ("Ignored (light single)", "0.031 g", false, 31),
        ]
        log = rows.map { KnockLog(date: now.addingTimeInterval(-$0.3), text: $0.0, detail: $0.1, accepted: $0.2) }
    }

    /// Lets the settings window test an action without knocking.
    func test(_ spec: ActionSpec) { runner.run(spec) }

    private func note(_ text: String, _ detail: String, _ accepted: Bool) {
        guard detector.monitor.enabled else { return }
        log.insert(KnockLog(text: text, detail: detail, accepted: accepted), at: 0)
        if log.count > 40 { log.removeLast(log.count - 40) }
    }

    private static func since(_ type: CGEventType) -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: type)
    }

    // MARK: Surface training

    func startCalibration(_ surface: Surface) {
        recognizer.cancel()
        var c = store.calibration
        c[surface] = []
        store.calibration = c
        calibrationCount = 0
        calibrating = surface
        applyPolicy()
    }

    func stopCalibration() {
        calibrating = nil
        applyPolicy()
    }

    func forget(_ surface: Surface) {
        var c = store.calibration
        c[surface] = nil
        store.calibration = c
    }

    var trainingAccuracy: Double? { classifier.selfTestAccuracy() }
}

/// Switches the sensor between a low idle rate and a high rate right after movement.
/// Called on the sensor thread.
final class RateController {
    private let sensor: AccelSensor
    private let lock = NSLock()
    private var idle = 200
    private var burst = 800
    private var burstUntil: Double = 0
    private var inBurst = false
    private var lastTypingCheck: Double = 0
    private var typing = false

    init(sensor: AccelSensor) { self.sensor = sensor }

    func configure(idle: Int, burst: Int) {
        lock.lock()
        self.idle = idle
        self.burst = burst
        let rate = inBurst ? burst : idle
        lock.unlock()
        if sensor.isRunning { sensor.setRate(rate) }
    }

    func activity(_ t: Double) {
        lock.lock(); defer { lock.unlock() }
        guard burst != idle else { return }
        // Don't stay at the high rate just because someone is typing.
        if t - lastTypingCheck > 0.15 {
            lastTypingCheck = t
            typing = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown) < 0.6
        }
        if typing { return }
        burstUntil = t + 2.0
        if !inBurst {
            inBurst = true
            sensor.setRate(burst)
        }
    }

    func tick(_ t: Double) {
        guard inBurst else { return }
        lock.lock(); defer { lock.unlock() }
        if inBurst && t > burstUntil {
            inBurst = false
            sensor.setRate(idle)
        }
    }
}

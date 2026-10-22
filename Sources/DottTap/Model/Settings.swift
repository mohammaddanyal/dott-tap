import Foundation
import Combine

enum Surface: String, Codable, CaseIterable, Identifiable {
    case anywhere, screen, desk, body
    var id: String { rawValue }
    var title: String {
        switch self {
        case .anywhere: "Anywhere"
        case .screen: "Screen"
        case .desk: "Desk"
        case .body: "Palm rest"
        }
    }
    var symbol: String {
        switch self {
        case .anywhere: "hand.tap"
        case .screen: "macbook"
        case .desk: "table.furniture"
        case .body: "keyboard"
        }
    }
    var hint: String {
        switch self {
        case .anywhere: ""
        case .screen: "Knock on the top edge or back of the lid."
        case .desk: "Knock on the desk 10–20 cm beside the Mac."
        case .body: "Knock on the palm rest, away from the keys."
        }
    }
    static let learnable: [Surface] = [.screen, .desk, .body]
}

enum KnockFeel: String, Codable, CaseIterable, Identifiable {
    case gentle, normal, firm, slap
    var id: String { rawValue }
    var title: String {
        switch self {
        case .gentle: "Gentle tap"
        case .normal: "Normal knock"
        case .firm: "Firm knock"
        case .slap: "Slap"
        }
    }
    /// Base noise multiple and minimum peak (g) for each feel.
    var base: (multiple: Float, minPeak: Float) {
        switch self {
        case .gentle: (6, 0.02)
        case .normal: (8, 0.04)
        case .firm: (10, 0.07)
        case .slap: (14, 0.15)
        }
    }
}

enum PowerMode: String, Codable, CaseIterable, Identifiable {
    case saver, balanced, precision
    var id: String { rawValue }
    var title: String {
        switch self {
        case .saver: "Battery saver"
        case .balanced: "Balanced"
        case .precision: "Precision"
        }
    }
    var detail: String {
        switch self {
        case .saver: "Listens at 100 Hz, 400 Hz after a knock. Lowest power, softest taps may be missed."
        case .balanced: "Listens at 200 Hz, 800 Hz right after a knock. Best for most people."
        case .precision: "800 Hz all the time. Most accurate surface detection, uses a bit more power."
        }
    }
    /// (idle, burst) sample rates
    var rates: (idle: Int, burst: Int) {
        switch self {
        case .saver: (100, 400)
        case .balanced: (200, 800)
        case .precision: (800, 800)
        }
    }
}

enum TrackpadModifier: String, Codable, CaseIterable, Identifiable {
    case fn, controlOption, commandOption, rightOption
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fn: "fn / 🌐"
        case .controlOption: "⌃ Control + ⌥ Option"
        case .commandOption: "⌘ Command + ⌥ Option"
        case .rightOption: "⌥ Right Option"
        }
    }
}

struct BindingKey: Hashable, Codable, CustomStringConvertible {
    var surface: Surface
    var count: Int
    var description: String { "\(surface.rawValue).\(count)" }
    init(_ surface: Surface, _ count: Int) { self.surface = surface; self.count = count }
    init?(string: String) {
        let parts = string.split(separator: ".")
        guard parts.count == 2, let s = Surface(rawValue: String(parts[0])), let c = Int(parts[1]) else { return nil }
        surface = s; count = c
    }
}

struct Bindings: Codable, Hashable {
    var map: [String: ActionSpec] = [:]
    subscript(_ key: BindingKey) -> ActionSpec? {
        get { map[key.description] }
        set { map[key.description] = newValue }
    }
}

struct AppProfile: Codable, Hashable, Identifiable {
    var bundleID: String
    var name: String
    var path: String
    var bindings = Bindings()
    var id: String { bundleID }
}

struct Settings: Codable, Equatable {
    var enabled = true
    var feel: KnockFeel = .normal
    var fineTune: Double = 0            // -1 (more sensitive) ... 1 (less)
    var gapMs: Double = 450             // max pause between knocks of one gesture
    var powerMode: PowerMode = .balanced
    var pauseOnLowBattery = true
    var ignoreWhileTyping = true
    var allowHardHits = false
    var soundFeedback = false
    var showHUD = true
    var trackpadMode = false
    var trackpadModifier: TrackpadModifier = .fn
    var phoneRemote = false
    var phonePort: UInt16 = 8787
    var phoneToken = String(UUID().uuidString.prefix(8)).lowercased()
    var onboarded = false
    var bindings = Bindings.defaults
    var apps: [AppProfile] = []
    var swipesEnabled = true
    /// Set once Dott Tap has added itself to Login Items, so turning it off later sticks.
    var openAtLoginDefaulted = false
    /// Disk images to open whenever their drive is connected.
    var autoOpenImages = true
    var diskImages: [DiskImageEntry] = []
    /// Set once the list was filled from images that were already open.
    var diskImagesSeeded = false
    /// Four-finger swipe actions, keyed by direction ("down", "up", "left", "right").
    var swipes: [String: ActionSpec] = [
        SwipeDirection.down.rawValue: ActionSpec(kind: .minimizeAll),
        SwipeDirection.up.rawValue: ActionSpec(kind: .restoreWindows),
    ]
}

extension Settings {
    /// Reads saved settings field by field, so a setting added in a newer version takes its
    /// default instead of making the whole file unreadable (which would reset everything).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        enabled = v(.enabled, d.enabled)
        feel = v(.feel, d.feel)
        fineTune = v(.fineTune, d.fineTune)
        gapMs = v(.gapMs, d.gapMs)
        powerMode = v(.powerMode, d.powerMode)
        pauseOnLowBattery = v(.pauseOnLowBattery, d.pauseOnLowBattery)
        ignoreWhileTyping = v(.ignoreWhileTyping, d.ignoreWhileTyping)
        allowHardHits = v(.allowHardHits, d.allowHardHits)
        soundFeedback = v(.soundFeedback, d.soundFeedback)
        showHUD = v(.showHUD, d.showHUD)
        trackpadMode = v(.trackpadMode, d.trackpadMode)
        trackpadModifier = v(.trackpadModifier, d.trackpadModifier)
        phoneRemote = v(.phoneRemote, d.phoneRemote)
        phonePort = v(.phonePort, d.phonePort)
        phoneToken = v(.phoneToken, d.phoneToken)
        onboarded = v(.onboarded, d.onboarded)
        bindings = v(.bindings, d.bindings)
        apps = v(.apps, d.apps)
        swipesEnabled = v(.swipesEnabled, d.swipesEnabled)
        swipes = v(.swipes, d.swipes)
        openAtLoginDefaulted = v(.openAtLoginDefaulted, d.openAtLoginDefaulted)
        autoOpenImages = v(.autoOpenImages, d.autoOpenImages)
        diskImages = v(.diskImages, d.diskImages)
        diskImagesSeeded = v(.diskImagesSeeded, d.diskImagesSeeded)
    }
}

extension Bindings {
    static var defaults: Bindings {
        var b = Bindings()
        b[BindingKey(.anywhere, 1)] = ActionSpec(kind: .none)
        b[BindingKey(.anywhere, 2)] = ActionSpec(kind: .playPause)
        b[BindingKey(.anywhere, 3)] = ActionSpec(kind: .missionControl)
        return b
    }
}

/// Persists settings and calibration to ~/Library/Application Support/Dott Tap.
final class Store: ObservableObject {
    static let shared = Store()

    @Published var settings: Settings { didSet { if settings != oldValue { scheduleSave() } } }
    @Published var calibration: [Surface: [KnockFeatures]] { didSet { saveCalibration() } }

    private let dir: URL
    private var saveWork: DispatchWorkItem?
    /// Set while rendering screenshots so demo settings never overwrite the real ones.
    var readOnly = false

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("Dott Tap", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dec = JSONDecoder()
        settings = (try? dec.decode(Settings.self, from: Data(contentsOf: dir.appendingPathComponent("settings.json")))) ?? Settings()
        let raw = (try? dec.decode([String: [KnockFeatures]].self, from: Data(contentsOf: dir.appendingPathComponent("surfaces.json")))) ?? [:]
        calibration = Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in Surface(rawValue: k).map { ($0, v) } })
    }

    private func scheduleSave() {
        guard !readOnly else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? enc.encode(self.settings).write(to: self.dir.appendingPathComponent("settings.json"), options: .atomic)
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func saveCalibration() {
        guard !readOnly else { return }
        let raw = Dictionary(uniqueKeysWithValues: calibration.map { ($0.key.rawValue, $0.value) })
        try? JSONEncoder().encode(raw).write(to: dir.appendingPathComponent("surfaces.json"), options: .atomic)
    }

    var learnedSurfaces: [Surface] {
        Surface.learnable.filter { (calibration[$0]?.count ?? 0) >= 3 }
    }

    // MARK: Binding resolution

    /// Action for a gesture: app profile first, then global; exact surface first, then Anywhere.
    func action(count: Int, surface: Surface, bundleID: String?) -> ActionSpec? {
        let layers: [Bindings] = [settings.apps.first { $0.bundleID == bundleID }?.bindings, settings.bindings].compactMap { $0 }
        for layer in layers {
            if surface != .anywhere, let a = layer[BindingKey(surface, count)] { return a }
            if let a = layer[BindingKey(.anywhere, count)] { return a }
        }
        return nil
    }

    /// Highest knock count that does something for this surface/app. Lets single knocks fire
    /// instantly when nothing longer is configured.
    func maxCount(surface: Surface, bundleID: String?) -> Int {
        for c in stride(from: 3, through: 1, by: -1) {
            if let a = action(count: c, surface: surface, bundleID: bundleID), a.kind != .none { return c }
            if surface == .anywhere {
                for s in learnedSurfaces {
                    if let a = action(count: c, surface: s, bundleID: bundleID), a.kind != .none { return c }
                }
            }
        }
        return 1
    }
}

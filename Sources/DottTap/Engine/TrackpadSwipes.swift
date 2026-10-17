import Foundation

enum SwipeDirection: String, Codable, CaseIterable, Identifiable {
    case down, up, left, right
    var id: String { rawValue }
    var title: String {
        switch self {
        case .down: "Swipe down"
        case .up: "Swipe up"
        case .left: "Swipe left"
        case .right: "Swipe right"
        }
    }
    var symbol: String {
        switch self {
        case .down: "arrow.down"
        case .up: "arrow.up"
        case .left: "arrow.left"
        case .right: "arrow.right"
        }
    }
}

/// Four-finger swipes on the trackpad. macOS has no public API for raw touches, so this
/// reads them from the MultitouchSupport framework the way trackpad utilities do. Frames
/// only arrive while fingers are on the trackpad, so it costs nothing when idle.
final class TrackpadSwipes {
    /// Called on the main thread.
    var onSwipe: ((Int, SwipeDirection) -> Void)?

    /// Fingers a gesture needs. Only four-finger swipes are used for now.
    var fingers = 4
    /// Travel needed, as a share of the trackpad (0...1).
    var distance: Float = 0.12

    private typealias Device = UnsafeMutableRawPointer
    private typealias FrameCallback = @convention(c) (Int32, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

    private var devices: [AnyObject] = []
    private var running = false
    /// Touch frames seen since start; tells whether macOS lets the app read the trackpad.
    private(set) var framesSeen = 0
    /// When fingers were last on the trackpad (`Clock` seconds). Fingers landing on the
    /// trackpad jolt the Mac like a knock, so knocks near this time are ignored.
    static var lastTouch: Double = -10

    // Gesture state (multitouch thread)
    private var tracking = false
    private var startX: Float = 0, startY: Float = 0
    private var fired = false
    private var lastCount = 0

    /// Only one swipe recogniser can own the C callback, which has no context pointer.
    private static weak var current: TrackpadSwipes?
    /// One function for register and unregister, so unregistering finds it.
    private static let callback: FrameCallback = { _, touches, count, _, _ in
        TrackpadSwipes.current?.frame(touches, Int(count))
        return 0
    }

    private static let framework: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)

    private static func symbol<T>(_ name: String, as: T.Type) -> T? {
        guard let framework, let s = dlsym(framework, name) else { return nil }
        return unsafeBitCast(s, to: T.self)
    }

    static var isAvailable: Bool { framework != nil && dlsym(framework, "MTDeviceCreateList") != nil }

    var isRunning: Bool { running }

    func start() {
        guard !running,
              let createList = Self.symbol("MTDeviceCreateList", as: (@convention(c) () -> Unmanaged<CFArray>?).self),
              let register = Self.symbol("MTRegisterContactFrameCallback", as: (@convention(c) (Device, FrameCallback) -> Void).self),
              let startDevice = Self.symbol("MTDeviceStart", as: (@convention(c) (Device, Int32) -> Int32).self),
              let list = createList()?.takeRetainedValue() as [AnyObject]?
        else { return }
        Self.current = self
        devices = list
        for d in list {
            let dev = Unmanaged.passUnretained(d).toOpaque()
            register(dev, Self.callback)
            _ = startDevice(dev, 0)
        }
        running = true
    }

    func stop() {
        guard running else { return }
        if let unregister = Self.symbol("MTUnregisterContactFrameCallback", as: (@convention(c) (Device, FrameCallback) -> Void).self),
           let stopDevice = Self.symbol("MTDeviceStop", as: (@convention(c) (Device) -> Void).self) {
            for d in devices {
                let dev = Unmanaged.passUnretained(d).toOpaque()
                unregister(dev, Self.callback)
                stopDevice(dev)
            }
        }
        devices = []
        running = false
        if Self.current === self { Self.current = nil }
    }

    // Touch records are 96 bytes; normalized position (0...1, y up) sits at offset 32.
    private static let stride = 96

    private func frame(_ touches: UnsafeMutableRawPointer?, _ count: Int) {
        framesSeen &+= 1
        Self.lastTouch = Clock.now()
        guard let touches, count > 0 else {
            tracking = false
            fired = false
            lastCount = 0
            return
        }
        var sx: Float = 0, sy: Float = 0
        for i in 0..<count {
            sx += touches.loadUnaligned(fromByteOffset: i * Self.stride + 32, as: Float.self)
            sy += touches.loadUnaligned(fromByteOffset: i * Self.stride + 36, as: Float.self)
        }
        let x = sx / Float(count), y = sy / Float(count)

        if count != lastCount {
            // Finger count changed: restart from here (fingers rarely land at the same moment).
            lastCount = count
            tracking = count == fingers
            startX = x; startY = y
            return
        }
        guard tracking, !fired else { return }
        let dx = x - startX, dy = y - startY
        let dir: SwipeDirection?
        if abs(dy) > distance && abs(dy) > abs(dx) * 1.5 {
            dir = dy < 0 ? .down : .up
        } else if abs(dx) > distance && abs(dx) > abs(dy) * 1.5 {
            dir = dx < 0 ? .left : .right
        } else {
            dir = nil
        }
        if let dir {
            fired = true   // one action per swipe, until the fingers lift
            let n = count
            DispatchQueue.main.async { [weak self] in self?.onSwipe?(n, dir) }
        }
    }

    /// What macOS itself does with four-finger swipes, from the Trackpad settings.
    static var systemUsesFourFingerVertical: Bool {
        (CFPreferencesCopyAppValue("TrackpadFourFingerVertSwipeGesture" as CFString,
                                   "com.apple.AppleMultitouchTrackpad" as CFString) as? Int ?? 2) != 0
    }
    static var systemUsesFourFingerHorizontal: Bool {
        (CFPreferencesCopyAppValue("TrackpadFourFingerHorizSwipeGesture" as CFString,
                                   "com.apple.AppleMultitouchTrackpad" as CFString) as? Int ?? 2) != 0
    }
}

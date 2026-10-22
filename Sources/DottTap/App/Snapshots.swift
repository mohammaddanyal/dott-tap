import AppKit
import SwiftUI

/// `DottTap --snapshots <folder>` renders the menu and settings pages to PNG files for
/// the README and website, using demo settings. Nothing is saved and the sensor stays off.
@MainActor
enum Snapshots {
    static func run(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = Store.shared
        let engine = KnockEngine.shared
        store.readOnly = true
        KnockEngine.snapshotMode = true
        store.settings = demoSettings(base: store.settings)
        engine.seedDemo()
        seedWaveform(engine.detector.monitor)

        let nav = SettingsWindow.shared.nav
        let pages: [(SettingsPage, String)] = [(.gestures, "gestures"), (.swipes, "swipes"), (.drives, "drives"), (.surfaces, "surfaces"), (.test, "test"),
                                               (.general, "general"), (.remote, "remote")]
        for (name, mode) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            for (page, file) in pages {
                nav.page = page
                let view = SettingsView().environmentObject(store).environmentObject(engine).environmentObject(nav)
                    .frame(width: 900, height: 600)
                capture(view, size: CGSize(width: 900, height: 600), appearance: mode, to: dir.appendingPathComponent("settings-\(file)-\(name).png"))
            }
            let menu = MenuBarView().environmentObject(store).environmentObject(engine)
                .background(Color(nsColor: .windowBackgroundColor))
            capture(menu, size: CGSize(width: 300, height: 318), appearance: mode, to: dir.appendingPathComponent("menu-\(name).png"), titled: false)
        }
    }

    private static func capture<V: View>(_ view: V, size: CGSize, appearance: NSAppearance.Name, to url: URL, titled: Bool = true) {
        let host = NSHostingView(rootView: view)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2, width: size.width, height: size.height)
        let style: NSWindow.StyleMask = titled ? [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView] : [.borderless]
        let window = NSWindow(contentRect: frame, styleMask: style, backing: .buffered, defer: false)
        window.title = "Dott Tap"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        window.setContentSize(size)
        // In front but parked almost entirely past the right edge of the screen: macOS treats it
        // as visible (so live views draw), yet only a few pixels show. The capture reads the
        // window's own backing store, so the off-screen part comes out complete.
        let full = NSScreen.main?.frame ?? frame
        window.setFrameOrigin(NSPoint(x: full.maxX - 4, y: full.midY - size.height / 2))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))

        // The window server can hand an app its own windows without screen-recording access.
        var image: CGImage?
        if let fn = windowImage {
            image = fn(.null, 1 << 3, CGWindowID(window.windowNumber), (1 << 0) | (1 << 3))?.takeRetainedValue()
        }
        if let image {
            let rep = NSBitmapImageRep(cgImage: image)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            print("wrote", url.lastPathComponent, image.width, "x", image.height)
        } else {
            print("could not capture", url.lastPathComponent)
        }
        window.orderOut(nil)
    }

    /// CGWindowListCreateImage is hidden from the Swift SDK but still present at runtime.
    private typealias WindowImageFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    private static let windowImage: WindowImageFn? = {
        guard let h = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
              let sym = dlsym(h, "CGWindowListCreateImage") else { return nil }
        return unsafeBitCast(sym, to: WindowImageFn.self)
    }()

    private static func demoSettings(base: Settings) -> Settings {
        var s = base
        s.enabled = true
        s.feel = .normal
        s.trackpadMode = true
        s.phoneRemote = false
        var b = Bindings()
        b[BindingKey(.anywhere, 1)] = ActionSpec(kind: .playPause)
        b[BindingKey(.anywhere, 2)] = ActionSpec(kind: .screenshotArea)
        b[BindingKey(.anywhere, 3)] = ActionSpec(kind: .lockScreen)
        b[BindingKey(.screen, 1)] = ActionSpec(kind: .showDesktop)
        b[BindingKey(.screen, 2)] = ActionSpec(kind: .missionControl)
        b[BindingKey(.screen, 3)] = ActionSpec(kind: .reactConfetti)
        b[BindingKey(.desk, 1)] = ActionSpec(kind: .nextTrack)
        b[BindingKey(.desk, 2)] = ActionSpec(kind: .spotlight)
        b[BindingKey(.desk, 3)] = ActionSpec(kind: .reactBlackHole)
        s.bindings = b
        return s
    }

    /// A believable trace: quiet noise, a double knock and a single knock.
    private static func seedWaveform(_ m: LevelMonitor) {
        m.enabled = true
        var rng = SystemRandomNumberGenerator()
        let knocks: [(Int, Float)] = [(420, 0.19), (560, 0.16), (1180, 0.24)]
        for i in 0..<LevelMonitor.size {
            var v = Float.random(in: 0.002...0.006, using: &rng)
            for (at, peak) in knocks where i >= at && i < at + 90 {
                let k = Float(i - at)
                v += peak * exp(-k / 14) * abs(cos(k * 0.9))
            }
            m.push(v)
        }
    }
}

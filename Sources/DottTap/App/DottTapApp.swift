import AppKit
import SwiftUI

@main
struct DottTapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = Store.shared
    @StateObject private var engine = KnockEngine.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
                .environmentObject(engine)
        } label: {
            Image(systemName: menuSymbol)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuSymbol: String {
        switch engine.state {
        case .listening: "hand.tap.fill"
        case .paused: "hand.tap"
        case .off: "hand.raised.slash"
        case .unsupported: store.settings.trackpadMode || store.settings.phoneRemote ? "hand.tap" : "hand.raised.slash"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "--snapshots") {
                let dir = i + 1 < args.count ? args[i + 1] : "snapshots"
                Snapshots.run(to: URL(fileURLWithPath: dir))
                exit(0)
            }
            KnockEngine.shared.start()
            if !Store.shared.settings.onboarded {
                SettingsWindow.shared.show(page: .welcome)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { SettingsWindow.shared.show() }
        return true
    }
}

/// Plain AppKit window hosting the SwiftUI settings, so it can be opened from anywhere.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private var window: NSWindow?
    let nav = SettingsNavigation()

    func show(page: SettingsPage? = nil) {
        if let page { nav.page = page }
        if window == nil {
            let host = NSHostingController(rootView: SettingsView()
                .environmentObject(Store.shared)
                .environmentObject(KnockEngine.shared)
                .environmentObject(nav))
            let w = NSWindow(contentViewController: host)
            w.title = "Dott Tap"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.toolbarStyle = .unified
            w.setContentSize(NSSize(width: 820, height: 580))
            w.minSize = NSSize(width: 720, height: 500)
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Back to a pure menu bar app; the window's SwiftUI tree stops updating too.
        NSApp.setActivationPolicy(.accessory)
        KnockEngine.shared.setLiveMonitoring(false)
        if KnockEngine.shared.calibrating != nil { KnockEngine.shared.stopCalibration() }
    }
}

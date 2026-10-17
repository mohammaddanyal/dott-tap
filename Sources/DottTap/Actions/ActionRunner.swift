import AppKit
import ApplicationServices
import CoreGraphics

/// Performs actions. Keystrokes and media keys need Accessibility permission; everything
/// else uses public APIs or built-in command-line tools.
@MainActor
final class ActionRunner {
    static let shared = ActionRunner()

    var reactions: Reactions?
    var onPauseRequest: ((TimeInterval) -> Void)?
    private var previousApp: NSRunningApplication?
    private var appObserver: NSObjectProtocol?

    init() {
        // Remember the app used before the current one for "Switch to last app".
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                if app?.bundleIdentifier != Bundle.main.bundleIdentifier { self?.previousApp = app }
            }
        }
    }

    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func run(_ spec: ActionSpec, knockCount: Int = 1) {
        switch spec.kind {
        case .none: break

        // Media
        case .playPause: MediaKey.press(.play)
        case .nextTrack: MediaKey.press(.next)
        case .previousTrack: MediaKey.press(.previous)
        case .volumeUp: MediaKey.press(.soundUp)
        case .volumeDown: MediaKey.press(.soundDown)
        case .mute: MediaKey.press(.mute)
        case .brightnessUp: MediaKey.press(.brightnessUp)
        case .brightnessDown: MediaKey.press(.brightnessDown)

        // System
        case .lockScreen: lockScreen()
        case .sleepDisplay: shell("/usr/bin/pmset", ["displaysleepnow"])
        case .sleepMac: shell("/usr/bin/pmset", ["sleepnow"])
        case .screenSaver: openApp(path: "/System/Library/CoreServices/ScreenSaverEngine.app")
        case .toggleDarkMode:
            appleScript("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
        case .spotlight: Keys.press(Keys.space, [.maskCommand])
        case .toggleKnocking: onPauseRequest?(600)

        // Windows & desktops
        case .missionControl: openApp(path: "/System/Applications/Mission Control.app")
        case .showDesktop: shell("/System/Applications/Mission Control.app/Contents/MacOS/Mission Control", ["1"])
        case .appLauncher:
            if FileManager.default.fileExists(atPath: "/System/Applications/Apps.app") {
                openApp(path: "/System/Applications/Apps.app")
            } else {
                openApp(path: "/System/Applications/Launchpad.app")
            }
        case .spaceLeft: Keys.press(Keys.left, [.maskControl])
        case .spaceRight: Keys.press(Keys.right, [.maskControl])
        case .nextTab: Keys.press(Keys.tab, [.maskControl])
        case .previousTab: Keys.press(Keys.tab, [.maskControl, .maskShift])
        case .newTab: Keys.press(Keys.t, [.maskCommand])
        case .closeTab: Keys.press(Keys.w, [.maskCommand])
        case .minimizeWindow: Keys.press(Keys.m, [.maskCommand])
        case .fullScreen: Keys.press(Keys.f, [.maskCommand, .maskControl])
        case .hideApp: NSWorkspace.shared.frontmostApplication?.hide()
        case .quitApp:
            if let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != "com.apple.finder" { app.terminate() }
        case .switchApp: previousApp?.activate()

        // Editing
        case .copy: Keys.press(Keys.c, [.maskCommand])
        case .paste: Keys.press(Keys.v, [.maskCommand])
        case .cut: Keys.press(Keys.x, [.maskCommand])
        case .undo: Keys.press(Keys.z, [.maskCommand])
        case .redo: Keys.press(Keys.z, [.maskCommand, .maskShift])
        case .selectAll: Keys.press(Keys.a, [.maskCommand])
        case .save: Keys.press(Keys.s, [.maskCommand])

        // Screenshots: the system's own shortcuts, so they save where the user chose.
        case .screenshotFull: Keys.press(Keys.three, [.maskCommand, .maskShift])
        case .screenshotArea: Keys.press(Keys.four, [.maskCommand, .maskShift])
        case .screenshotTool: Keys.press(Keys.five, [.maskCommand, .maskShift])

        // Automation
        case .keyboardShortcut:
            if let c = spec.combo { Keys.press(CGKeyCode(c.keyCode), CGEventFlags(rawValue: c.modifiers)) }
        case .typeText: Keys.type(spec.text)
        case .openApp: if !spec.appPath.isEmpty { openApp(path: spec.appPath) }
        case .openURL:
            var s = spec.text.trimmingCharacters(in: .whitespaces)
            if !s.contains("://") { s = "https://" + s }
            if let url = URL(string: s) { NSWorkspace.shared.open(url) }
        case .runShortcut: if !spec.text.isEmpty { shell("/usr/bin/shortcuts", ["run", spec.text]) }
        case .shellCommand: if !spec.text.isEmpty { shell("/bin/zsh", ["-lc", spec.text]) }
        case .appleScript: if !spec.text.isEmpty { appleScript(spec.text) }

        // Reactions
        case .reactFlash, .reactShockwave, .reactGlitch, .reactText, .reactConfetti,
             .reactBall, .reactCombo, .reactStack, .reactBlackHole, .reactRandom:
            reactions?.play(spec.kind, text: spec.text, knockCount: knockCount)
        }
    }

    // MARK: Helpers

    private func lockScreen() {
        // Same call the Control Centre "Lock Screen" item uses.
        typealias LockFn = @convention(c) () -> Void
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
           let sym = dlsym(handle, "SACLockScreenImmediate") {
            unsafeBitCast(sym, to: LockFn.self)()
            return
        }
        Keys.press(Keys.q, [.maskCommand, .maskControl])
    }

    private func openApp(path: String) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: config)
    }

    private func shell(_ tool: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    private func appleScript(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
        }
    }
}

enum Keys {
    static let a: CGKeyCode = 0, s: CGKeyCode = 1, f: CGKeyCode = 3, z: CGKeyCode = 6, x: CGKeyCode = 7,
               c: CGKeyCode = 8, v: CGKeyCode = 9, q: CGKeyCode = 12, w: CGKeyCode = 13, t: CGKeyCode = 17,
               three: CGKeyCode = 20, four: CGKeyCode = 21, five: CGKeyCode = 23, m: CGKeyCode = 46,
               tab: CGKeyCode = 48, space: CGKeyCode = 49, left: CGKeyCode = 123, right: CGKeyCode = 124

    static func press(_ key: CGKeyCode, _ flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        // Arrow keys carry the function/numpad flags when typed on a real keyboard.
        var f = flags
        if key >= 123 && key <= 126 { f.insert(.maskSecondaryFn); f.insert(.maskNumericPad) }
        let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
        down?.flags = f
        up?.flags = f
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    static func type(_ text: String) {
        let src = CGEventSource(stateID: .hidSystemState)
        for chunk in text.chunked(20) {
            let utf16 = Array(chunk.utf16)
            let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
            let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
            down?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            up?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }
}

/// The hardware media keys (F7–F12 row), posted as system-defined events.
enum MediaKey: Int32 {
    case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7,
         play = 16, next = 17, previous = 18

    static func press(_ key: MediaKey) {
        func post(down: Bool) {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = Int((key.rawValue << 16) | ((down ? 0xA : 0xB) << 8))
            let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                                           timestamp: 0, windowNumber: 0, context: nil,
                                           subtype: 8, data1: data1, data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
        post(down: true)
        post(down: false)
    }
}

private extension String {
    func chunked(_ size: Int) -> [String] {
        var out: [String] = []
        var current = ""
        for ch in self {
            current.append(ch)
            if current.count == size { out.append(current); current = "" }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}

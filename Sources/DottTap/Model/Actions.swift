import Foundation

enum ActionCategory: String, CaseIterable, Identifiable {
    case media = "Media"
    case system = "System"
    case windows = "Windows & Desktops"
    case editing = "Editing"
    case capture = "Screenshots"
    case automation = "Automation"
    case reactions = "Reactions"
    var id: String { rawValue }
}

enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case none

    // Media
    case playPause, nextTrack, previousTrack, volumeUp, volumeDown, mute
    // System
    case lockScreen, sleepDisplay, sleepMac, screenSaver, brightnessUp, brightnessDown,
         toggleDarkMode, spotlight, toggleKnocking
    // Windows & desktops
    case missionControl, showDesktop, appLauncher, spaceLeft, spaceRight,
         nextTab, previousTab, newTab, closeTab, minimizeWindow, fullScreen, hideApp, quitApp, switchApp
    // Editing
    case copy, paste, cut, undo, redo, selectAll, save
    // Screenshots
    case screenshotFull, screenshotArea, screenshotTool
    // Automation
    case keyboardShortcut, typeText, openApp, openURL, runShortcut, shellCommand, appleScript
    // Reactions
    case reactFlash, reactShockwave, reactGlitch, reactText, reactConfetti,
         reactBall, reactCombo, reactStack, reactBlackHole, reactRandom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Do nothing"
        case .playPause: "Play / Pause"
        case .nextTrack: "Next track"
        case .previousTrack: "Previous track"
        case .volumeUp: "Volume up"
        case .volumeDown: "Volume down"
        case .mute: "Mute / Unmute"
        case .lockScreen: "Lock screen"
        case .sleepDisplay: "Turn display off"
        case .sleepMac: "Sleep Mac"
        case .screenSaver: "Start screen saver"
        case .brightnessUp: "Brightness up"
        case .brightnessDown: "Brightness down"
        case .toggleDarkMode: "Dark / Light mode"
        case .spotlight: "Spotlight"
        case .toggleKnocking: "Pause knocks for 10 min"
        case .missionControl: "Mission Control"
        case .showDesktop: "Show desktop"
        case .appLauncher: "Apps launcher"
        case .spaceLeft: "Desktop to the left"
        case .spaceRight: "Desktop to the right"
        case .nextTab: "Next tab"
        case .previousTab: "Previous tab"
        case .newTab: "New tab"
        case .closeTab: "Close tab / window"
        case .minimizeWindow: "Minimise window"
        case .fullScreen: "Full screen"
        case .hideApp: "Hide app"
        case .quitApp: "Quit app"
        case .switchApp: "Switch to last app"
        case .copy: "Copy"
        case .paste: "Paste"
        case .cut: "Cut"
        case .undo: "Undo"
        case .redo: "Redo"
        case .selectAll: "Select all"
        case .save: "Save"
        case .screenshotFull: "Screenshot"
        case .screenshotArea: "Screenshot of an area"
        case .screenshotTool: "Screenshot toolbar"
        case .keyboardShortcut: "Press a shortcut…"
        case .typeText: "Type text…"
        case .openApp: "Open app…"
        case .openURL: "Open website…"
        case .runShortcut: "Run Shortcut…"
        case .shellCommand: "Run command…"
        case .appleScript: "Run AppleScript…"
        case .reactFlash: "Screen flash"
        case .reactShockwave: "Shockwave"
        case .reactGlitch: "Glitch"
        case .reactText: "Show text…"
        case .reactConfetti: "Confetti"
        case .reactBall: "Bouncing ball"
        case .reactCombo: "Combo counter"
        case .reactStack: "Gravity stack"
        case .reactBlackHole: "Black hole"
        case .reactRandom: "Random reaction"
        }
    }

    var symbol: String {
        switch self {
        case .none: "circle.slash"
        case .playPause: "playpause.fill"
        case .nextTrack: "forward.fill"
        case .previousTrack: "backward.fill"
        case .volumeUp: "speaker.wave.3.fill"
        case .volumeDown: "speaker.wave.1.fill"
        case .mute: "speaker.slash.fill"
        case .lockScreen: "lock.fill"
        case .sleepDisplay: "display"
        case .sleepMac: "moon.fill"
        case .screenSaver: "sparkles.tv"
        case .brightnessUp: "sun.max.fill"
        case .brightnessDown: "sun.min.fill"
        case .toggleDarkMode: "circle.lefthalf.filled"
        case .spotlight: "magnifyingglass"
        case .toggleKnocking: "pause.circle"
        case .missionControl: "rectangle.3.group"
        case .showDesktop: "menubar.dock.rectangle"
        case .appLauncher: "square.grid.3x3.fill"
        case .spaceLeft: "arrow.left.square"
        case .spaceRight: "arrow.right.square"
        case .nextTab: "arrow.right.to.line"
        case .previousTab: "arrow.left.to.line"
        case .newTab: "plus.square.on.square"
        case .closeTab: "xmark.square"
        case .minimizeWindow: "minus.square"
        case .fullScreen: "arrow.up.left.and.arrow.down.right"
        case .hideApp: "eye.slash"
        case .quitApp: "power"
        case .switchApp: "arrow.left.arrow.right"
        case .copy: "doc.on.doc"
        case .paste: "doc.on.clipboard"
        case .cut: "scissors"
        case .undo: "arrow.uturn.backward"
        case .redo: "arrow.uturn.forward"
        case .selectAll: "selection.pin.in.out"
        case .save: "square.and.arrow.down"
        case .screenshotFull: "camera.viewfinder"
        case .screenshotArea: "crop"
        case .screenshotTool: "camera.on.rectangle"
        case .keyboardShortcut: "command"
        case .typeText: "keyboard"
        case .openApp: "app.badge"
        case .openURL: "safari"
        case .runShortcut: "square.stack.3d.up.fill"
        case .shellCommand: "terminal"
        case .appleScript: "applescript"
        case .reactFlash: "bolt.fill"
        case .reactShockwave: "dot.radiowaves.left.and.right"
        case .reactGlitch: "waveform.path.ecg"
        case .reactText: "textformat"
        case .reactConfetti: "party.popper"
        case .reactBall: "circle.circle"
        case .reactCombo: "flame.fill"
        case .reactStack: "square.stack.fill"
        case .reactBlackHole: "hurricane"
        case .reactRandom: "dice.fill"
        }
    }

    var category: ActionCategory? {
        switch self {
        case .none: nil
        case .playPause, .nextTrack, .previousTrack, .volumeUp, .volumeDown, .mute: .media
        case .lockScreen, .sleepDisplay, .sleepMac, .screenSaver, .brightnessUp, .brightnessDown,
             .toggleDarkMode, .spotlight, .toggleKnocking: .system
        case .missionControl, .showDesktop, .appLauncher, .spaceLeft, .spaceRight, .nextTab, .previousTab,
             .newTab, .closeTab, .minimizeWindow, .fullScreen, .hideApp, .quitApp, .switchApp: .windows
        case .copy, .paste, .cut, .undo, .redo, .selectAll, .save: .editing
        case .screenshotFull, .screenshotArea, .screenshotTool: .capture
        case .keyboardShortcut, .typeText, .openApp, .openURL, .runShortcut, .shellCommand, .appleScript: .automation
        case .reactFlash, .reactShockwave, .reactGlitch, .reactText, .reactConfetti, .reactBall,
             .reactCombo, .reactStack, .reactBlackHole, .reactRandom: .reactions
        }
    }

    /// What extra input this action needs, if any.
    var parameter: ActionParameter? {
        switch self {
        case .keyboardShortcut: .keyCombo
        case .typeText: .text("Text to type")
        case .openApp: .app
        case .openURL: .text("https://")
        case .runShortcut: .shortcutName
        case .shellCommand: .text("say hello")
        case .appleScript: .multiline
        case .reactText: .text("KNOCK KNOCK")
        default: nil
        }
    }

    /// Needs permission to send keystrokes (Accessibility).
    var needsAccessibility: Bool {
        switch self {
        case .playPause, .nextTrack, .previousTrack, .volumeUp, .volumeDown, .mute, .brightnessUp, .brightnessDown,
             .spotlight, .spaceLeft, .spaceRight, .nextTab, .previousTab, .newTab, .closeTab, .minimizeWindow,
             .fullScreen, .hideApp, .quitApp, .switchApp, .copy, .paste, .cut, .undo, .redo, .selectAll, .save,
             .screenshotFull, .screenshotArea, .screenshotTool, .keyboardShortcut, .typeText:
            true
        default:
            false
        }
    }

    static func kinds(in category: ActionCategory) -> [ActionKind] {
        allCases.filter { $0.category == category }
    }
}

enum ActionParameter: Equatable {
    case text(String)   // placeholder
    case multiline
    case keyCombo
    case app
    case shortcutName
}

struct KeyCombo: Codable, Hashable {
    var keyCode: UInt16
    var modifiers: UInt64   // CGEventFlags raw value (only the modifier bits)
    var display: String
}

struct ActionSpec: Codable, Hashable {
    var kind: ActionKind = .none
    var text: String = ""
    var combo: KeyCombo?
    var appPath: String = ""

    static let none = ActionSpec()

    var summary: String {
        switch kind {
        case .keyboardShortcut: combo.map { "Press \($0.display)" } ?? kind.title
        case .openApp: appPath.isEmpty ? kind.title : "Open \(URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent)"
        case .typeText, .openURL, .runShortcut, .shellCommand, .reactText:
            text.isEmpty ? kind.title : "\(kind.title.replacingOccurrences(of: "…", with: "")): \(text)"
        case .appleScript: kind.title.replacingOccurrences(of: "…", with: "")
        default: kind.title
        }
    }
}

import AppKit
import SwiftUI

/// One cell of the gesture grid: shows the action and edits it in a popover.
struct ActionCell: View {
    @Binding var spec: ActionSpec?
    let inheritLabel: String
    var disabledNote: String?
    @StateObject private var editing = Box(false)

    var body: some View {
        Button { editing.value = true } label: {
            HStack(spacing: 8) {
                Image(systemName: spec?.kind.symbol ?? "arrow.turn.down.right")
                    .frame(width: 18)
                    .foregroundStyle(spec == nil ? .secondary : .primary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(spec?.summary ?? inheritLabel)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(spec == nil ? .secondary : .primary)
                    if let disabledNote {
                        Text(disabledNote).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(minWidth: 130, maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(.quaternary.opacity(spec == nil ? 0.35 : 0.8)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $editing.value, arrowEdge: .bottom) {
            ActionEditor(spec: $spec, inheritLabel: inheritLabel)
        }
    }
}

struct ActionEditor: View {
    @Binding var spec: ActionSpec?
    let inheritLabel: String
    @StateObject private var shortcuts = Box<[String]>([])

    private var kind: Binding<ActionKind?> {
        Binding(get: { spec?.kind }, set: { k in
            if let k { spec = ActionSpec(kind: k, text: spec?.kind == k ? spec?.text ?? "" : "") } else { spec = nil }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Menu {
                Button(inheritLabel) { kind.wrappedValue = nil }
                Button("Do nothing") { kind.wrappedValue = ActionKind.none }
                ForEach(ActionCategory.allCases) { cat in
                    Section(cat.rawValue) {
                        ForEach(ActionKind.kinds(in: cat)) { k in
                            Button { kind.wrappedValue = k } label: { Label(k.title, systemImage: k.symbol) }
                        }
                    }
                }
            } label: {
                Label(spec?.kind.title ?? inheritLabel, systemImage: spec?.kind.symbol ?? "arrow.turn.down.right")
            }
            .frame(width: 280)

            if let p = spec?.kind.parameter {
                parameterEditor(p)
            }

            HStack {
                if spec?.kind.needsAccessibility == true && !ActionRunner.hasAccessibility {
                    Label("Needs Accessibility", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                Spacer()
                Button("Try it") {
                    if let s = spec {
                        // Let the popover close first so keystrokes go to the right app.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { KnockEngine.shared.test(s) }
                    }
                }
                .disabled(spec == nil || spec?.kind == ActionKind.none)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    @ViewBuilder
    private func parameterEditor(_ p: ActionParameter) -> some View {
        let text = Binding(get: { spec?.text ?? "" }, set: { spec?.text = $0 })
        switch p {
        case .text(let placeholder):
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        case .multiline:
            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .frame(height: 90)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
        case .keyCombo:
            ShortcutRecorder(combo: Binding(get: { spec?.combo }, set: { spec?.combo = $0 }))
        case .app:
            HStack {
                if let path = spec?.appPath, !path.isEmpty {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 22, height: 22)
                    Text(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
                }
                Spacer()
                Button("Choose…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.application]
                    panel.directoryURL = URL(fileURLWithPath: "/Applications")
                    if panel.runModal() == .OK, let url = panel.url { spec?.appPath = url.path }
                }
            }
        case .shortcutName:
            HStack {
                TextField("Shortcut name", text: text).textFieldStyle(.roundedBorder)
                Menu("Pick") {
                    ForEach(shortcuts.value, id: \.self) { name in Button(name) { spec?.text = name } }
                }
                .fixedSize()
            }
            .task { shortcuts.value = await Self.listShortcuts() }
        }
    }

    static func listShortcuts() async -> [String] {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
                p.arguments = ["list"]
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = FileHandle.nullDevice
                try? p.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                let names = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init).sorted()
                cont.resume(returning: names)
            }
        }
    }
}

/// Click, then press the shortcut you want knocks to send.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo?
    @StateObject private var recording = Box(false)
    @StateObject private var monitor = Box<Any?>(nil)

    var body: some View {
        HStack {
            Button(recording.value ? "Press keys…" : (combo?.display ?? "Record shortcut")) {
                recording.value ? stop() : start()
            }
            .buttonStyle(.bordered)
            if combo != nil {
                Button { combo = nil } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording.value = true
        monitor.value = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53 { stop(); return nil }  // Esc cancels
            let mods = e.modifierFlags.intersection([.command, .option, .control, .shift, .function])
            var cg = CGEventFlags()
            if mods.contains(.command) { cg.insert(.maskCommand) }
            if mods.contains(.option) { cg.insert(.maskAlternate) }
            if mods.contains(.control) { cg.insert(.maskControl) }
            if mods.contains(.shift) { cg.insert(.maskShift) }
            if mods.contains(.function) { cg.insert(.maskSecondaryFn) }
            combo = KeyCombo(keyCode: e.keyCode, modifiers: cg.rawValue, display: Self.describe(mods, e))
            stop()
            return nil
        }
    }

    private func stop() {
        recording.value = false
        if let m = monitor.value { NSEvent.removeMonitor(m) }
        monitor.value = nil
    }

    static func describe(_ m: NSEvent.ModifierFlags, _ e: NSEvent) -> String {
        var s = ""
        if m.contains(.control) { s += "⌃" }
        if m.contains(.option) { s += "⌥" }
        if m.contains(.shift) { s += "⇧" }
        if m.contains(.command) { s += "⌘" }
        let special: [UInt16: String] = [36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
                                         122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
                                         101: "F9", 109: "F10", 103: "F11", 111: "F12"]
        s += special[e.keyCode] ?? (e.charactersIgnoringModifiers ?? "?").uppercased()
        return s
    }
}

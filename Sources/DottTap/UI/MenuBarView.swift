import ServiceManagement
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var engine: KnockEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dott Tap").font(.headline)
                    Text(statusText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $store.settings.enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            if !ActionRunner.hasAccessibility {
                Button {
                    SettingsWindow.shared.show(page: .permissions)
                } label: {
                    Label("Allow Accessibility so actions can run", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.orange)
            }

            HStack(spacing: 8) {
                Image(systemName: "hand.tap").foregroundStyle(.secondary)
                Text(engine.lastGesture).font(.callout)
                Spacer()
            }
            .padding(10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                ForEach(1...3, id: \.self) { n in
                    HStack {
                        Text(["", "Single", "Double", "Triple"][n]).foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .leading)
                        let spec = store.settings.bindings[BindingKey(.anywhere, n)] ?? .none
                        Image(systemName: spec.kind.symbol).frame(width: 18)
                        Text(spec.summary).lineLimit(1)
                        Spacer()
                    }
                    .font(.callout)
                }
            }

            Toggle("Open at login", isOn: Binding(
                get: { SMAppService.mainApp.status == .enabled },
                set: { on in
                    try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    store.objectWillChange.send()
                }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.callout)

            Picker("Knock feel", selection: $store.settings.feel) {
                ForEach(KnockFeel.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)

            Divider()

            HStack {
                if engine.pausedUntil != nil {
                    Button("Resume") { engine.resume() }
                } else {
                    Button("Pause 10 min") { engine.pause(for: 600) }
                        .disabled(!store.settings.enabled)
                }
                Spacer()
                Button("Settings…") { SettingsWindow.shared.show() }
                Button("Quit") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 300)
    }

    private var statusText: String {
        switch engine.state {
        case .off: return "Off"
        case .listening(let hz): return "Listening · \(hz) Hz"
        case .paused(let why):
            if let until = engine.pausedUntil, why == "Paused" {
                return "Paused until \(until.formatted(date: .omitted, time: .shortened))"
            }
            return "Paused · \(why)"
        case .unsupported: return "No motion sensor · trackpad & phone only"
        }
    }
}

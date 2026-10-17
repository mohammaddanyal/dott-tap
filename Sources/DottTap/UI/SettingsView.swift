import ServiceManagement
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case welcome, general, gestures, swipes, apps, surfaces, test, remote, permissions
    var id: String { rawValue }
    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .general: "General"
        case .gestures: "Gestures"
        case .swipes: "Swipe gestures"
        case .apps: "Per-app gestures"
        case .surfaces: "Screen & desk"
        case .test: "Knock test"
        case .remote: "Trackpad & phone"
        case .permissions: "Permissions"
        }
    }
    var symbol: String {
        switch self {
        case .welcome: "hand.wave"
        case .general: "gearshape"
        case .gestures: "hand.tap"
        case .swipes: "hand.draw"
        case .apps: "square.grid.2x2"
        case .surfaces: "macbook"
        case .test: "waveform.path.ecg"
        case .remote: "iphone.gen3"
        case .permissions: "lock.shield"
        }
    }
}

final class SettingsNavigation: ObservableObject {
    @Published var page: SettingsPage = .gestures
}

struct SettingsView: View {
    @EnvironmentObject private var nav: SettingsNavigation
    @EnvironmentObject private var engine: KnockEngine

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: Binding(get: { nav.page }, set: { if let p = $0 { nav.page = p } })) { p in
                Label(p.title, systemImage: p.symbol).tag(p)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 240)
        } detail: {
            Group {
                switch nav.page {
                case .welcome: WelcomePage()
                case .general: GeneralPage()
                case .gestures: GesturesPage()
                case .swipes: SwipesPage()
                case .apps: AppsPage()
                case .surfaces: SurfacesPage()
                case .test: TestPage()
                case .remote: RemotePage()
                case .permissions: PermissionsPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Welcome

struct WelcomePage: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var engine: KnockEngine
    @EnvironmentObject private var nav: SettingsNavigation
    @StateObject private var trusted = Box(ActionRunner.hasAccessibility)
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Knock on your Mac").font(.largeTitle.bold())
                    Text("Dott Tap feels knocks through the motion sensor inside your MacBook and turns single, double and triple knocks into actions. Knock on the screen, the palm rest or the desk next to it.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Step(number: 1, title: "Check the sensor", done: engine.sensorSupported) {
                    Text(engine.sensorSupported
                         ? "Found it. Your Mac can feel knocks."
                         : "This Mac has no readable motion sensor. Trackpad and phone knocks still work.")
                }
                Step(number: 2, title: "Allow Accessibility", done: trusted.value) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Needed to press keys for you: media keys, copy/paste, screenshots, desktops.")
                        if !trusted.value {
                            Button("Allow…") { ActionRunner.requestAccessibility() }
                        }
                    }
                }
                Step(number: 3, title: "Try it", done: engine.lastGesture != "No knocks yet") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Knock twice near the trackpad, firmly, like knocking on a door. Music should play or pause.")
                        Text("Last: \(engine.lastGesture)").foregroundStyle(.secondary)
                    }
                }
                Step(number: 4, title: "Teach it your screen and desk (optional)", done: store.learnedSurfaces.count >= 2) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Eight knocks on each and you can give the screen and the desk different actions.")
                        Button("Teach surfaces") { nav.page = .surfaces }
                    }
                }

                HStack {
                    Spacer()
                    Button("Done") {
                        store.settings.onboarded = true
                        nav.page = .gestures
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .onReceive(timer) { _ in let now = ActionRunner.hasAccessibility; if trusted.value != now { trusted.value = now } }
    }

    struct Step<Content: View>: View {
        let number: Int
        let title: String
        let done: Bool
        @ViewBuilder let content: Content
        var body: some View {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle().fill(done ? Color.green : Color.accentColor.opacity(0.15)).frame(width: 28, height: 28)
                    if done { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white) }
                    else { Text("\(number)").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.accentColor) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline)
                    content.font(.callout).foregroundStyle(.primary)
                }
            }
        }
    }
}

// MARK: - General

struct GeneralPage: View {
    @EnvironmentObject private var store: Store
    @StateObject private var loginItem = Box(SMAppService.mainApp.status == .enabled)

    var body: some View {
        Form {
            Section {
                Toggle("Listen for knocks", isOn: $store.settings.enabled)
                Toggle("Open at login", isOn: $loginItem.value)
                    .onChange(of: loginItem.value) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            loginItem.value = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            Section("Knock feel") {
                Picker("Knock feel", selection: $store.settings.feel) {
                    ForEach(KnockFeel.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                LabeledContent("Fine tune") {
                    HStack {
                        Text("More sensitive").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $store.settings.fineTune, in: -1...1)
                        Text("Fewer accidents").font(.caption).foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Time between knocks") {
                    HStack {
                        Slider(value: $store.settings.gapMs, in: 250...650, step: 10)
                        Text("\(Int(store.settings.gapMs)) ms").monospacedDigit().frame(width: 56, alignment: .trailing)
                    }
                }
                Toggle("Ignore knocks while typing or clicking", isOn: $store.settings.ignoreWhileTyping)
                Toggle("Accept very hard hits", isOn: $store.settings.allowHardHits)
            }

            Section {
                Picker("Power", selection: $store.settings.powerMode) {
                    ForEach(PowerMode.allCases) { Text($0.title).tag($0) }
                }
                Text(store.settings.powerMode.detail).font(.caption).foregroundStyle(.secondary)
                Toggle("Pause below 10% battery", isOn: $store.settings.pauseOnLowBattery)
            } header: {
                Text("Battery")
            } footer: {
                Text("Dott Tap stops listening while the display is off or the screen is locked, and drops to Battery saver when Low Power Mode is on.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Feedback") {
                Toggle("Show what each knock did", isOn: $store.settings.showHUD)
                Toggle("Play a sound on each knock", isOn: $store.settings.soundFeedback)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Gestures

struct GesturesPage: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Gestures", text: "Pick what each knock does. Screen and desk columns work after you teach those surfaces; until then, Anywhere is used.")
                GestureGrid(bindings: $store.settings.bindings, inheritLabel: "Same as Anywhere")
            }
            .padding(24)
        }
    }
}

struct PageHeader: View {
    let title: String
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title2.bold())
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Rows: single/double/triple. Columns: Anywhere plus each surface.
struct GestureGrid: View {
    @Binding var bindings: Bindings
    let inheritLabel: String
    var isAppProfile = false
    @EnvironmentObject private var store: Store

    private var columns: [Surface] { [.anywhere, .screen, .desk] + (store.learnedSurfaces.contains(.body) ? [.body] : []) }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                Text("")
                ForEach(columns) { s in
                    Label(s.title, systemImage: s.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(s == .anywhere || store.learnedSurfaces.contains(s) ? .primary : .secondary)
                }
            }
            ForEach(1...3, id: \.self) { n in
                GridRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(["", "Single", "Double", "Triple"][n]).font(.headline)
                        Text(String(repeating: "● ", count: n)).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(width: 70, alignment: .leading)
                    ForEach(columns) { s in
                        let key = BindingKey(s, n)
                        ActionCell(
                            spec: Binding(get: { bindings[key] }, set: { bindings[key] = $0 }),
                            inheritLabel: s == .anywhere ? (isAppProfile ? "Same as global" : "Do nothing") : inheritLabel,
                            disabledNote: s != .anywhere && !store.learnedSurfaces.contains(s) ? "Teach \(s.title.lowercased()) first" : nil)
                    }
                }
            }
        }
    }
}

// MARK: - Swipes

struct SwipesPage: View {
    @EnvironmentObject private var store: Store
    @StateObject private var vertical = Box(TrackpadSwipes.systemUsesFourFingerVertical)
    @StateObject private var horizontal = Box(TrackpadSwipes.systemUsesFourFingerHorizontal)
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Swipe gestures",
                           text: "Swipe with four fingers on the trackpad. Swipe down to minimise every window, swipe up to bring them back.")
                Toggle("Four-finger swipes", isOn: $store.settings.swipesEnabled)
                    .toggleStyle(.switch)

                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                    ForEach(SwipeDirection.allCases) { dir in
                        GridRow {
                            Label(dir.title, systemImage: dir.symbol)
                                .font(.headline)
                                .frame(width: 150, alignment: .leading)
                            ActionCell(spec: Binding(get: { store.settings.swipes[dir.rawValue] },
                                                     set: { store.settings.swipes[dir.rawValue] = $0 }),
                                       inheritLabel: "Do nothing",
                                       disabledNote: note(for: dir))
                                .frame(maxWidth: 360)
                        }
                    }
                }
                .disabled(!store.settings.swipesEnabled)
                .opacity(store.settings.swipesEnabled ? 1 : 0.5)

                if vertical.value || horizontal.value {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("macOS uses some four-finger swipes too", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                        Text(conflictText)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open Trackpad settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!)
                        }
                    }
                    .font(.callout)
                    .padding(14)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(24)
        }
        .onReceive(timer) { _ in
            CFPreferencesAppSynchronize("com.apple.AppleMultitouchTrackpad" as CFString)
            let v = TrackpadSwipes.systemUsesFourFingerVertical, h = TrackpadSwipes.systemUsesFourFingerHorizontal
            if vertical.value != v { vertical.value = v }
            if horizontal.value != h { horizontal.value = h }
        }
    }

    private func note(for dir: SwipeDirection) -> String? {
        switch dir {
        case .up, .down: vertical.value ? "macOS uses this too" : nil
        case .left, .right: horizontal.value ? "macOS uses this too" : nil
        }
    }

    private var conflictText: String {
        var parts: [String] = []
        if vertical.value {
            parts.append("Swiping up or down with four fingers also opens Mission Control or App Exposé. In Trackpad settings, open More Gestures and set Mission Control and App Exposé to three fingers.")
        }
        if horizontal.value {
            parts.append("Swiping left or right with four fingers also switches desktops. Set \u{201C}Swipe between full-screen apps\u{201D} to three fingers there if you want those for Dott Tap.")
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - Apps

struct AppsPage: View {
    @EnvironmentObject private var store: Store
    @StateObject private var selection = Box<String?>(nil)

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                List(selection: $selection.value) {
                    ForEach(store.settings.apps) { app in
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 20, height: 20)
                            Text(app.name)
                        }
                        .tag(app.bundleID)
                    }
                }
                Divider()
                HStack(spacing: 4) {
                    Menu {
                        ForEach(runningApps, id: \.bundleIdentifier) { app in
                            Button(app.localizedName ?? "App") { add(app.bundleURL) }
                        }
                        Divider()
                        Button("Choose from Applications…") { chooseApp() }
                    } label: { Image(systemName: "plus") }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    Button {
                        store.settings.apps.removeAll { $0.bundleID == selection.value }
                        selection.value = nil
                    } label: { Image(systemName: "minus") }
                        .buttonStyle(.borderless)
                        .disabled(selection.value == nil)
                    Spacer()
                }
                .padding(8)
            }
            .frame(width: 210)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let idx = store.settings.apps.firstIndex(where: { $0.bundleID == selection.value }) {
                        PageHeader(title: store.settings.apps[idx].name,
                                   text: "These win while \(store.settings.apps[idx].name) is in front. Empty cells fall back to your global gestures.")
                        GestureGrid(bindings: $store.settings.apps[idx].bindings, inheritLabel: "Same as global", isAppProfile: true)
                    } else {
                        PageHeader(title: "Per-app gestures",
                                   text: "Give knocks a different job in specific apps, for example next slide in Keynote, mute in Zoom or skip in Spotify. Add an app with +.")
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .filter { app in !store.settings.apps.contains { $0.bundleID == app.bundleIdentifier } }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func chooseApp() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.application]
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        if p.runModal() == .OK { add(p.url) }
    }

    private func add(_ url: URL?) {
        guard let url, let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
        guard !store.settings.apps.contains(where: { $0.bundleID == id }) else { selection.value = id; return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        store.settings.apps.append(AppProfile(bundleID: id, name: name, path: url.path))
        selection.value = id
    }
}

// MARK: - Permissions

struct PermissionsPage: View {
    @StateObject private var trusted = Box(ActionRunner.hasAccessibility)
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                LabeledContent("Accessibility") {
                    if trusted.value {
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Allow…") { ActionRunner.requestAccessibility() }
                    }
                }
                Text("Lets Dott Tap press keys for you (media keys, shortcuts, copy/paste, screenshots, switching desktops) and run Trackpad Tap Mode.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open Accessibility settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
            Section {
                Text("Dark mode switching asks once to control System Events. Running a command or AppleScript runs it as you, so only add commands you trust.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Privacy") {
                Text("Everything stays on this Mac. Dott Tap only reads motion; it has no microphone or camera access and sends nothing anywhere. The phone remote only works on your own network with the private link shown on that page.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in let now = ActionRunner.hasAccessibility; if trusted.value != now { trusted.value = now } }
    }
}

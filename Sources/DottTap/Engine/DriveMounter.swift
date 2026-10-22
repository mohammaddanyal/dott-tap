import AppKit

/// A disk image Dott Tap opens whenever the drive it lives on is connected.
struct DiskImageEntry: Codable, Hashable, Identifiable {
    var path: String
    var showInFinder = true
    var id: String { path }
    var name: String { URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent }
}

/// Opens disk images (sparse bundles, DMGs) automatically when the drive that holds them is
/// plugged in, and ejects drives safely: images first, then the drive. It only ever runs
/// `hdiutil attach`, `hdiutil detach` and `diskutil eject`: nothing is formatted or repaired.
@MainActor
final class DriveMounter: ObservableObject {
    enum Status: Equatable {
        case open(mountPoint: String)
        case waitingForDrive
        case opening
        case failed(String)
    }

    @Published private(set) var status: [String: Status] = [:]
    @Published private(set) var lastMessage: String?

    var images: [DiskImageEntry] = [] { didSet { if oldValue != images { openAll(reason: "list changed") } } }
    var enabled = true { didSet { if enabled && !oldValue { openAll(reason: "on") } } }
    var log: ((String, [String: Any]) -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var inFlight: Set<String> = []
    private let queue = DispatchQueue(label: "DottTap.drives", qos: .userInitiated)

    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] note in
            let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
            MainActor.assumeIsolated { self?.volumeMounted(url) }
        })
        observers.append(nc.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        openAll(reason: "launch")
    }

    /// Images already open from an external drive, to fill the list the first time.
    func currentlyOpenImages(_ done: @escaping ([DiskImageEntry]) -> Void) {
        queue.async {
            let found = Self.attachedImages().keys
                .filter { $0.hasPrefix("/Volumes/") }
                .sorted()
                .map { DiskImageEntry(path: $0) }
            DispatchQueue.main.async { done(found) }
        }
    }

    private func volumeMounted(_ url: URL?) {
        guard let url else { return }
        let host = url.path.hasSuffix("/") ? url.path : url.path + "/"
        // Only react to the drives our images live on (not to the images themselves).
        if images.contains(where: { $0.path.hasPrefix(host) }) {
            openAll(reason: "drive connected")
        } else {
            refresh()
        }
    }

    /// Opens every listed image whose drive is connected and that isn't open yet.
    func openAll(reason: String) {
        guard enabled else { refresh(); return }
        let wanted = images
        queue.async { [weak self] in
            let attached = Self.attachedImages()
            for image in wanted where attached[image.path] == nil && FileManager.default.fileExists(atPath: image.path) {
                DispatchQueue.main.async { self?.attach(image, reason: reason) }
            }
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    private func attach(_ image: DiskImageEntry, reason: String) {
        guard !inFlight.contains(image.path) else { return }
        inFlight.insert(image.path)
        status[image.path] = .opening
        var args = ["attach", image.path, "-quiet"]
        if !image.showInFinder { args.append("-nobrowse") }
        queue.async { [weak self] in
            let result = Self.run("/usr/bin/hdiutil", args, timeout: 120)
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight.remove(image.path)
                if result.ok {
                    self.lastMessage = "Opened \(image.name)"
                    self.log?("drive", ["action": "attach", "image": image.name, "reason": reason, "ok": true])
                } else {
                    self.status[image.path] = .failed(result.output.isEmpty ? "hdiutil couldn’t open it" : result.output)
                    self.lastMessage = "Couldn’t open \(image.name)"
                    self.log?("drive", ["action": "attach", "image": image.name, "reason": reason, "ok": false, "error": result.output])
                }
                self.refresh()
            }
        }
    }

    /// Closes open images first, then ejects every external drive, so nothing is mid-write
    /// when the cable comes out.
    func ejectAll(_ done: ((Bool, String) -> Void)? = nil) {
        queue.async { [weak self] in
            var problems: [String] = []
            // Images stored on external drives first.
            for (path, devices) in Self.attachedImages() where path.hasPrefix("/Volumes/") {
                if let dev = devices.first {
                    let r = Self.run("/usr/bin/hdiutil", ["detach", dev], timeout: 60)
                    if !r.ok { problems.append(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent) }
                }
            }
            var ejected: [String] = []
            for disk in Self.externalPhysicalDisks() {
                let r = Self.run("/usr/sbin/diskutil", ["eject", disk], timeout: 60)
                if r.ok { ejected.append(disk) } else { problems.append(disk) }
            }
            let ok = problems.isEmpty
            let message = ok
                ? (ejected.isEmpty ? "No external drives to eject" : "Safe to unplug")
                : "Still in use: \(problems.joined(separator: ", ")). Close files on it and try again."
            DispatchQueue.main.async {
                self?.lastMessage = message
                self?.log?("drive", ["action": "eject", "ok": ok, "problems": problems])
                self?.refresh()
                done?(ok, message)
            }
        }
    }

    func refresh() {
        let wanted = images
        queue.async { [weak self] in
            let attached = Self.attachedMountPoints()
            var s: [String: Status] = [:]
            for image in wanted {
                if let mount = attached[image.path] {
                    s[image.path] = .open(mountPoint: mount)
                } else if !FileManager.default.fileExists(atPath: image.path) {
                    s[image.path] = .waitingForDrive
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                for image in wanted {
                    if let new = s[image.path] {
                        self.status[image.path] = new
                    } else if case .open = self.status[image.path] {
                        self.status[image.path] = nil   // closed; will show "Not open"
                    } else if self.status[image.path] == .waitingForDrive {
                        self.status[image.path] = nil
                    }
                }
            }
        }
    }

    // MARK: - hdiutil / diskutil

    nonisolated private static func run(_ tool: String, _ args: [String], timeout: TimeInterval) -> (ok: Bool, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (false, error.localizedDescription) }
        // Stop a stuck command; reading to the end below then returns.
        let watchdog = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        watchdog.cancel()
        let out = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return (p.terminationStatus == 0 && p.terminationReason == .exit, out)
    }

    nonisolated private static func hdiutilInfo() -> [[String: Any]] {
        let r = run("/usr/bin/hdiutil", ["info", "-plist"], timeout: 20)
        guard r.ok, let data = r.output.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [] }
        return plist["images"] as? [[String: Any]] ?? []
    }

    /// Image path → its /dev entries (whole disk first).
    nonisolated private static func attachedImages() -> [String: [String]] {
        var out: [String: [String]] = [:]
        for image in hdiutilInfo() {
            guard let path = image["image-path"] as? String else { continue }
            let devs = (image["system-entities"] as? [[String: Any]] ?? []).compactMap { $0["dev-entry"] as? String }.sorted()
            out[path] = devs
        }
        return out
    }

    /// Image path → where its volume is mounted.
    nonisolated private static func attachedMountPoints() -> [String: String] {
        var out: [String: String] = [:]
        for image in hdiutilInfo() {
            guard let path = image["image-path"] as? String else { continue }
            let mounts = (image["system-entities"] as? [[String: Any]] ?? []).compactMap { $0["mount-point"] as? String }
            out[path] = mounts.first ?? ""
        }
        return out
    }

    nonisolated private static func externalPhysicalDisks() -> [String] {
        let r = run("/usr/sbin/diskutil", ["list", "-plist", "external", "physical"], timeout: 20)
        guard r.ok, let data = r.output.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [] }
        return plist["WholeDisks"] as? [String] ?? []
    }
}

import AppKit
import IOKit.ps

/// Watches the things that decide whether listening is worth the power: display sleep,
/// screen lock, system sleep, battery level and Low Power Mode.
@MainActor
final class PowerMonitor {
    private(set) var screensAsleep = false
    private(set) var locked = false
    private(set) var systemSleeping = false
    private(set) var onBattery = false
    private(set) var batteryPercent = 100
    private(set) var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    var onChange: (() -> Void)?

    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var psSource: CFRunLoopSource?

    func start() {
        let ws = NSWorkspace.shared.notificationCenter
        let dn = DistributedNotificationCenter.default()
        let nc = NotificationCenter.default
        func on(_ center: NotificationCenter, _ name: Notification.Name, _ body: @escaping @MainActor () -> Void) {
            let o = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { body() }
            }
            observers.append((center, o))
        }
        on(ws, NSWorkspace.screensDidSleepNotification) { [weak self] in self?.screensAsleep = true; self?.onChange?() }
        on(ws, NSWorkspace.screensDidWakeNotification) { [weak self] in self?.screensAsleep = false; self?.onChange?() }
        on(ws, NSWorkspace.willSleepNotification) { [weak self] in self?.systemSleeping = true; self?.onChange?() }
        on(ws, NSWorkspace.didWakeNotification) { [weak self] in self?.systemSleeping = false; self?.onChange?() }
        on(ws, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in self?.locked = true; self?.onChange?() }
        on(ws, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in self?.locked = false; self?.onChange?() }
        on(dn, Notification.Name("com.apple.screenIsLocked")) { [weak self] in self?.locked = true; self?.onChange?() }
        on(dn, Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in self?.locked = false; self?.onChange?() }
        on(nc, Notification.Name.NSProcessInfoPowerStateDidChange) { [weak self] in
            self?.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            self?.onChange?()
        }

        readBattery()
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated {
                monitor.readBattery()
                monitor.onChange?()
            }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
            psSource = src
        }
    }

    private func readBattery() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 100
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            batteryPercent = max > 0 ? cur * 100 / max : cur
            onBattery = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue
        }
    }
}

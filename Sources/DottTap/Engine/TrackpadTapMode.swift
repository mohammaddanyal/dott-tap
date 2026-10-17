import AppKit
import CoreGraphics

/// Hold a modifier and click (or tap-to-click) the trackpad to knock. Works on any Mac.
/// The click is swallowed so it doesn't also land on whatever is under the pointer.
final class TrackpadTapMode {
    var modifier: TrackpadModifier = .fn
    var onTap: (() -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var swallowNextUp = false

    var isRunning: Bool { tap != nil }

    func start() {
        guard tap == nil else { return }
        let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask), callback: { _, type, event, ctx in
            guard let ctx else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<TrackpadTapMode>.fromOpaque(ctx).takeUnretainedValue()
            return me.handle(type: type, event: event)
        }, userInfo: context) else { return }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if type == .leftMouseUp, swallowNextUp {
            swallowNextUp = false
            return nil
        }
        guard type == .leftMouseDown, matches(event.flags) else { return Unmanaged.passUnretained(event) }
        swallowNextUp = true
        DispatchQueue.main.async { [weak self] in self?.onTap?() }
        return nil
    }

    private func matches(_ flags: CGEventFlags) -> Bool {
        switch modifier {
        case .fn: return flags.contains(.maskSecondaryFn)
        case .controlOption: return flags.contains(.maskControl) && flags.contains(.maskAlternate) && !flags.contains(.maskCommand)
        case .commandOption: return flags.contains(.maskCommand) && flags.contains(.maskAlternate)
        case .rightOption:
            // Device-dependent bit for the right Option key.
            return flags.contains(.maskAlternate) && (flags.rawValue & 0x40) != 0
        }
    }
}

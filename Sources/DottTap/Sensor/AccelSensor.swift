import Foundation
import IOKit
import IOKit.hid

/// Reads the motion sensor that Apple Silicon MacBooks (M2 and later) expose through
/// the Sensor Processing Unit: vendor usage page 0xFF00, usage 3, 22-byte reports with
/// x/y/z as little-endian Int32 at offsets 6/10/14, in 1/65536 g.
///
/// Reports are delivered on a private thread so the main thread never wakes for them.
final class AccelSensor {
    /// Called on the sensor thread for every report: (seconds, x, y, z) in g.
    var onSample: ((Double, Float, Float, Float) -> Void)?

    private var device: IOHIDDevice?
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private let reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private let ticksToSeconds: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()
    private(set) var rateHz: Int = 0
    private(set) var isRunning = false

    /// The rates the SPU actually honours (it rounds anything else to one of these).
    static let supportedRates = [100, 200, 400, 800]

    static var isSupported: Bool {
        guard let service = findService(className: "AppleSPUHIDDevice", match: { usagePage($0) == 0xFF00 && usage($0) == 3 }) else { return false }
        IOObjectRelease(service)
        return true
    }

    deinit {
        stop()
        reportBuffer.deallocate()
    }

    @discardableResult
    func start(rateHz: Int) -> Bool {
        if isRunning { setRate(rateHz); return true }
        guard let service = Self.findService(className: "AppleSPUHIDDevice", match: { Self.usagePage($0) == 0xFF00 && Self.usage($0) == 3 }) else { return false }
        defer { IOObjectRelease(service) }
        guard let dev = IOHIDDeviceCreate(kCFAllocatorDefault, service) else { return false }
        guard IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return false }

        Self.withAccelDriver { driver in
            IORegistryEntrySetCFProperty(driver, "SensorPropertyReportingState" as CFString, 1 as CFNumber)
            IORegistryEntrySetCFProperty(driver, "SensorPropertyPowerState" as CFString, 1 as CFNumber)
        }
        setRate(rateHz)

        device = dev
        isRunning = true
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportWithTimeStampCallback(dev, reportBuffer, 64, { context, _, _, _, _, report, length, timeStamp in
            guard let context, length >= 18 else { return }
            let sensor = Unmanaged<AccelSensor>.fromOpaque(context).takeUnretainedValue()
            let raw = UnsafeRawPointer(report)
            let x = Float(Int32(littleEndian: raw.loadUnaligned(fromByteOffset: 6, as: Int32.self))) / 65536
            let y = Float(Int32(littleEndian: raw.loadUnaligned(fromByteOffset: 10, as: Int32.self))) / 65536
            let z = Float(Int32(littleEndian: raw.loadUnaligned(fromByteOffset: 14, as: Int32.self))) / 65536
            sensor.onSample?(Double(timeStamp) * sensor.ticksToSeconds, x, y, z)
        }, context)

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self, let dev = self.device else { ready.signal(); return }
            self.runLoop = CFRunLoopGetCurrent()
            IOHIDDeviceScheduleWithRunLoop(dev, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            ready.signal()
            while self.isRunning {
                CFRunLoopRunInMode(.defaultMode, 3600, false)
            }
        }
        thread.name = "DottTap.sensor"
        thread.qualityOfService = .utility
        self.thread = thread
        thread.start()
        ready.wait()
        return true
    }

    /// Changes the report rate. Safe to call from any thread.
    func setRate(_ hz: Int) {
        let hz = Self.supportedRates.min(by: { abs($0 - hz) < abs($1 - hz) }) ?? 200
        guard hz != rateHz else { return }
        rateHz = hz
        let intervalMicros = 1_000_000 / hz
        Self.withAccelDriver { driver in
            IORegistryEntrySetCFProperty(driver, "ReportInterval" as CFString, intervalMicros as CFNumber)
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        if let dev = device {
            if let rl = runLoop {
                IOHIDDeviceUnscheduleFromRunLoop(dev, rl, CFRunLoopMode.defaultMode.rawValue)
                CFRunLoopStop(rl)
            }
            IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        device = nil
        runLoop = nil
        thread = nil
        rateHz = 0
    }

    // MARK: - IORegistry helpers

    private static func withAccelDriver(_ body: (io_service_t) -> Void) {
        guard let driver = findService(className: "AppleSPUHIDDriver", match: { product($0) == "accel" }) else { return }
        body(driver)
        IOObjectRelease(driver)
    }

    private static func findService(className: String, match: (io_service_t) -> Bool) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if match(service) { return service }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return nil
    }

    private static func property(_ service: io_service_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
    private static func usagePage(_ s: io_service_t) -> Int? { property(s, "PrimaryUsagePage") as? Int }
    private static func usage(_ s: io_service_t) -> Int? { property(s, "PrimaryUsage") as? Int }
    private static func product(_ s: io_service_t) -> String? { property(s, "Product") as? String }
}

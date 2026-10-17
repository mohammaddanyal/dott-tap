import Foundation

/// Small local log of knock events (features only, no other data) used to tune detection.
/// Kept under ~1 MB in ~/Library/Application Support/Dott Tap/events.jsonl.
final class EventLog {
    private let url: URL
    private let queue = DispatchQueue(label: "DottTap.eventlog", qos: .background)

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        url = base.appendingPathComponent("Dott Tap/events.jsonl")
    }

    func write(_ fields: [String: Any], _ features: KnockFeatures?) {
        var row = fields
        row["t"] = Date().timeIntervalSince1970
        if let f = features {
            row["f"] = ["peak": f.peak, "ex": f.ex, "ey": f.ey, "ez": f.ez, "sx": f.sx, "sy": f.sy, "sz": f.sz,
                        "decay": f.decayMs, "low": f.lowShare, "hz": f.rateHz]
        }
        let url = self.url
        queue.async {
            guard JSONSerialization.isValidJSONObject(row),
                  var data = try? JSONSerialization.data(withJSONObject: row) else { return }
            data.append(0x0A)
            let fm = FileManager.default
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 1_000_000 {
                try? fm.removeItem(at: url.appendingPathExtension("old"))
                try? fm.moveItem(at: url, to: url.appendingPathExtension("old"))
            }
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                h.write(data)
                try? h.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}

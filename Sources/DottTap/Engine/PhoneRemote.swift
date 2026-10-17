import Foundation
import Network

/// Turns any phone on the same Wi-Fi into a knock pad: open the page, tap the big
/// square. Taps are grouped on the phone with the same timing as on the Mac and sent
/// as one gesture. A random token in the address keeps other people on the network out.
final class PhoneRemote {
    var onGesture: ((Int, Surface) -> Void)?
    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    var token = ""
    var gapMs = 380

    var isRunning: Bool { listener != nil }

    func start(port: UInt16, token: String) {
        stop()
        self.token = token
        guard let p = NWEndpoint.Port(rawValue: port), let l = try? NWListener(using: .tcp, on: p) else { return }
        l.newConnectionHandler = { [weak self] c in self?.handle(c) }
        l.start(queue: .global(qos: .utility))
        listener = l
        self.port = port
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    var urls: [String] {
        Self.localIPv4().map { "http://\($0):\(port)/\(token)" }
    }

    private func handle(_ c: NWConnection) {
        c.start(queue: .global(qos: .utility))
        c.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data, let req = String(data: data, encoding: .utf8),
                  let line = req.split(separator: "\r\n").first else { c.cancel(); return }
            let parts = line.split(separator: " ")
            let path = parts.count > 1 ? String(parts[1]) : "/"
            self.respond(c, path: path)
        }
    }

    private func respond(_ c: NWConnection, path: String) {
        let comps = URLComponents(string: path)
        let segs = (comps?.path ?? "").split(separator: "/").map(String.init)
        guard segs.first == token else { send(c, status: "404 Not Found", type: "text/plain", body: "Not found"); return }
        if segs.count >= 2, segs[1] == "g" {
            let q = Dictionary(uniqueKeysWithValues: (comps?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            let count = max(1, min(3, Int(q["n"] ?? "1") ?? 1))
            let surface = Surface(rawValue: q["s"] ?? "") ?? .anywhere
            DispatchQueue.main.async { self.onGesture?(count, surface) }
            send(c, status: "204 No Content", type: "text/plain", body: "")
            return
        }
        send(c, status: "200 OK", type: "text/html; charset=utf-8", body: page())
    }

    private func send(_ c: NWConnection, status: String, type: String, body: String) {
        let b = Data(body.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(b.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        c.send(content: Data(head.utf8) + b, completion: .contentProcessed { _ in c.cancel() })
    }

    private func page() -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">
        <meta name="apple-mobile-web-app-capable" content="yes">
        <title>Dott Tap</title>
        <style>
        :root{color-scheme:dark}
        body{margin:0;font:16px -apple-system,system-ui,sans-serif;background:#0d0f14;color:#e9ecf2;
             display:flex;flex-direction:column;height:100vh;height:100dvh;user-select:none;-webkit-user-select:none}
        header{padding:14px 16px 6px;font-weight:600}
        .seg{display:flex;gap:6px;padding:0 16px 10px}
        .seg button{flex:1;padding:10px 0;border-radius:10px;border:0;background:#1b1f29;color:#c8cdd8;font:inherit}
        .seg button.on{background:#3b6cff;color:#fff}
        #pad{flex:1;margin:0 16px 16px;border-radius:24px;background:radial-gradient(circle at 50% 40%,#1e2a4a,#121722);
             display:flex;align-items:center;justify-content:center;font-size:20px;color:#8f9bb3;touch-action:manipulation}
        #pad.hit{background:radial-gradient(circle at 50% 40%,#3b6cff,#18254a)}
        #dots{font-size:44px;letter-spacing:10px;color:#fff;min-height:56px}
        </style></head><body>
        <header>Dott Tap remote</header>
        <div class="seg" id="seg">
          <button data-s="anywhere" class="on">Anywhere</button><button data-s="screen">Screen</button><button data-s="desk">Desk</button>
        </div>
        <div id="pad"><div><div id="dots"></div><div id="msg">Tap once, twice or three times</div></div></div>
        <script>
        let s='anywhere',n=0,t=null;const gap=\(gapMs);
        document.querySelectorAll('#seg button').forEach(b=>b.onclick=()=>{s=b.dataset.s;
          document.querySelectorAll('#seg button').forEach(x=>x.classList.toggle('on',x===b));});
        const pad=document.getElementById('pad'),dots=document.getElementById('dots');
        pad.addEventListener('pointerdown',e=>{e.preventDefault();n=Math.min(3,n+1);dots.textContent='●'.repeat(n);
          pad.classList.add('hit');setTimeout(()=>pad.classList.remove('hit'),90);
          if(navigator.vibrate)navigator.vibrate(15);clearTimeout(t);
          const go=()=>{fetch('g?n='+n+'&s='+s).catch(()=>{});n=0;setTimeout(()=>dots.textContent='',300);};
          if(n>=3)go();else t=setTimeout(go,gap);});
        </script></body></html>
        """
    }

    static func localIPv4() -> [String] {
        var out: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                out.append(String(cString: host))
            }
        }
        return out
    }
}

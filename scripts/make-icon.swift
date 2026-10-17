// Draws the app icon: a dot with knock ripples on a deep blue squircle.
// Usage: swift scripts/make-icon.swift <out.iconset>
import AppKit

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // macOS icon grid: 824/1024 body with soft shadow.
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = CGPath(roundedRect: body, cornerWidth: body.width * 0.225, cornerHeight: body.width * 0.225, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(path); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(srgbRed: 0.10, green: 0.13, blue: 0.32, alpha: 1).cgColor,
        NSColor(srgbRed: 0.16, green: 0.33, blue: 0.95, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: body.minX, y: body.minY), end: CGPoint(x: body.maxX, y: body.maxY), options: [])

    // A dot with impact rings spreading out, the way a knock travels through the Mac.
    let c = CGPoint(x: s / 2, y: s / 2)
    for (i, r) in [0.16, 0.245, 0.33].enumerated() {
        let radius = s * CGFloat(r)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.8 - CGFloat(i) * 0.26).cgColor)
        ctx.setLineWidth(s * (0.03 - CGFloat(i) * 0.006))
        ctx.strokeEllipse(in: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
    }
    let dot = s * 0.09
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: CGRect(x: c.x - dot, y: c.y - dot, width: dot * 2, height: dot * 2))
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! draw(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try! draw(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}

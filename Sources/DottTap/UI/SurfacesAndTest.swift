import CoreImage.CIFilterBuiltins
import SwiftUI

// MARK: - Screen & desk training

struct SurfacesPage: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var engine: KnockEngine

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Screen & desk",
                           text: "A knock on the screen shakes the Mac differently from a knock on the desk. Teach Dott Tap a few of each and it can tell them apart, so each surface can do its own thing.")

                if !engine.sensorSupported {
                    Label("This Mac has no readable motion sensor.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }

                ForEach(Surface.learnable) { s in
                    SurfaceCard(surface: s)
                }

                if let acc = engine.trainingAccuracy {
                    HStack(spacing: 10) {
                        Image(systemName: acc >= 0.85 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(acc >= 0.85 ? .green : .orange)
                        Text(acc >= 0.85
                             ? "Self-check: \(Int(acc * 100))% of your knocks are recognised correctly."
                             : "Self-check: \(Int(acc * 100))%. Try knocking each surface the same way every time, or teach again.")
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(24)
        }
    }
}

private struct SurfaceCard: View {
    let surface: Surface
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var engine: KnockEngine

    var body: some View {
        let count = store.calibration[surface]?.count ?? 0
        let active = engine.calibrating == surface
        HStack(spacing: 16) {
            Image(systemName: surface.symbol)
                .font(.system(size: 26))
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(surface.title).font(.headline)
                if active {
                    Text(surface.hint).font(.callout)
                    HStack(spacing: 6) {
                        ForEach(0..<engine.calibrationTarget, id: \.self) { i in
                            Circle().fill(i < engine.calibrationCount ? Color.accentColor : Color.secondary.opacity(0.25))
                                .frame(width: 10, height: 10)
                        }
                    }
                    .padding(.top, 2)
                } else {
                    Text(count >= 3 ? "Learned from \(count) knocks" : surface.hint)
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if active {
                Button("Stop") { engine.stopCalibration() }
            } else {
                if count > 0 { Button("Forget") { engine.forget(surface) }.buttonStyle(.borderless) }
                Button(count >= 3 ? "Teach again" : "Teach") { engine.startCalibration(surface) }
                    .disabled(engine.calibrating != nil || !engine.sensorSupported)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(active ? 0.9 : 0.45)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(active ? Color.accentColor : .clear, lineWidth: 2))
    }
}

// MARK: - Live test

struct TestPage: View {
    @EnvironmentObject private var engine: KnockEngine
    @EnvironmentObject private var store: Store

    private var graph: some View {
        Canvas { ctx, size in
            let values = engine.detector.monitor.snapshot()
            let tune = engine.detector.tuning
            let top: Float = max(0.08, (values.max() ?? 0) * 1.15)
            func y(_ v: Float) -> CGFloat { size.height - CGFloat(min(v, top) / top) * size.height }
            var path = Path()
            let step = size.width / CGFloat(max(values.count - 1, 1))
            for (i, v) in values.enumerated() {
                let p = CGPoint(x: CGFloat(i) * step, y: y(v))
                i == 0 ? path.move(to: p) : path.addLine(to: p)
            }
            ctx.stroke(path, with: .color(.accentColor), lineWidth: 1.5)
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y(tune.minPeak)))
            line.addLine(to: CGPoint(x: size.width, y: y(tune.minPeak)))
            ctx.stroke(line, with: .color(.orange), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Not PageHeader: its fixed-height text blanks this page, which (unlike the others)
            // isn't inside a ScrollView.
            VStack(alignment: .leading, spacing: 4) {
                Text("Knock test").font(.title2.bold())
                Text("Knock and watch the signal. Spikes above the dashed line count as knocks. Use this to pick the right knock feel.")
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Picker("Knock feel", selection: $store.settings.feel) {
                ForEach(KnockFeel.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                // Screenshots render once; a hidden window never ticks a timeline.
                if KnockEngine.snapshotMode {
                    graph
                } else {
                    TimelineView(.periodic(from: .now, by: 1.0 / 30)) { _ in graph }
                }
            }
            .frame(height: 170)
            .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.4)))

            HStack {
                Text("Last gesture: \(engine.lastGesture)").font(.headline)
                Spacer()
            }

            // Plain SwiftUI rows rather than List: List's table view kept the page from
            // drawing while the graph redraws 30 times a second.
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(engine.log) { item in
                        HStack {
                            Image(systemName: item.accepted ? "hand.tap.fill" : "xmark.circle")
                                .foregroundStyle(item.accepted ? Color.accentColor : .secondary)
                                .frame(width: 20)
                            Text(item.text)
                            Spacer()
                            Text(item.detail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            Text(item.date.formatted(date: .omitted, time: .standard)).font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        Divider().opacity(0.5)
                    }
                    if engine.log.isEmpty {
                        Text("Knock and your knocks show up here.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.3)))
            .frame(minHeight: 120, maxHeight: .infinity)
        }
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { engine.setLiveMonitoring(true) }
        .onDisappear { engine.setLiveMonitoring(false) }
    }
}

// MARK: - Trackpad & phone

struct RemotePage: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var engine: KnockEngine

    var body: some View {
        Form {
            Section {
                Toggle("Trackpad Tap Mode", isOn: $store.settings.trackpadMode)
                Picker("Hold while clicking", selection: $store.settings.trackpadModifier) {
                    ForEach(TrackpadModifier.allCases) { Text($0.title).tag($0) }
                }
                .disabled(!store.settings.trackpadMode)
                if store.settings.trackpadMode && !ActionRunner.hasAccessibility {
                    Button("Allow Accessibility to use this") { ActionRunner.requestAccessibility() }
                }
            } footer: {
                Text("Hold the key and click the trackpad once, twice or three times. Works on any Mac, including desktops with a Magic Trackpad.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Phone remote", isOn: $store.settings.phoneRemote)
                if store.settings.phoneRemote {
                    if let url = engine.phoneURLs.first {
                        HStack(alignment: .top, spacing: 16) {
                            if let qr = Self.qr(url) {
                                Image(nsImage: qr).interpolation(.none).resizable().frame(width: 140, height: 140)
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Scan with your phone's camera, or open:").font(.callout)
                                Text(url).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                                Text("Phone and Mac must be on the same Wi-Fi. Add it to your home screen for one-tap access.")
                                    .font(.caption).foregroundStyle(.secondary)
                                Button("New private link") {
                                    store.settings.phoneToken = String(UUID().uuidString.prefix(8)).lowercased()
                                }
                            }
                        }
                    } else {
                        Text("Connect to Wi-Fi to use the phone remote.").foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Turns your phone into a knock pad that triggers the same gestures, including screen and desk ones.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    static func qr(_ text: String) -> NSImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let rep = NSCIImageRep(ciImage: out)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }
}

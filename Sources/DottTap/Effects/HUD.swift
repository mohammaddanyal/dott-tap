import AppKit
import SwiftUI

/// Small pill under the menu bar confirming what a knock did.
@MainActor
final class HUD {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private let model = HUDModel()

    func show(symbol: String, title: String, subtitle: String) {
        model.symbol = symbol
        model.title = title
        model.subtitle = subtitle
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let screen {
            let size = panel.contentView?.fittingSize ?? NSSize(width: 300, height: 56)
            let f = screen.visibleFrame
            panel.setFrame(NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height - 14, width: size.width, height: size.height), display: true)
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                self?.panel?.animator().alphaValue = 0
            }, completionHandler: {
                MainActor.assumeIsolated { self?.panel?.orderOut(nil) }
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3, execute: work)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 56),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingView(rootView: HUDView(model: model))
        host.sizingOptions = [.intrinsicContentSize]
        p.contentView = host
        return p
    }
}

private final class HUDModel: ObservableObject {
    @Published var symbol = "hand.tap"
    @Published var title = ""
    @Published var subtitle = ""
}

private struct HUDView: View {
    @ObservedObject var model: HUDModel
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: model.symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.title).font(.system(size: 13, weight: .semibold))
                Text(model.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .fixedSize()
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .padding(4)
    }
}

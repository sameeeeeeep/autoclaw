import AppKit
import SwiftUI

/// Floating kanban board widget — separate from the toast.
/// Positioned bottom-left, opposite to Theater PIP (bottom-right).
final class BoardPIPWindow: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 360),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
    }

    private var hosting: BoardFirstMouseHostingView?
    private var hasContent = false

    var isShowing: Bool { isVisible && hasContent }

    func show(with view: some View) {
        if hasContent {
            if !isVisible {
                alphaValue = 0
                makeKeyAndOrderFront(nil)
                level = .floating
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.25
                    animator().alphaValue = 1
                }
            }
            return
        }

        let hostingView = BoardFirstMouseHostingView(rootView: AnyView(view))

        let effect = BoardFirstMouseVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: effect.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
        ])

        contentView = effect
        hosting = hostingView
        hasContent = true

        hostingView.layoutSubtreeIfNeeded()
        let fitting = hostingView.fittingSize
        let w = max(fitting.width, 280)
        let h = min(max(fitting.height, 200), 480)

        // Position bottom-left
        if let screen = NSScreen.main {
            let vis = screen.visibleFrame
            let x = vis.minX + 16
            let y = vis.minY + 16
            setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
        }

        alphaValue = 0
        makeKeyAndOrderFront(nil)
        level = .floating

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
            self.alphaValue = 1
            self.hasContent = false
            self.hosting = nil
            self.contentView = nil
        })
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class BoardFirstMouseHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class BoardFirstMouseVisualEffectView: NSVisualEffectView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

import AppKit
import SwiftUI

/// Floating Picture-in-Picture window for SiliconValley Theater dialog.
/// Stays above other windows while the Haiku session is active.
/// Uses liquid glass effect (macOS 26) with fallback, matching toast styling.
public final class TheaterPIPWindow: NSPanel {
    public var isShowing: Bool { isVisible && hasContent }

    public init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
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

    private var hosting: TheaterFirstMouseHostingView?
    private var hasContent = false

    public func show(with view: some View) {
        if hasContent {
            // Already showing — just ensure visible, don't recreate the view hierarchy.
            // SwiftUI @ObservedObject reactivity handles content updates.
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

        let hostingView = TheaterFirstMouseHostingView(rootView: AnyView(view))

        let effect = TheaterFirstMouseVisualEffectView()
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

        // Force layout to get intrinsic size
        hostingView.layoutSubtreeIfNeeded()
        let fitting = hostingView.fittingSize
        let w = max(fitting.width, 380)
        let h = min(max(fitting.height, 250), 500)

        // Position bottom-right of visible screen, above dock
        if let screen = NSScreen.main {
            let vis = screen.visibleFrame
            let x = vis.maxX - w - 16
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

    /// Update window size when dialog content changes
    public func refit() {
        guard let hostingView = hosting else { return }
        hostingView.layoutSubtreeIfNeeded()
        let fitting = hostingView.fittingSize
        let w = max(fitting.width, 380)
        let h = min(max(fitting.height, 250), 500)

        var frame = self.frame
        // Keep bottom-left corner pinned, grow upward
        let dy = h - frame.height
        frame.origin.y -= dy
        frame.size = NSSize(width: w, height: h)
        setFrame(frame, display: true, animate: true)
    }

    public func dismiss() {
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

    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { false }
}

// MARK: - First-Mouse Views (immediate click without activation)

private final class TheaterFirstMouseHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class TheaterFirstMouseVisualEffectView: NSVisualEffectView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

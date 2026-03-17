import AppKit
import SwiftUI

final class PillWindow: NSPanel {

    static let defaultWidth: CGFloat = 240

    // Smooth drag state
    private var initialMouseScreenLocation: NSPoint = .zero
    private var initialWindowOrigin: NSPoint = .zero
    private var isDragging = false
    private var hostingView: NSHostingView<AnyView>?

    /// Observable collapse level — the SwiftUI view binds to this
    @Published var collapseLevel: CollapseLevel = .full {
        didSet { if oldValue != collapseLevel { animateToLevel(collapseLevel) } }
    }

    init(appState: AppState) {
        let initial = CollapseLevel.full
        super.init(
            contentRect: NSRect(x: 0, y: 0,
                                width: initial.width,
                                height: initial.height),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow

        let binding = Binding<CollapseLevel>(
            get: { [weak self] in self?.collapseLevel ?? .full },
            set: { [weak self] in self?.collapseLevel = $0 }
        )

        let view = SidebarView(appState: appState, collapseLevel: binding)
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = CGColor.clear
        hosting.layer?.isOpaque = false
        contentView = hosting
        hostingView = hosting

        // Position top-right
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.maxX - initial.width - 16
            let y = screen.visibleFrame.maxY - initial.height - 16
            setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    // MARK: - Collapse Animation

    /// Animate the window frame to match a collapse level.
    /// Pins top edge and right edge so it grows/shrinks downward + inward.
    private func animateToLevel(_ level: CollapseLevel) {
        let newW = level.width
        let newH = level.height
        guard abs(frame.width - newW) > 1 || abs(frame.height - newH) > 1 else { return }
        let deltaH = newH - frame.height
        let deltaW = newW - frame.width
        var r = frame
        r.origin.y -= deltaH    // keep top edge pinned
        r.origin.x -= deltaW    // keep right edge pinned
        r.size.width  = newW
        r.size.height = newH
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.36
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ctx.allowsImplicitAnimation = true
            self.animator().setFrame(r, display: true)
        }
    }

    // MARK: - Smooth Dragging

    override func mouseDown(with event: NSEvent) {
        initialMouseScreenLocation = NSEvent.mouseLocation
        initialWindowOrigin = frame.origin
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        isDragging = true
        let current = NSEvent.mouseLocation
        let newOrigin = NSPoint(
            x: initialWindowOrigin.x + (current.x - initialMouseScreenLocation.x),
            y: initialWindowOrigin.y + (current.y - initialMouseScreenLocation.y)
        )
        setFrameOrigin(newOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging { snapToEdges() }
        isDragging = false
    }

    private func snapToEdges() {
        guard let screen = NSScreen.main else { return }
        let margin: CGFloat = 12
        let visible = screen.visibleFrame
        var origin = frame.origin

        if abs(origin.x - visible.minX) < margin { origin.x = visible.minX }
        if abs(origin.x + frame.width - visible.maxX) < margin { origin.x = visible.maxX - frame.width }
        if abs(origin.y + frame.height - visible.maxY) < margin { origin.y = visible.maxY - frame.height }
        if abs(origin.y - visible.minY) < margin { origin.y = visible.minY }

        if origin != frame.origin {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().setFrameOrigin(origin)
            }
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

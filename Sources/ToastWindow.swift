import AppKit
import SwiftUI

/// Floating toast panel — plain window with `.titled` + `.fullSizeContentView`
/// so Apple's system-level liquid glass effect renders automatically.
final class ToastWindow: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
    }

    /// Maximum height for the toast (thread view can grow taller)
    var maxHeight: CGFloat = 500

    func show(with view: some View) {
        let hosting = NSHostingView(rootView: AnyView(view))

        // Use visual effect view as backdrop for system material
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12

        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
        ])

        contentView = effect

        // Force layout to get correct size
        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize
        let w = max(fitting.width, 300)
        let h = min(max(fitting.height, 100), maxHeight)

        // Position top-right of visible screen area
        if let screen = NSScreen.main {
            let vis = screen.visibleFrame
            let x = vis.maxX - w - 16
            let y = vis.maxY - h - 16
            setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
        }

        alphaValue = 1
        orderFront(nil)
        level = .floating
        NSLog("[Autoclaw] Toast shown: \(w)x\(h)")
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
            self.alphaValue = 1
        })
    }

    /// Set to true for toasts that need keyboard input (clarification)
    var allowsKeyboard = false
    override var canBecomeKey: Bool { allowsKeyboard }
    override var canBecomeMain: Bool { false }

    /// Enable file drag & drop — calls handler with dropped file URLs
    var onFilesDropped: (([URL]) -> Void)?

    func enableFileDrop() {
        // Use a transparent drop overlay on the content view
        guard let cv = contentView else { return }
        let dropView = DropTargetView { [weak self] urls in
            self?.onFilesDropped?(urls)
        }
        dropView.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(dropView)
        NSLayoutConstraint.activate([
            dropView.topAnchor.constraint(equalTo: cv.topAnchor),
            dropView.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
            dropView.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            dropView.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
        ])
    }
}

// MARK: - Drop Target View

private final class DropTargetView: NSView {
    var handler: (([URL]) -> Void)?

    convenience init(handler: @escaping ([URL]) -> Void) {
        self.init(frame: .zero)
        self.handler = handler
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !items.isEmpty else { return false }
        handler?(items)
        return true
    }
}

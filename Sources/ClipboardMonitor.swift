import AppKit
import Combine

@MainActor
final class ClipboardMonitor: ObservableObject {
    @Published var latestContent = ""

    private var timer: Timer?
    private var lastChangeCount = 0

    func start() {
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.check()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func check() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        if let text = pb.string(forType: .string), !text.isEmpty {
            latestContent = text
        }
    }
}

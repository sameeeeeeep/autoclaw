import Foundation

/// Simple file-based debug logger — writes to /tmp/autoclaw_debug.log
/// so we can `tail -f` it from a terminal while the app runs.
enum DebugLog {
    private static let logPath = "/tmp/autoclaw_debug.log"
    private static let lock = NSLock()

    /// Log a message with timestamp. Also prints to stdout for Xcode/terminal launches.
    static func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"

        print(message)  // still print for terminal launches

        lock.lock()
        defer { lock.unlock() }

        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: logPath)) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: URL(fileURLWithPath: logPath))
            }
        }
    }

    /// Clear the log file (call on app launch)
    static func clear() {
        try? "".write(toFile: logPath, atomically: true, encoding: .utf8)
    }
}

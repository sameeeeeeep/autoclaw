import Foundation
import os

/// Simple logger for the Theater module.
/// Uses os_log so output is visible via `log stream --predicate 'subsystem == "com.autoclaw.theater"'`.
public enum TheaterLog {
    private static let logger = Logger(subsystem: "com.autoclaw.theater", category: "Theater")

    public static func log(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }
}

// Internal alias so existing code can use DebugLog.log() without changes
enum DebugLog {
    static func log(_ message: String) {
        TheaterLog.log(message)
    }
}

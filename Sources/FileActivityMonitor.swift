import Foundation
import AppKit

/// Monitors file system activity to detect file transfers between apps.
/// Watches Downloads, Desktop, and recently-changed files to connect
/// file operations to the app sequence (e.g., "downloaded CSV from Chrome → opened in Numbers").
@MainActor
final class FileActivityMonitor: ObservableObject {

    // MARK: - Public Types

    struct FileEvent: Identifiable {
        let id = UUID()
        let timestamp: Date
        let path: String
        let fileName: String
        let fileType: FileType
        let operation: FileOperation
        let sizeBytes: Int64
        let sourceApp: String?  // app that was active when file appeared/changed

        var sizeFormatted: String {
            ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
        }
    }

    enum FileType: String {
        case image      // png, jpg, svg, webp
        case document   // pdf, docx, pages
        case spreadsheet // csv, xlsx, numbers
        case presentation // pptx, key
        case code       // swift, js, py, json
        case archive    // zip, tar, gz
        case video      // mp4, mov, avi
        case audio      // mp3, wav, m4a
        case data       // sql, xml, yaml
        case other

        static func from(extension ext: String) -> FileType {
            switch ext.lowercased() {
            case "png", "jpg", "jpeg", "gif", "svg", "webp", "ico", "tiff", "bmp", "heic":
                return .image
            case "pdf", "doc", "docx", "pages", "rtf", "txt", "md":
                return .document
            case "csv", "xlsx", "xls", "numbers", "tsv":
                return .spreadsheet
            case "pptx", "ppt", "key":
                return .presentation
            case "swift", "js", "ts", "py", "rb", "go", "rs", "java", "kt", "json", "html", "css":
                return .code
            case "zip", "tar", "gz", "rar", "7z", "dmg":
                return .archive
            case "mp4", "mov", "avi", "mkv", "webm":
                return .video
            case "mp3", "wav", "m4a", "aac", "flac":
                return .audio
            case "sql", "xml", "yaml", "yml", "plist", "toml":
                return .data
            default:
                return .other
            }
        }
    }

    enum FileOperation: String {
        case created    // new file appeared
        case modified   // existing file changed
        case moved      // file moved between directories
    }

    // MARK: - Published State

    @Published var recentEvents: [FileEvent] = []

    // MARK: - Callbacks

    /// Called when a file event is detected — feeds into FrictionDetector
    var onFileEvent: ((FileEvent) -> Void)?

    // MARK: - Private

    private var eventStream: FSEventStreamRef?
    private var isMonitoring = false
    private var knownFiles: [String: Date] = [:]  // path → last modified
    private var activeApp: String = ""
    private var scanTimer: Timer?

    /// Directories to watch for file activity
    /// Only watch Documents and temp (for autoclaw's own files).
    /// Desktop and Downloads were triggering unnecessary permission dialogs
    /// and capturing noise (browser downloads, screenshot files, etc.)
    private var watchedPaths: [String] {
        let home = NSHomeDirectory()
        return [
            home + "/Documents",
            NSTemporaryDirectory(),
        ]
    }

    // MARK: - Start / Stop

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // Snapshot current state so we only detect NEW changes
        snapshotCurrentFiles()

        // Start FSEvents stream
        startFSEventStream()

        DebugLog.log("[FileActivityMonitor] Started watching: \(watchedPaths.joined(separator: ", "))")
    }

    func stop() {
        guard isMonitoring else { return }
        isMonitoring = false

        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }

        scanTimer?.invalidate()
        scanTimer = nil

        DebugLog.log("[FileActivityMonitor] Stopped")
    }

    /// Update the active app context (called by AppState when app changes)
    func updateActiveApp(_ app: String) {
        activeApp = app
    }

    // MARK: - FSEvents

    private func startFSEventStream() {
        // Use a timer-based approach for simplicity and MainActor compatibility
        // FSEvents callbacks run on arbitrary threads which complicates @MainActor
        scanTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scanForChanges()
            }
        }
    }

    private func scanForChanges() {
        guard isMonitoring else { return }

        let fm = FileManager.default
        let now = Date()
        let recentThreshold: TimeInterval = 5  // look at files changed in last 5 seconds

        for dir in watchedPaths {
            guard let contents = try? fm.contentsOfDirectory(atPath: dir) else { continue }

            for fileName in contents {
                // Skip hidden files and system files
                if fileName.hasPrefix(".") { continue }

                let fullPath = (dir as NSString).appendingPathComponent(fileName)

                // Get file attributes
                guard let attrs = try? fm.attributesOfItem(atPath: fullPath) else { continue }
                guard let modDate = attrs[.modificationDate] as? Date else { continue }

                // Check if this is a new or recently modified file
                let age = now.timeIntervalSince(modDate)
                guard age < recentThreshold else { continue }

                // Check if we've already seen this file at this modification time
                if let knownMod = knownFiles[fullPath], knownMod == modDate { continue }

                let isNew = knownFiles[fullPath] == nil
                knownFiles[fullPath] = modDate

                // Skip directories
                var isDir: ObjCBool = false
                fm.fileExists(atPath: fullPath, isDirectory: &isDir)
                if isDir.boolValue { continue }

                // Skip our own key frame and grid files to prevent infinite loops
                if fileName.hasPrefix("autoclaw_keyframe_") || fileName.hasPrefix("autoclaw_grid_") {
                    continue
                }

                let size = attrs[.size] as? Int64 ?? 0
                let ext = (fileName as NSString).pathExtension

                let event = FileEvent(
                    timestamp: now,
                    path: fullPath,
                    fileName: fileName,
                    fileType: FileType.from(extension: ext),
                    operation: isNew ? .created : .modified,
                    sizeBytes: size,
                    sourceApp: activeApp.isEmpty ? nil : activeApp
                )

                recentEvents.append(event)
                // Keep buffer bounded
                if recentEvents.count > 50 {
                    recentEvents.removeFirst(recentEvents.count - 50)
                }

                onFileEvent?(event)

                DebugLog.log("[FileActivityMonitor] \(event.operation.rawValue): \(event.fileName) (\(event.fileType.rawValue), \(event.sizeFormatted)) from \(event.sourceApp ?? "unknown")")
            }
        }
    }

    // MARK: - Snapshot

    private func snapshotCurrentFiles() {
        let fm = FileManager.default
        for dir in watchedPaths {
            guard let contents = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for fileName in contents {
                if fileName.hasPrefix(".") { continue }
                let fullPath = (dir as NSString).appendingPathComponent(fileName)
                if let attrs = try? fm.attributesOfItem(atPath: fullPath),
                   let modDate = attrs[.modificationDate] as? Date {
                    knownFiles[fullPath] = modDate
                }
            }
        }
    }

    // MARK: - Query

    /// Recent file events involving a specific app
    func events(for app: String, limit: Int = 10) -> [FileEvent] {
        recentEvents
            .filter { $0.sourceApp == app }
            .suffix(limit)
            .reversed()
    }

    /// Recent file events of a specific type
    func events(ofType type: FileType, limit: Int = 10) -> [FileEvent] {
        recentEvents
            .filter { $0.fileType == type }
            .suffix(limit)
            .reversed()
    }

    /// Detect file transfer pattern: file created while in App A, then App B becomes active
    /// Returns (file, sourceApp, destApp) tuples
    func detectTransfers(currentApp: String) -> [(FileEvent, String, String)] {
        var transfers: [(FileEvent, String, String)] = []

        for event in recentEvents.suffix(10) {
            if let source = event.sourceApp,
               source != currentApp,
               event.operation == .created,
               Date().timeIntervalSince(event.timestamp) < 60 {
                transfers.append((event, source, currentApp))
            }
        }

        return transfers
    }
}

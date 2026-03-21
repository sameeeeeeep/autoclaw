import Foundation
import Network
import os

private let logger = Logger(subsystem: "com.autoclaw.app", category: "browser-bridge")

/// WebSocket server that receives DOM events from the Autoclaw Chrome extension.
/// Runs on ws://127.0.0.1:9849, accepts connections from localhost only.
///
/// The Chrome extension captures clicks, form inputs, navigation, and form submits
/// with full CSS selectors, field names, and values — much richer than OCR alone.
@MainActor
final class BrowserBridge: ObservableObject {

    @Published var isConnected = false
    @Published var isRecording = false
    @Published var eventCount = 0

    /// Callback when a DOM event arrives (wired by AppState)
    var onDOMEvent: ((BrowserDOMEvent) -> Void)?

    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private var keepaliveTimer: Timer?
    private let port: UInt16 = 9849

    // MARK: - Start / Stop

    func start() {
        guard listener == nil else { return }

        let params = NWParameters(tls: nil)
        let wsOptions = NWProtocolWebSocket.Options()
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        do {
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            logger.error("[BrowserBridge] Failed to create listener: \(error.localizedDescription)")
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    logger.info("[BrowserBridge] WebSocket server listening on ws://127.0.0.1:\(self?.port ?? 0)")
                case .failed(let error):
                    logger.error("[BrowserBridge] Listener failed: \(error.localizedDescription)")
                    self?.stop()
                default:
                    break
                }
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleNewConnection(connection)
            }
        }

        listener?.start(queue: .main)

        // Keepalive ping every 20s — prevents Chrome MV3 service worker from sleeping
        keepaliveTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendToExtension(["type": "ping"])
            }
        }
    }

    func stop() {
        keepaliveTimer?.invalidate()
        keepaliveTimer = nil
        listener?.cancel()
        listener = nil
        activeConnection?.cancel()
        activeConnection = nil
        isConnected = false
        isRecording = false
        eventCount = 0
    }

    // MARK: - Recording Control

    /// Tell the Chrome extension to start capturing DOM events
    func startRecording() {
        isRecording = true
        eventCount = 0
        sendToExtension(["type": "start_recording"])
        logger.info("[BrowserBridge] Sent start_recording to extension")
    }

    /// Tell the Chrome extension to stop capturing DOM events
    func stopRecording() {
        isRecording = false
        sendToExtension(["type": "stop_recording"])
        logger.info("[BrowserBridge] Sent stop_recording to extension (captured \(self.eventCount) events)")
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        // Only allow one connection at a time
        activeConnection?.cancel()
        activeConnection = connection

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.isConnected = true
                    logger.info("[BrowserBridge] Chrome extension connected")
                case .failed, .cancelled:
                    self?.isConnected = false
                    self?.activeConnection = nil
                    logger.info("[BrowserBridge] Chrome extension disconnected")
                default:
                    break
                }
            }
        }

        connection.start(queue: .main)
        receiveMessage(on: connection)
    }

    private func receiveMessage(on connection: NWConnection) {
        connection.receiveMessage { [weak self] content, context, isComplete, error in
            Task { @MainActor in
                if let data = content, !data.isEmpty {
                    self?.handleMessage(data)
                }

                if let error = error {
                    logger.error("[BrowserBridge] Receive error: \(error.localizedDescription)")
                    return
                }

                // Continue receiving
                if connection.state == .ready {
                    self?.receiveMessage(on: connection)
                }
            }
        }
    }

    private func handleMessage(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.warning("[BrowserBridge] Invalid JSON message")
            return
        }

        let messageType = json["type"] as? String ?? ""

        switch messageType {
        case "extension_connected":
            let version = json["version"] as? String ?? "unknown"
            logger.info("[BrowserBridge] Extension v\(version) connected")
            // If we're already recording, tell the extension
            if isRecording {
                sendToExtension(["type": "start_recording"])
            }

        case "dom_event":
            guard let eventData = json["event"] as? [String: Any] else { return }
            if let domEvent = parseDOMEvent(eventData) {
                eventCount += 1
                onDOMEvent?(domEvent)
            }

        case "pong":
            break  // keepalive response

        default:
            logger.info("[BrowserBridge] Unknown message type: \(messageType)")
        }
    }

    // MARK: - Send to Extension

    private func sendToExtension(_ message: [String: Any]) {
        guard let connection = activeConnection, connection.state == .ready else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "ws", metadata: [metadata])

        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { error in
            if let error = error {
                logger.error("[BrowserBridge] Send error: \(error.localizedDescription)")
            }
        })
    }

    // MARK: - Parse DOM Event

    private func parseDOMEvent(_ data: [String: Any]) -> BrowserDOMEvent? {
        guard let typeStr = data["type"] as? String,
              let eventType = BrowserDOMEvent.EventType(rawValue: typeStr) else {
            return nil
        }

        return BrowserDOMEvent(
            type: eventType,
            url: data["url"] as? String,
            pageTitle: data["pageTitle"] as? String,
            selector: data["selector"] as? String,
            tagName: data["tagName"] as? String,
            elementText: data["elementText"] as? String,
            fieldName: data["fieldName"] as? String,
            value: data["value"] as? String,
            formAction: data["formAction"] as? String
        )
    }
}

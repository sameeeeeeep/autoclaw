import Foundation

// MARK: - Ollama Service

/// Thin HTTP client for local Ollama at localhost:11434.
/// Used by TranscribeService for Qwen text cleanup and
/// by the ambient pipeline for fast local inference.
final class OllamaService {
    private let baseURL = "http://127.0.0.1:11434"
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Generate (non-streaming)

    /// Send a prompt to a local Ollama model and return the full response.
    func generate(
        model: String = "qwen2.5:3b",
        prompt: String,
        system: String? = nil
    ) async throws -> String {
        let url = URL(string: "\(baseURL)/api/generate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false
        ]
        if let system = system {
            body["system"] = system
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OllamaError.httpError(statusCode: http.statusCode, body: body)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["response"] as? String else {
            throw OllamaError.parseError
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Health Check

    /// Quick check if Ollama is running and the model is available.
    func isAvailable(model: String = "qwen2.5:3b") async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return false }
        do {
            let (data, _) = try await session.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else { return false }
            return models.contains { ($0["name"] as? String)?.hasPrefix(model) == true }
        } catch {
            return false
        }
    }
}

// MARK: - Errors

enum OllamaError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case parseError
    case notRunning

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from Ollama"
        case .httpError(let code, _): return "Ollama error (HTTP \(code))"
        case .parseError: return "Could not parse Ollama response"
        case .notRunning: return "Ollama is not running. Start it with: ollama serve"
        }
    }
}

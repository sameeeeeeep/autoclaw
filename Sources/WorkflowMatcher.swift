import Foundation
import NaturalLanguage

/// Matches current recording events against saved workflow steps using Apple's on-device NLEmbedding.
/// Provides real-time similarity scores so the extraction prompt can reference similar past workflows.
@MainActor
final class WorkflowMatcher {

    /// A match result pairing a saved workflow with its similarity score.
    struct Match {
        let workflow: SavedWorkflow
        let score: Double          // 0-1, higher = more similar
        let matchedSteps: [String] // which step descriptions were closest
    }

    private let embeddingModel: NLEmbedding?

    init() {
        // Use Apple's built-in English word embedding (ships with macOS, no download needed)
        self.embeddingModel = NLEmbedding.wordEmbedding(for: .english)
        if embeddingModel == nil {
            DebugLog.log("[WorkflowMatcher] Warning: NLEmbedding not available for English")
        }
    }

    /// Find saved workflows that are similar to the current recording's events.
    /// - Parameters:
    ///   - events: Current recording events (with OCR context)
    ///   - savedWorkflows: All saved workflows to compare against
    ///   - topK: How many top matches to return
    /// - Returns: Top matching workflows sorted by score (highest first)
    func findSimilarWorkflows(
        events: [WorkflowEvent],
        savedWorkflows: [SavedWorkflow],
        topK: Int = 3
    ) -> [Match] {
        guard !events.isEmpty, !savedWorkflows.isEmpty else { return [] }

        // Build a text summary of the current recording
        let currentSummary = buildRecordingSummary(from: events)
        guard !currentSummary.isEmpty else { return [] }

        var matches: [Match] = []

        for workflow in savedWorkflows {
            let stepDescriptions = workflow.steps.map(\.description)
            let workflowText = stepDescriptions.joined(separator: ". ")

            let score = computeSimilarity(text1: currentSummary, text2: workflowText)
            if score > 0.15 { // minimum threshold to be considered a match
                let closest = findClosestSteps(currentSummary: currentSummary, steps: stepDescriptions)
                matches.append(Match(workflow: workflow, score: score, matchedSteps: closest))
            }
        }

        matches.sort { $0.score > $1.score }
        return Array(matches.prefix(topK))
    }

    /// Build a text hint for the extraction prompt based on similar workflows.
    /// Returns nil if no good matches are found.
    func buildExtractionHint(
        events: [WorkflowEvent],
        savedWorkflows: [SavedWorkflow]
    ) -> String? {
        let matches = findSimilarWorkflows(events: events, savedWorkflows: savedWorkflows)
        guard !matches.isEmpty else { return nil }

        var hint = "## Similar workflows this user has done before\n\n"
        hint += "Use these as reference for naming and structuring steps (but don't copy blindly — "
        hint += "the current recording may differ):\n\n"

        for (i, match) in matches.enumerated() {
            hint += "### Match \(i + 1): \"\(match.workflow.name)\" (similarity: \(String(format: "%.0f", match.score * 100))%)\n"
            for step in match.workflow.steps {
                hint += "- \(step.description) [tool: \(step.tool)]\n"
            }
            hint += "\n"
        }

        return hint
    }

    // MARK: - Similarity Computation

    /// Compute similarity between two text passages using averaged word embeddings.
    private func computeSimilarity(text1: String, text2: String) -> Double {
        guard let embedding = embeddingModel else {
            // Fallback: simple word overlap (Jaccard similarity)
            return jaccardSimilarity(text1: text1, text2: text2)
        }

        let vec1 = averageEmbedding(for: text1, embedding: embedding)
        let vec2 = averageEmbedding(for: text2, embedding: embedding)

        guard let v1 = vec1, let v2 = vec2 else {
            return jaccardSimilarity(text1: text1, text2: text2)
        }

        return cosineSimilarity(v1, v2)
    }

    /// Average the word embeddings for all meaningful words in a text.
    private func averageEmbedding(for text: String, embedding: NLEmbedding) -> [Double]? {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text.lowercased()

        var vectors: [[Double]] = []
        tokenizer.enumerateTokens(in: text.lowercased().startIndex..<text.lowercased().endIndex) { range, _ in
            let word = String(text.lowercased()[range])
            if let vec = embedding.vector(for: word) {
                vectors.append(vec)
            }
            return true
        }

        guard !vectors.isEmpty else { return nil }

        let dim = vectors[0].count
        var avg = [Double](repeating: 0, count: dim)
        for vec in vectors {
            for i in 0..<dim {
                avg[i] += vec[i]
            }
        }
        let n = Double(vectors.count)
        return avg.map { $0 / n }
    }

    /// Cosine similarity between two vectors.
    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, normA = 0.0, normB = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? max(0, (dot / denom + 1) / 2) : 0  // normalize from [-1,1] to [0,1]
    }

    /// Fallback: Jaccard similarity on word sets.
    private func jaccardSimilarity(text1: String, text2: String) -> Double {
        let words1 = Set(text1.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let words2 = Set(text2.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let intersection = words1.intersection(words2).count
        let union = words1.union(words2).count
        return union > 0 ? Double(intersection) / Double(union) : 0
    }

    /// Find the step descriptions from a workflow that are most similar to the current recording.
    private func findClosestSteps(currentSummary: String, steps: [String], topK: Int = 3) -> [String] {
        let scored = steps.map { step in
            (step, computeSimilarity(text1: currentSummary, text2: step))
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(topK).map(\.0)
    }

    // MARK: - Recording Summary

    /// Build a text summary from recording events suitable for embedding comparison.
    private func buildRecordingSummary(from events: [WorkflowEvent]) -> String {
        var parts: [String] = []

        // App names used
        let apps = Set(events.map(\.app)).filter { !$0.isEmpty }
        if !apps.isEmpty {
            parts.append("Apps: \(apps.joined(separator: ", "))")
        }

        // Click descriptions (most informative events)
        let clicks = events.filter { $0.type == .click }
        for click in clicks.prefix(10) {
            parts.append(click.description)
            if let ocr = click.ocrContext {
                // Extract just the "Near cursor" part for tighter matching
                if let nearRange = ocr.range(of: "Near cursor: ") {
                    let afterNear = ocr[nearRange.upperBound...]
                    let nearText = afterNear.prefix(while: { $0 != "\n" })
                    parts.append(String(nearText))
                }
            }
        }

        // Clipboard copies
        let clips = events.filter { $0.type == .clipboard }
        for clip in clips.prefix(5) {
            if let data = clip.data {
                parts.append("Copied: \(data)")
            }
        }

        // App switches with URLs
        let switches = events.filter { $0.type == .appSwitch && $0.data != nil }
        for sw in switches.prefix(5) {
            if let url = sw.data {
                parts.append("Visited: \(url)")
            }
        }

        return parts.joined(separator: ". ")
    }
}

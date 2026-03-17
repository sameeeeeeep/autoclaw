import Foundation
import Combine

@MainActor
final class ProjectStore: ObservableObject {
    @Published var projects: [Project] = []

    private let storageURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Autoclaw", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storageURL = dir.appendingPathComponent("projects.json")
        load()
    }

    func add(_ project: Project) {
        projects.append(project)
        save()
    }

    func remove(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        save()
    }

    func addFromPath(_ path: String) -> Project {
        let name = URL(fileURLWithPath: path).lastPathComponent
        var summary: String?

        // Try to read CLAUDE.md for project context
        let claudeMDPath = path + "/CLAUDE.md"
        if let content = try? String(contentsOfFile: claudeMDPath, encoding: .utf8) {
            summary = String(content.prefix(500))
        }

        let project = Project(name: name, path: path, claudeMDSummary: summary)
        add(project)
        return project
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([Project].self, from: data) else {
            return
        }
        projects = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}

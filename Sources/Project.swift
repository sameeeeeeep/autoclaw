import Foundation

struct Project: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var path: String
    var claudeMDSummary: String?

    init(id: UUID = UUID(), name: String, path: String, claudeMDSummary: String? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.claudeMDSummary = claudeMDSummary
    }
}

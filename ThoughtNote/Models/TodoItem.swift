import Foundation
import SwiftData

/// Represents an actionable to-do item extracted from a thought
@Model
final class TodoItem {
    var id: UUID
    var text: String
    var isDone: Bool
    var createdAt: Date
    var dueDate: Date?
    var priority: Int?

    /// Parent thought relationship
    var thought: Thought?

    init(
        id: UUID = UUID(),
        text: String,
        isDone: Bool = false,
        createdAt: Date = Date(),
        dueDate: Date? = nil,
        priority: Int? = nil
    ) {
        self.id = id
        self.text = text
        self.isDone = isDone
        self.createdAt = createdAt
        self.dueDate = dueDate
        self.priority = priority
    }
}

// MARK: - Codable DTO for JSON parsing
extension TodoItem {
    struct DTO: Codable {
        let text: String
        let dueDate: Date?
        let priority: Int?

        enum CodingKeys: String, CodingKey {
            case text
            case dueDate
            case priority
        }
    }

    convenience init(from dto: DTO) {
        self.init(
            text: dto.text,
            dueDate: dto.dueDate,
            priority: dto.priority
        )
    }
}

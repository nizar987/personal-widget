import Foundation

struct Note: Identifiable, Codable, Hashable {
    let id: Int
    var content: String
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, content
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct NoteListResponse: Codable {
    let ok: Bool
    let data: [Note]
}

struct NoteResponse: Codable {
    let ok: Bool
    let data: Note
}

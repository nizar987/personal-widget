import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case network(Error)
    case decoding(Error)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:        return "Invalid URL"
        case .network(let e):    return "Network error: \(e.localizedDescription)"
        case .decoding(let e):   return "Decode error: \(e.localizedDescription)"
        case .server(let msg):   return "Server error: \(msg)"
        }
    }
}

struct NewTaskInput: Codable {
    let title: String
    let project: String
    let priority: Priority
    let due_date: String?
    let description: String?
    var scheduled_date: String? = nil
}

/// Partial update for PATCH /api/tasks/:id. Nil fields are left unchanged.
struct TaskPatch: Encodable {
    /// Set or clear a date field (due date or do date).
    enum DueDate {
        case set(String)
        case clear
    }

    var title: String?
    var description: String?
    var project: String?
    var priority: Priority?
    var dueDate: DueDate?
    var completed: Bool?
    /// The do date ("work on it on…").
    var scheduledDate: DueDate?

    private enum CodingKeys: String, CodingKey {
        case title, description, project, priority, completed
        case dueDate = "due_date"
        case scheduledDate = "scheduled_date"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(project, forKey: .project)
        try c.encodeIfPresent(priority, forKey: .priority)
        try c.encodeIfPresent(completed, forKey: .completed)
        switch dueDate {
        case .set(let day): try c.encode(day, forKey: .dueDate)
        case .clear: try c.encodeNil(forKey: .dueDate)
        case nil: break
        }
        switch scheduledDate {
        case .set(let day): try c.encode(day, forKey: .scheduledDate)
        case .clear: try c.encodeNil(forKey: .scheduledDate)
        case nil: break
        }
    }
}

private struct OkResponse: Decodable {
    let ok: Bool
}

actor APIClient {
    static let shared = APIClient()
    private init() {}

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    private func makeURL(path: String, query: [URLQueryItem] = []) throws -> URL {
        var comps = URLComponents(url: Constants.apiBaseURL.appendingPathComponent(path),
                                  resolvingAgainstBaseURL: false)
        if !query.isEmpty { comps?.queryItems = query }
        guard let url = comps?.url else { throw APIError.invalidURL }
        return url
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.server("No HTTP response")
        }

        if !(200...299).contains(http.statusCode) {
            if let err = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw APIError.server(err.error)
            }
            throw APIError.server("HTTP \(http.statusCode)")
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    // MARK: - Endpoints

    func fetchTasks(view: String? = nil,
                    project: String? = nil,
                    completed: Bool? = nil) async throws -> [Task] {
        var q: [URLQueryItem] = []
        if let view { q.append(.init(name: "view", value: view)) }
        if let project { q.append(.init(name: "project", value: project)) }
        if let completed { q.append(.init(name: "completed", value: completed ? "true" : "false")) }

        let url = try makeURL(path: "/api/tasks", query: q)
        let req = URLRequest(url: url)
        let result: TaskListResponse = try await perform(req)
        return result.data
    }

    func createTask(_ input: NewTaskInput) async throws -> Task {
        let url = try makeURL(path: "/api/tasks")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(input)
        let result: TaskResponse = try await perform(req)
        return result.data
    }

    func toggleTask(id: Int) async throws -> Task {
        let url = try makeURL(path: "/api/tasks/\(id)/toggle")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let result: TaskResponse = try await perform(req)
        return result.data
    }

    func updateTask(id: Int, _ patch: TaskPatch) async throws -> Task {
        let url = try makeURL(path: "/api/tasks/\(id)")
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(patch)
        let result: TaskResponse = try await perform(req)
        return result.data
    }

    func deleteTask(id: Int) async throws {
        let url = try makeURL(path: "/api/tasks/\(id)")
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        let _: OkResponse = try await perform(req)
    }

    func fetchProjects() async throws -> [String] {
        let url = try makeURL(path: "/api/tasks", query: [.init(name: "view", value: "projects")])
        let req = URLRequest(url: url)
        let result: ProjectsResponse = try await perform(req)
        return result.data.filter { !$0.isEmpty }
    }

    // MARK: - Notes

    func fetchNotes(search: String? = nil, limit: Int? = nil) async throws -> [Note] {
        var q: [URLQueryItem] = []
        if let search, !search.isEmpty { q.append(.init(name: "search", value: search)) }
        if let limit { q.append(.init(name: "limit", value: String(limit))) }
        let url = try makeURL(path: "/api/notes", query: q)
        let req = URLRequest(url: url)
        let result: NoteListResponse = try await perform(req)
        return result.data
    }

    func createNote(content: String) async throws -> Note {
        let url = try makeURL(path: "/api/notes")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["content": content])
        let result: NoteResponse = try await perform(req)
        return result.data
    }

    func updateNote(id: Int, content: String) async throws -> Note {
        let url = try makeURL(path: "/api/notes/\(id)")
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["content": content])
        let result: NoteResponse = try await perform(req)
        return result.data
    }

    func deleteNote(id: Int) async throws {
        let url = try makeURL(path: "/api/notes/\(id)")
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        let _: OkResponse = try await perform(req)
    }
}


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

    func fetchProjects() async throws -> [String] {
        let url = try makeURL(path: "/api/tasks", query: [.init(name: "view", value: "projects")])
        let req = URLRequest(url: url)
        let result: ProjectsResponse = try await perform(req)
        return result.data.filter { !$0.isEmpty }
    }
}

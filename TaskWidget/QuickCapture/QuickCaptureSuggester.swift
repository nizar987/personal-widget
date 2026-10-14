import Foundation

/// A previously used task, offered so repeat tasks can be captured in a couple of keystrokes.
struct QuickCaptureHistoryItem: Equatable {
    let title: String
    let project: String
    let priority: Priority
}

struct QuickCaptureSuggestion: Equatable, Identifiable {
    enum Kind: Equatable { case project, priority, date, title }

    let kind: Kind
    /// What the row shows, e.g. `#wms`, `!high`, `besok`.
    let label: String
    /// Secondary text, e.g. "3 open" or "Sun, Oct 11".
    let detail: String
    /// Full field text after accepting.
    let completion: String

    var id: String { "\(kind)-\(label)" }
}

/// Completes the word being typed in the quick-capture field.
enum QuickCaptureSuggester {
    static let limit = 5
    /// Plain words need this many letters before date words are suggested, to stay out of the way.
    static let minimumWordLength = 3
    static let minimumTitleLength = 3

    static func suggestions(for text: String, projects: [String], openCounts: [String: Int] = [:],
                            history: [QuickCaptureHistoryItem] = [], now: Date = Date(),
                            calendar: Calendar = .current) -> [QuickCaptureSuggestion] {
        // Nothing to complete right after a space.
        guard let last = text.last, !last.isWhitespace else { return [] }
        let tokenStart = text.lastIndex(where: \.isWhitespace).map { text.index(after: $0) } ?? text.startIndex
        let token = String(text[tokenStart...])
        let head = String(text[..<tokenStart])

        let results: [QuickCaptureSuggestion]
        switch token.first {
        case "#":
            results = projectSuggestions(String(token.dropFirst()), head: head, projects: projects, openCounts: openCounts)
        case "!":
            results = prioritySuggestions(String(token.dropFirst()), head: head)
        case "@":
            results = dateSuggestions(String(token.dropFirst()), head: head, prefix: "@", minimumLength: 0,
                                      now: now, calendar: calendar)
        default:
            let dates = dateSuggestions(token, head: head, prefix: "", minimumLength: minimumWordLength,
                                        now: now, calendar: calendar)
            results = dates + titleSuggestions(text, history: history)
        }
        return Array(results.prefix(limit))
    }

    // MARK: - Kinds

    private static func projectSuggestions(_ query: String, head: String, projects: [String],
                                           openCounts: [String: Int]) -> [QuickCaptureSuggestion] {
        let q = query.lowercased()
        let matches = projects.filter { q.isEmpty || $0.lowercased().contains(q) }
            .sorted { a, b in
                let (pa, pb) = (a.lowercased().hasPrefix(q), b.lowercased().hasPrefix(q))
                if pa != pb { return pa }
                let (ca, cb) = (openCounts[a] ?? 0, openCounts[b] ?? 0)
                return ca != cb ? ca > cb : a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            }
        return matches.map { name in
            let open = openCounts[name] ?? 0
            return QuickCaptureSuggestion(kind: .project, label: "#\(name)",
                                          detail: open == 0 ? "project" : "\(open) open",
                                          completion: "\(head)#\(name) ")
        }
    }

    private static let priorities: [(token: String, priority: Priority, aliases: [String])] = [
        ("high", .high, ["high", "tinggi", "urgent", "penting"]),
        ("medium", .medium, ["medium", "sedang"]),
        ("low", .low, ["low", "rendah"]),
    ]

    private static func prioritySuggestions(_ query: String, head: String) -> [QuickCaptureSuggestion] {
        let q = query.lowercased()
        return priorities
            .filter { q.isEmpty || $0.aliases.contains { $0.hasPrefix(q) } }
            .map { item in
                QuickCaptureSuggestion(kind: .priority, label: "!\(item.token)",
                                       detail: "\(dot(item.priority)) \(item.priority.displayName)",
                                       completion: "\(head)!\(item.token) ")
            }
    }

    /// Date words in the order people reach for them; each is checked against the real parser.
    private static let dateWords = [
        "today", "tomorrow", "besok", "lusa", "hari ini", "next week", "minggu depan", "this weekend",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "senin", "selasa", "rabu", "kamis", "jumat", "sabtu",
    ]
    private static let atWords = [
        "today", "tomorrow", "besok", "lusa", "mon", "tue", "wed", "thu", "fri", "sat", "sun",
        "senin", "selasa", "rabu", "kamis", "jumat", "sabtu", "minggu",
    ]

    private static func dateSuggestions(_ query: String, head: String, prefix: String, minimumLength: Int,
                                        now: Date, calendar: Calendar) -> [QuickCaptureSuggestion] {
        let q = query.lowercased()
        guard q.count >= minimumLength else { return [] }
        let words = prefix == "@" ? atWords : dateWords
        return words
            .filter { $0.hasPrefix(q) && $0 != q }
            .compactMap { word -> QuickCaptureSuggestion? in
                let phrase = prefix + word
                let parsed = QuickCaptureParser.parse(phrase, now: now, calendar: calendar)
                guard let date = parsed.scheduled ?? parsed.due else { return nil }
                return QuickCaptureSuggestion(kind: .date, label: phrase, detail: describe(date, now: now, calendar: calendar),
                                              completion: "\(head)\(phrase) ")
            }
    }

    /// Whole-text match against earlier titles; accepting also fills their project and priority.
    private static func titleSuggestions(_ text: String, history: [QuickCaptureHistoryItem]) -> [QuickCaptureSuggestion] {
        let typed = text.trimmingCharacters(in: .whitespaces)
        guard typed.count >= minimumTitleLength,
              !typed.contains(where: { "#!@".contains($0) }) else { return [] }
        let q = typed.lowercased()
        let matches = history.filter { item in
            let title = item.title.lowercased()
            return title != q && (title.hasPrefix(q) || title.split(separator: " ").contains { $0.hasPrefix(q) })
        }
        return matches.prefix(3).map { item in
            let project = item.project.isEmpty ? "" : " #\(item.project)"
            return QuickCaptureSuggestion(
                kind: .title, label: item.title,
                detail: [item.project, "\(dot(item.priority)) \(item.priority.displayName)"]
                    .filter { !$0.isEmpty }.joined(separator: " · "),
                completion: "\(item.title)\(project) !\(item.priority.rawValue) "
            )
        }
    }

    // MARK: - Helpers

    private static func dot(_ priority: Priority) -> String {
        switch priority {
        case .high: return "🔴"
        case .medium: return "🟡"
        case .low: return "🔵"
        }
    }

    private static func describe(_ date: Date, now: Date, calendar: Calendar) -> String {
        let today = calendar.startOfDay(for: now)
        if date == today { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today), date == tomorrow { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// Unique titles, most recent first (higher id = newer).
    static func history(from tasks: [Task]) -> [QuickCaptureHistoryItem] {
        var seen = Set<String>()
        return tasks.sorted { $0.id > $1.id }.compactMap { task in
            let key = task.title.lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { return nil }
            return QuickCaptureHistoryItem(title: task.title, project: task.project, priority: task.priority)
        }
    }

    static func openCounts(from tasks: [Task]) -> [String: Int] {
        tasks.filter { !$0.completed }.reduce(into: [:]) { $0[$1.project, default: 0] += 1 }
    }
}

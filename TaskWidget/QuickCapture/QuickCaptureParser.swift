import Foundation

/// What the quick-capture field understood from the typed text.
struct QuickCaptureDraft: Equatable {
    var title: String
    var project: String?
    var priority: Priority?
    var due: Date?
}

/// Parses inline shortcuts out of a one-line task, English and Indonesian:
///
/// - `#project` — existing projects match case-insensitively
/// - `!high` `!h` `!!!` `!tinggi` · `!medium` `!m` `!!` `!sedang` · `!low` `!l` `!` `!rendah`
/// - `today` `hari ini` · `tomorrow` `tmrw` `besok` · `lusa` · `next week` `minggu depan`
/// - weekdays: `friday` `next friday` `jumat` `hari minggu`, or any `@fri` / `@minggu`
/// - `in 3 days` `3 hari lagi` · `12/10` `12/10/2026` `2026-10-12` · `12 okt` `oct 12`
///
/// Recognised tokens are removed from the title; when a field appears twice the last one wins.
enum QuickCaptureParser {
    static func parse(_ text: String, projects: [String] = [], now: Date = Date(),
                      calendar: Calendar = .current) -> QuickCaptureDraft {
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var draft = QuickCaptureDraft(title: "")
        var kept: [String] = []
        let today = calendar.startOfDay(for: now)
        var i = 0

        while i < tokens.count {
            let token = tokens[i]
            if let project = projectName(token, known: projects) {
                draft.project = project
                i += 1
            } else if let priority = priority(token) {
                draft.priority = priority
                i += 1
            } else if let (date, used) = DatePhrase.match(tokens, at: i, today: today, calendar: calendar) {
                draft.due = date
                i += used
            } else {
                kept.append(token)
                i += 1
            }
        }
        draft.title = kept.joined(separator: " ")
        return draft
    }

    // MARK: - Project & priority

    private static func projectName(_ token: String, known: [String]) -> String? {
        guard token.hasPrefix("#"), token.count > 1 else { return nil }
        let name = String(token.dropFirst()).trimmingCharacters(in: .punctuationCharacters.subtracting(["-", "_"]))
        guard !name.isEmpty else { return nil }
        return known.first { $0.caseInsensitiveCompare(name) == .orderedSame } ?? name
    }

    private static let priorityWords: [String: Priority] = [
        "high": .high, "h": .high, "tinggi": .high, "penting": .high, "urgent": .high, "1": .high,
        "medium": .medium, "med": .medium, "m": .medium, "sedang": .medium, "2": .medium,
        "low": .low, "l": .low, "rendah": .low, "3": .low,
    ]

    private static func priority(_ token: String) -> Priority? {
        guard token.hasPrefix("!") else { return nil }
        if token.allSatisfy({ $0 == "!" }) {
            switch token.count {
            case 1: return .low
            case 2: return .medium
            default: return .high
            }
        }
        return priorityWords[String(token.dropFirst()).lowercased()]
    }
}

// MARK: - Dates

private enum DatePhrase {
    /// Tries every phrase shape at `index`; returns the date and how many tokens it used.
    static func match(_ tokens: [String], at index: Int, today: Date, calendar: Calendar) -> (Date, Int)? {
        let words = tokens[index...].prefix(3).map { $0.lowercased().trimmingCharacters(in: trailingPunctuation) }
        guard let first = words.first else { return nil }

        // `@...` forces a single-token date, including ambiguous words like `@sun` or `@minggu`.
        if first.hasPrefix("@") {
            let word = String(first.dropFirst())
            return single(word, today: today, calendar: calendar, allowAmbiguous: true).map { ($0, 1) }
        }
        if words.count >= 3, let date = threeWords(Array(words.prefix(3)), today: today, calendar: calendar) {
            return (date, 3)
        }
        if words.count >= 2, let date = twoWords(words[0], words[1], today: today, calendar: calendar) {
            return (date, 2)
        }
        return single(first, today: today, calendar: calendar, allowAmbiguous: false).map { ($0, 1) }
    }

    private static let trailingPunctuation = CharacterSet(charactersIn: ",.;:")

    private static func single(_ word: String, today: Date, calendar: Calendar, allowAmbiguous: Bool) -> Date? {
        switch word {
        case "today", "tdy", "hariini": return today
        case "tomorrow", "tmrw", "tmr", "besok": return add(1, to: today, calendar)
        case "lusa": return add(2, to: today, calendar)
        default: break
        }
        if let weekday = weekday(word, allowAmbiguous: allowAmbiguous) {
            return upcoming(weekday, from: today, calendar: calendar, skipToday: false)
        }
        return numericDate(word, today: today, calendar: calendar)
    }

    private static func twoWords(_ a: String, _ b: String, today: Date, calendar: Calendar) -> Date? {
        switch (a, b) {
        case ("hari", "ini"): return today
        case ("next", "week"), ("minggu", "depan"), ("pekan", "depan"):
            let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
            return add(7, to: thisWeek, calendar)
        case ("this", "weekend"), ("akhir", "pekan"):
            return upcoming(7, from: today, calendar: calendar, skipToday: false)
        default: break
        }
        if a == "next", let weekday = weekday(b, allowAmbiguous: false) {
            return upcoming(weekday, from: today, calendar: calendar, skipToday: true)
        }
        if a == "hari", let weekday = weekday(b, allowAmbiguous: true) {
            return upcoming(weekday, from: today, calendar: calendar, skipToday: false)
        }
        if let day = Int(a), let month = month(b) { return dayMonth(day, month, today: today, calendar: calendar) }
        if let month = month(a), let day = Int(b) { return dayMonth(day, month, today: today, calendar: calendar) }
        return nil
    }

    private static func threeWords(_ w: [String], today: Date, calendar: Calendar) -> Date? {
        if w == ["day", "after", "tomorrow"] { return add(2, to: today, calendar) }
        if w[0] == "in", let n = Int(w[1]), ["day", "days"].contains(w[2]) { return add(n, to: today, calendar) }
        if w[0] == "dalam", let n = Int(w[1]), w[2] == "hari" { return add(n, to: today, calendar) }
        if let n = Int(w[0]), w[1] == "hari", w[2] == "lagi" { return add(n, to: today, calendar) }
        return nil
    }

    // MARK: Vocabulary

    /// Calendar weekday numbers (1 = Sunday). Short or ambiguous forms need `@`.
    private static let weekdays: [String: Int] = [
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7,
        "senin": 2, "selasa": 3, "rabu": 4, "kamis": 5, "jumat": 6, "jum'at": 6, "sabtu": 7,
    ]
    private static let ambiguousWeekdays: [String: Int] = [
        "sun": 1, "mon": 2, "tue": 3, "tues": 3, "wed": 4, "thu": 5, "thur": 5, "thurs": 5,
        "fri": 6, "sat": 7, "minggu": 1, "ahad": 1,
    ]

    private static func weekday(_ word: String, allowAmbiguous: Bool) -> Int? {
        weekdays[word] ?? (allowAmbiguous ? ambiguousWeekdays[word] : nil)
    }

    private static let months: [String: Int] = {
        let names: [[String]] = [
            ["jan", "january", "januari"], ["feb", "february", "februari", "peb"], ["mar", "march", "maret"],
            ["apr", "april"], ["may", "mei"], ["jun", "june", "juni"], ["jul", "july", "juli"],
            ["aug", "august", "agu", "agt", "agustus"], ["sep", "sept", "september"],
            ["oct", "october", "okt", "oktober"], ["nov", "november", "nop"], ["dec", "december", "des", "desember"],
        ]
        return Dictionary(uniqueKeysWithValues: names.enumerated().flatMap { index, aliases in
            aliases.map { ($0, index + 1) }
        })
    }()

    private static func month(_ word: String) -> Int? { months[word] }

    // MARK: Builders

    private static func add(_ days: Int, to date: Date, _ calendar: Calendar) -> Date? {
        calendar.date(byAdding: .day, value: days, to: date)
    }

    /// Next date with `weekday`; today counts unless `skipToday`.
    private static func upcoming(_ weekday: Int, from today: Date, calendar: Calendar, skipToday: Bool) -> Date? {
        var ahead = (weekday - calendar.component(.weekday, from: today) + 7) % 7
        if ahead == 0 && skipToday { ahead = 7 }
        return add(ahead, to: today, calendar)
    }

    /// `12/10`, `12/10/26`, `12/10/2026` (day first) or ISO `2026-10-12`.
    private static func numericDate(_ word: String, today: Date, calendar: Calendar) -> Date? {
        if word.count == 10, word.dropFirst(4).first == "-" {
            return TaskDate.date(from: word)
        }
        let parts = word.split(separator: "/").map(String.init)
        guard (2...3).contains(parts.count), let day = Int(parts[0]), let month = Int(parts[1]) else { return nil }
        if parts.count == 3, let rawYear = Int(parts[2]) {
            let year = rawYear < 100 ? 2000 + rawYear : rawYear
            return make(year: year, month: month, day: day, calendar: calendar)
        }
        return dayMonth(day, month, today: today, calendar: calendar)
    }

    /// Day + month without a year: this year, or next year if that date already passed.
    private static func dayMonth(_ day: Int, _ month: Int, today: Date, calendar: Calendar) -> Date? {
        let year = calendar.component(.year, from: today)
        guard let date = make(year: year, month: month, day: day, calendar: calendar) else { return nil }
        return date < today ? make(year: year + 1, month: month, day: day, calendar: calendar) : date
    }

    /// Rejects impossible dates like 31/02 instead of letting Calendar roll them over.
    private static func make(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day,
              calendar.component(.month, from: date) == month else { return nil }
        return date
    }
}

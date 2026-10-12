import SwiftUI
import Observation

/// Single source of truth for the Notes screen. Mutations are optimistic and roll back on failure.
@Observable
@MainActor
final class NoteStore {
    private(set) var notes: [Note] = []
    private(set) var isLoading = false
    private(set) var isOffline = false
    var errorMessage: String?
    var search = ""

    private let api = APIClient.shared
    private let springy = Animation.spring(response: 0.38, dampingFraction: 0.82)

    // MARK: - Loading

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let query = search.trimmingCharacters(in: .whitespaces)
            let fresh = try await api.fetchNotes(search: query.isEmpty ? nil : query)
            withAnimation(springy) { notes = fresh }
            isOffline = false
            errorMessage = nil
        } catch {
            isOffline = true
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Mutations

    @discardableResult
    func create(content: String) async -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            let created = try await api.createNote(content: trimmed)
            withAnimation(springy) { notes.insert(created, at: 0) }
            return true
        } catch {
            report(error)
            return false
        }
    }

    func update(_ note: Note, content: String) async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != note.content else { return }
        var updated = note
        updated.content = trimmed
        replaceLocally(updated)
        do {
            replaceLocally(try await api.updateNote(id: note.id, content: trimmed))
        } catch {
            replaceLocally(note)
            report(error)
        }
    }

    func delete(_ note: Note) async {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        _ = withAnimation(springy) { notes.remove(at: index) }
        do {
            try await api.deleteNote(id: note.id)
        } catch {
            withAnimation(springy) { notes.insert(note, at: min(index, notes.count)) }
            report(error)
        }
    }

    // MARK: - Helpers

    private func replaceLocally(_ note: Note) {
        guard let i = notes.firstIndex(where: { $0.id == note.id }) else { return }
        withAnimation(springy) {
            var copy = notes
            copy[i] = note
            notes = copy
        }
    }

    private func report(_ error: Error) {
        errorMessage = error.localizedDescription
    }
}

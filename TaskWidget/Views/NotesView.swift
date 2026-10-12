import SwiftUI

/// Notes screen: quick-add at top, searchable list below. Notes are separate from tasks —
/// plain free-form text, newest first.
struct NotesView: View {
    let store: NoteStore
    @State private var draft = ""
    @State private var editingNote: Note?
    @State private var editText = ""
    @FocusState private var addFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            quickAdd
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            searchBar
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            if store.isLoading && store.notes.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else if store.notes.isEmpty {
                Spacer()
                emptyState
                Spacer()
            } else {
                noteList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { await store.load() }
        .sheet(item: $editingNote) { note in
            NoteEditorSheet(note: note, text: $editText) { newContent in
                _Concurrency.Task { await store.update(note, content: newContent) }
            }
            .frame(width: 420, height: 320)
        }
    }

    /// In-view search field (kept inside NotesView, not the toolbar — the window already
    /// owns a toolbar search item, and a second one crashes AppKit's NSToolbar).
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tertiary)
            TextField("Search notes", text: searchBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
            if !store.search.isEmpty {
                Button {
                    store.search = ""
                    _Concurrency.Task { await store.load() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var searchBinding: Binding<String> {
        Binding(
            get: { store.search },
            set: { value in
                store.search = value
                debounceLoad()
            }
        )
    }

    @State private var searchTask: _Concurrency.Task<Void, Never>?

    /// Debounce so each keystroke doesn't fire a network request.
    private func debounceLoad() {
        searchTask?.cancel()
        searchTask = _Concurrency.Task {
            try? await _Concurrency.Task.sleep(for: .milliseconds(280))
            guard !_Concurrency.Task.isCancelled else { return }
            await store.load()
        }
    }

    // MARK: - Quick add

    private var quickAdd: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "note.text.badge.plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 8)
            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text("New note…  (⌘↵ save)")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $draft)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .focused($addFocused)
                    .frame(minHeight: 40, maxHeight: 120)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button { submit() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .padding(.top, 4)
            }
        }
        .card()
        .onAppear { addFocused = true }
    }

    private func submit() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        draft = ""
        _Concurrency.Task {
            let ok = await store.create(content: text)
            if !ok { draft = text }
        }
    }

    // MARK: - List

    private var noteList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(store.notes) { note in
                    NoteRow(note: note,
                            onEdit: {
                                editText = note.content
                                editingNote = note
                            },
                            onDelete: { _Concurrency.Task { await store.delete(note) } })
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: store.search.isEmpty ? "note.text" : "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(store.search.isEmpty ? "No notes yet" : "No notes match \"\(store.search)\"")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            if store.search.isEmpty {
                Text("Write one above — notes are plain text, newest first.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Row

private struct NoteRow: View {
    let note: Note
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(note.content)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(relativeTime)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    if note.updatedAt != note.createdAt {
                        Text("· edited")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer(minLength: 8)
            if hovering {
                HStack(spacing: 4) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Edit note")
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.today)
                    .help("Delete note")
                }
                .padding(.top, 2)
            }
        }
        .card()
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: onEdit)
    }

    private var relativeTime: String {
        guard let date = TaskDate.timestamp(from: note.createdAt) else { return note.createdAt }
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Editor sheet

private struct NoteEditorSheet: View {
    let note: Note
    @Binding var text: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Note")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(text)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            Divider()
            TextEditor(text: $text)
                .font(.system(size: 14))
                .padding(8)
        }
    }
}

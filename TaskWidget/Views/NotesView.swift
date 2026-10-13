import SwiftUI
import AppKit

/// Notes screen: header, composer, then notes grouped by day (newest first). Notes are plain
/// free-form text, separate from tasks; the first line reads as the title.
///
/// Text input uses `TextField(axis: .vertical)` rather than `TextEditor`: a self-sizing
/// `TextEditor` (NSTextView in a scroll view) inside the window's GeometryReader detail kept
/// re-laying out until AppKit threw, crashing the app as soon as Notes opened.
struct NotesView: View {
    let store: NoteStore
    /// The window's toolbar search field. Notes reuse it instead of adding their own — a second
    /// toolbar search item crashes NSToolbar.
    let search: String
    /// Shared with ⌘N in the toolbar, which focuses the composer on this screen.
    var composerFocus: FocusState<Bool>.Binding

    @State private var draft = ""
    @State private var isSaving = false
    @State private var editingID: Int?
    @State private var editText = ""
    @State private var pendingDelete: Note?
    @State private var searchTask: _Concurrency.Task<Void, Never>?

    private var query: String { search.trimmingCharacters(in: .whitespaces) }
    private var groups: [NoteGroup] { NoteGroup.make(from: store.notes, now: Date()) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if store.isOffline {
                    offlineBanner
                } else if let error = store.errorMessage {
                    errorBanner(error)
                }
                NoteComposer(text: $draft, isSaving: isSaving, focus: composerFocus, onSave: submit)
                content
            }
            .padding(24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .animation(AppStyle.spring, value: groups.map(\.id))
        }
        .task { await reload() }
        .onChange(of: search) { debounceReload() }
        .onDisappear { searchTask?.cancel() }
        .confirmationDialog("Delete “\(pendingDelete?.parts.title ?? "")”?", isPresented: deleteBinding,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let note = pendingDelete { delete(note) }
            }
        } message: {
            Text("This can't be undone.")
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text("Notes")
            } icon: {
                Image(systemName: SidebarItem.notes.icon).foregroundStyle(SidebarItem.notes.accent)
            }
            .font(.system(size: 26, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
    }

    private var subtitle: String {
        let count = store.notes.count
        if !query.isEmpty { return "\(count) \(count == 1 ? "result" : "results") for “\(query)”" }
        return "\(count) \(count == 1 ? "note" : "notes") · plain text, newest first"
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading && store.notes.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
        } else if store.notes.isEmpty {
            emptyState
        } else {
            ForEach(groups) { group in
                groupCard(group)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
    }

    private func groupCard(_ group: NoteGroup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            NoteGroupHeader(group: group)
                .padding(.bottom, 4)
            ForEach(group.notes) { note in
                NoteRow(note: note,
                        isEditing: editingID == note.id,
                        editText: $editText,
                        onEdit: { startEditing(note) },
                        onCommit: { commitEdit(note) },
                        onCancel: cancelEdit,
                        onDelete: { pendingDelete = note })
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                if note.id != group.notes.last?.id {
                    Divider().opacity(0.5).padding(.horizontal, 10)
                }
            }
        }
        .card(padding: 10)
    }

    private var offlineBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash").foregroundStyle(Palette.upcoming)
            VStack(alignment: .leading, spacing: 2) {
                Text("Can't reach the backend").font(.system(size: 13, weight: .semibold))
                Text("Start the TaskWidget server (\(Constants.apiHostLabel)) — see backend/README.md.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Retry") { _Concurrency.Task { await store.load() } }
        }
        .card()
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.today)
            Text(message)
                .font(.system(size: 13))
                .lineLimit(2)
            Spacer()
            Button("Dismiss") { store.errorMessage = nil }
        }
        .card()
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: query.isEmpty ? "note.text" : "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(SidebarItem.notes.accent.gradient)
            Text(query.isEmpty ? "No notes yet" : "No notes match “\(query)”")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            Text(query.isEmpty ? "Write one above, or press ⌥Space anywhere and hit ⇥ to switch to Note."
                               : "Try a different search.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: - Actions

    private func submit() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isSaving else { return }
        isSaving = true
        _Concurrency.Task {
            let ok = await store.create(content: text)
            isSaving = false
            if ok {
                draft = ""
                composerFocus.wrappedValue = true
            }
        }
    }

    private func startEditing(_ note: Note) {
        editText = note.content
        withAnimation(AppStyle.spring) { editingID = note.id }
    }

    private func commitEdit(_ note: Note) {
        let text = editText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        withAnimation(AppStyle.spring) { editingID = nil }
        _Concurrency.Task { await store.update(note, content: text) }
    }

    private func cancelEdit() {
        withAnimation(AppStyle.spring) { editingID = nil }
    }

    private func delete(_ note: Note) {
        if editingID == note.id { editingID = nil }
        pendingDelete = nil
        _Concurrency.Task { await store.delete(note) }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    // MARK: - Search

    private func reload() async {
        store.search = search
        await store.load()
    }

    /// Debounce so each keystroke doesn't fire a network request.
    private func debounceReload() {
        searchTask?.cancel()
        searchTask = _Concurrency.Task {
            try? await _Concurrency.Task.sleep(for: .milliseconds(280))
            guard !_Concurrency.Task.isCancelled else { return }
            await reload()
        }
    }
}

// MARK: - Composer

/// "Write a note…" card. ↵ saves, ⌥↵ inserts a line break.
private struct NoteComposer: View {
    @Binding var text: String
    let isSaving: Bool
    var focus: FocusState<Bool>.Binding
    let onSave: () -> Void

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    private var isActive: Bool { focus.wrappedValue || !text.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSaving ? "hourglass" : "square.and.pencil")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SidebarItem.notes.accent)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 18)
                TextField("Write a note…", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .lineLimit(1...10)
                    .focused(focus)
                    .onSubmit(onSave)
            }
            if isActive {
                HStack(spacing: 8) {
                    Text("↵ save   ⌥↵ new line   first line becomes the title")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Button("Save", action: onSave)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!canSave)
                }
                .padding(.leading, 28)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .card(padding: 12)
        .animation(AppStyle.spring, value: isActive)
    }
}

// MARK: - Groups

/// Notes bucketed by when they were written: Today, Yesterday, Previous 7 Days, Earlier.
private struct NoteGroup: Identifiable {
    let id: String
    let title: String
    let icon: String
    let accent: Color
    let notes: [Note]

    static func make(from notes: [Note], now: Date) -> [NoteGroup] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let yesterday = TaskDate.day(offset: -1, from: now)
        let weekAgo = TaskDate.day(offset: -7, from: now)
        var buckets: [[Note]] = [[], [], [], []]
        for note in notes {
            switch note.createdDate.map({ cal.startOfDay(for: $0) }) {
            case let day? where day >= today: buckets[0].append(note)
            case let day? where day >= yesterday: buckets[1].append(note)
            case let day? where day >= weekAgo: buckets[2].append(note)
            default: buckets[3].append(note)
            }
        }
        let meta: [(id: String, title: String, icon: String, accent: Color)] = [
            ("today", "Today", "sun.max.fill", Palette.upcoming),
            ("yesterday", "Yesterday", "moon.stars.fill", Palette.important),
            ("week", "Previous 7 Days", "calendar", Palette.project),
            ("earlier", "Earlier", "archivebox.fill", .gray),
        ]
        return zip(meta, buckets).compactMap { m, bucket in
            bucket.isEmpty ? nil : NoteGroup(id: m.id, title: m.title, icon: m.icon, accent: m.accent, notes: bucket)
        }
    }
}

private struct NoteGroupHeader: View {
    let group: NoteGroup

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: group.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(group.accent)
            Text(group.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(group.accent == .gray ? Color.primary : group.accent)
            Spacer()
            CountBadge(count: group.notes.count, accent: group.accent)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Row

/// One note: bold first line, a few lines of preview, time. Click edits in place; hover shows
/// copy / edit / delete; right-click has the same actions.
private struct NoteRow: View {
    let note: Note
    let isEditing: Bool
    @Binding var editText: String
    let onEdit: () -> Void
    let onCommit: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false
    @FocusState private var editorFocused: Bool

    var body: some View {
        Group {
            if isEditing { editor } else { display }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isEditing ? Color.accentColor.opacity(0.08)
                                : (hovering ? Color.primary.opacity(0.04) : .clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isEditing ? Color.accentColor.opacity(0.35) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .contextMenu {
            Button("Edit", systemImage: "pencil", action: onEdit)
            Button("Copy", systemImage: "doc.on.doc", action: copy)
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private var display: some View {
        let parts = note.parts
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(parts.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(parts.body == nil ? 6 : 2)
                if let body = parts.body {
                    Text(body)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 9, weight: .semibold))
                    Text(NoteTime.label(for: note.createdDate, now: Date()))
                    if note.wasEdited { Text("· edited") }
                }
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 2) {
                iconButton("doc.on.doc", help: "Copy", action: copy)
                iconButton("pencil", help: "Edit", action: onEdit)
                iconButton("trash", help: "Delete", tint: Palette.today, action: onDelete)
            }
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Note", text: $editText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14, design: .rounded))
                .lineLimit(2...16)
                .focused($editorFocused)
                .onSubmit(onCommit)
                .onExitCommand(perform: onCancel)
            HStack(spacing: 8) {
                Text("↵ save   ⌥↵ new line   esc cancel")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button("Cancel", action: onCancel)
                    .controlSize(.small)
                Button("Save", action: onCommit)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear { editorFocused = true }
    }

    private func iconButton(_ symbol: String, help: String, tint: Color = .secondary,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(note.content, forType: .string)
    }
}

// MARK: - Formatting

private enum NoteTime {
    /// Time only for today/yesterday (the group header names the day), weekday + time within a
    /// week, otherwise the date.
    static func label(for date: Date?, now: Date) -> String {
        guard let date else { return "" }
        let cal = Calendar.current
        if cal.isDateInToday(date) || cal.isDateInYesterday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if date >= TaskDate.day(offset: -7, from: now) {
            return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
        if cal.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

private extension Note {
    /// First non-empty line as the title, the rest as the preview body.
    var parts: (title: String, body: String?) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lineBreak = trimmed.firstIndex(where: \.isNewline) else { return (trimmed, nil) }
        let title = trimmed[..<lineBreak].trimmingCharacters(in: .whitespaces)
        let body = trimmed[lineBreak...].trimmingCharacters(in: .whitespacesAndNewlines)
        return (title, body.isEmpty ? nil : body)
    }

    var createdDate: Date? { TaskDate.timestamp(from: createdAt) }
    var wasEdited: Bool { updatedAt != createdAt }
}

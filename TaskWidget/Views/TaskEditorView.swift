import SwiftUI

/// Inspector panel for editing every field of a task.
struct TaskEditorView: View {
    let task: Task
    let projects: [String]
    let onSave: (TaskPatch) -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onClose: () -> Void

    @State private var title = ""
    @State private var notes = ""
    @State private var project = ""
    @State private var priority: Priority = .medium
    @State private var hasDue = false
    @State private var due = Date()
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                field("Title") {
                    TextField("Task title", text: $title, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .lineLimit(1...4)
                }
                field("Notes") {
                    TextField("Add notes…", text: $notes, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(3...10)
                }
                field("Project") { projectField }
                field("Priority") {
                    Picker("Priority", selection: $priority) {
                        ForEach(Priority.allCases) { p in Text(p.displayName).tag(p) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                field("Due Date") { dueField }
                footer
            }
            .padding(16)
        }
        .confirmationDialog("Delete “\(task.title)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: onDelete)
        } message: {
            Text("This can't be undone.")
        }
        .onAppear(perform: reset)
        .onChange(of: task.id) { reset() }
        .animation(AppStyle.spring, value: hasDue)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Button(action: onToggle) {
                Label(task.completed ? "Completed" : "Mark as Done",
                      systemImage: task.completed ? "checkmark.circle.fill" : "circle")
                    .contentTransition(.symbolEffect(.replace))
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .tint(task.completed ? Palette.done : nil)
            Spacer()
            Button(action: onClose) { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .help("Close")
        }
    }

    private var projectField: some View {
        HStack(spacing: 6) {
            TextField("Project", text: $project)
                .textFieldStyle(.plain)
            Menu {
                ForEach(projects, id: \.self) { p in Button(p) { project = p } }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(projects.isEmpty)
        }
    }

    private var dueField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Has due date", isOn: $hasDue)
                .toggleStyle(.switch)
                .controlSize(.small)
            if hasDue {
                DatePicker("", selection: $due, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { quickDueButtons }
                    VStack(alignment: .leading, spacing: 6) { quickDueButtons }
                }
            }
        }
    }

    @ViewBuilder
    private var quickDueButtons: some View {
        ForEach(DueChoice.allCases.filter { $0 != .none }) { choice in
            Button(choice.title) { if let d = choice.date { due = d } }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Revert", action: reset).disabled(!hasChanges)
                Spacer()
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!hasChanges || !isValid)
            }
            Divider()
            Button(role: .destructive) { confirmDelete = true } label: {
                Label("Delete Task", systemImage: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Palette.today)
            if !task.createdAt.isEmpty {
                Text("Created \(task.createdAt)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 10)
        }
    }

    // MARK: - Draft state

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedProject: String { project.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var draftDue: String? { hasDue ? TaskDate.string(from: due) : nil }

    private var isValid: Bool { !trimmedTitle.isEmpty && !trimmedProject.isEmpty }

    private var hasChanges: Bool {
        trimmedTitle != task.title || notes != task.description || trimmedProject != task.project
            || priority != task.priority || draftDue != task.dueDay.map(TaskDate.string(from:))
    }

    private func reset() {
        title = task.title
        notes = task.description
        project = task.project
        priority = task.priority
        hasDue = task.dueDay != nil
        due = task.dueDay ?? TaskDate.day(offset: 0)
    }

    private func save() {
        var patch = TaskPatch()
        if trimmedTitle != task.title { patch.title = trimmedTitle }
        if notes != task.description { patch.description = notes }
        if trimmedProject != task.project { patch.project = trimmedProject }
        if priority != task.priority { patch.priority = priority }
        if draftDue != task.dueDay.map(TaskDate.string(from:)) {
            patch.dueDate = draftDue.map { .set($0) } ?? .clear
        }
        onSave(patch)
    }
}

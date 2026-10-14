import SwiftUI

struct TaskRowView: View {
    let task: Task
    let isSelected: Bool
    let projects: [String]
    let onToggle: () -> Void
    let onSelect: () -> Void
    let onUpdate: (TaskPatch) -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onToggle) {
                CheckCircle(isOn: task.completed, tint: Palette.color(for: task.priority))
            }
            .buttonStyle(.plain)
            .help(task.completed ? "Mark as not done" : "Mark as done")

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                    .strikethrough(task.completed, color: .secondary)
                    .foregroundStyle(task.completed ? .secondary : .primary)
                    .lineLimit(2)
                if !task.description.isEmpty {
                    Text(task.description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                meta
            }

            Spacer(minLength: 8)

            if isHovering {
                hoverActions.transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : (isHovering ? Color.primary.opacity(0.05) : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering } }
        .contextMenu { TaskContextMenu(task: task, projects: projects, onToggle: onToggle,
                                       onEdit: onSelect, onUpdate: onUpdate, onDelete: onDelete) }
    }

    private var meta: some View {
        HStack(spacing: 6) {
            if let doText = DoLabel.text(for: task, now: Date()) {
                Chip(text: doText, icon: "play.circle", tint: task.completed ? .secondary : DoLabel.color(for: task, now: Date()))
                    .help("Do date")
            }
            if let due = DueLabel.text(for: task, now: Date()) {
                Chip(text: due, icon: "flag.checkered", tint: task.completed ? .secondary : DueLabel.color(for: task, now: Date()))
                    .help("Due date")
            }
            Chip(text: task.project, icon: "folder", tint: Palette.project)
            if task.priority == .high && !task.completed {
                Image(systemName: "flag.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.today)
            }
        }
    }

    private var hoverActions: some View {
        HStack(spacing: 2) {
            Menu {
                DateChoiceMenus(onUpdate: onUpdate)
            } label: {
                Image(systemName: "calendar")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 26)
            .help("Change do date or due date")

            iconButton("pencil", help: "Edit", action: onSelect)
            iconButton("trash", help: "Delete", tint: Palette.today, action: onDelete)
        }
        .foregroundStyle(.secondary)
    }

    private func iconButton(_ icon: String, help: String, tint: Color = .secondary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Right-click menu: every quick edit without opening the inspector.
struct TaskContextMenu: View {
    let task: Task
    let projects: [String]
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onUpdate: (TaskPatch) -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(task.completed ? "Mark as Not Done" : "Mark as Done", systemImage: "checkmark.circle", action: onToggle)
        Button("Edit…", systemImage: "pencil", action: onEdit)
        Divider()
        Menu("Priority") {
            ForEach(Priority.allCases.reversed()) { p in
                Button { onUpdate(TaskPatch(priority: p)) } label: {
                    if p == task.priority { Label(p.displayName, systemImage: "checkmark") } else { Text(p.displayName) }
                }
            }
        }
        DateChoiceMenus(onUpdate: onUpdate)
        Menu("Move to Project") {
            ForEach(projects.filter { $0 != task.project }, id: \.self) { p in
                Button(p) { onUpdate(TaskPatch(project: p)) }
            }
        }
        .disabled(projects.count < 2)
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
    }
}

/// "Do On" and "Due Date" submenus with the quick day choices.
struct DateChoiceMenus: View {
    let onUpdate: (TaskPatch) -> Void

    var body: some View {
        Menu("Do On") {
            ForEach(DueChoice.allCases) { choice in
                Button(choice.title, systemImage: choice.icon) {
                    onUpdate(TaskPatch(scheduledDate: change(choice)))
                }
            }
        }
        Menu("Due Date") {
            ForEach(DueChoice.allCases) { choice in
                Button(choice.title, systemImage: choice.icon) {
                    onUpdate(TaskPatch(dueDate: change(choice)))
                }
            }
        }
    }

    private func change(_ choice: DueChoice) -> TaskPatch.DueDate {
        choice.date.map { .set(TaskDate.string(from: $0)) } ?? .clear
    }
}

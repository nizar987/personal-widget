import SwiftUI

/// Inline "Add a task…" field. Enter saves; chips pick project, priority, do date and due date.
struct QuickAddBar: View {
    let defaults: QuickAddDefaults
    let projects: [String]
    var focus: FocusState<Bool>.Binding
    let onAdd: (_ title: String, _ project: String, _ priority: Priority, _ due: Date?,
                _ scheduled: Date?) async -> Bool

    @State private var title = ""
    @State private var project = ""
    @State private var priority: Priority = .medium
    @State private var due: Date?
    @State private var scheduled: Date?
    @State private var isSaving = false
    @State private var showsNewProject = false
    @State private var newProject = ""

    private var resolvedProject: String {
        let p = project.trimmingCharacters(in: .whitespaces)
        return p.isEmpty ? (projects.first ?? "Inbox") : p
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: isSaving ? "hourglass" : "plus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor)
                    .contentTransition(.symbolEffect(.replace))
                TextField("Add a task…", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .focused(focus)
                    .onSubmit(submit)
                if canSubmit {
                    Button("Add", action: submit)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            FlowLayout(spacing: 6) {
                projectMenu
                priorityMenu
                doMenu
                dueMenu
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 28)
        }
        .card(padding: 12)
        .animation(AppStyle.spring, value: canSubmit)
        .onAppear(perform: applyDefaults)
        .onChange(of: defaults.project) { applyDefaults() }
        .onChange(of: defaults.due) { applyDefaults() }
        .onChange(of: defaults.priority) { applyDefaults() }
        .onChange(of: defaults.scheduled) { applyDefaults() }
        .alert("New Project", isPresented: $showsNewProject) {
            TextField("Project name", text: $newProject)
            Button("Cancel", role: .cancel) {}
            Button("Use") { project = newProject.trimmingCharacters(in: .whitespaces) }
        }
    }

    // MARK: - Chips

    private var projectMenu: some View {
        Menu {
            ForEach(projects, id: \.self) { p in Button(p) { project = p } }
            if !projects.isEmpty { Divider() }
            Button("New Project…", systemImage: "plus") { newProject = ""; showsNewProject = true }
        } label: {
            Chip(text: resolvedProject, icon: "folder", tint: Palette.project)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var priorityMenu: some View {
        Menu {
            ForEach(Priority.allCases.reversed()) { p in
                Button { priority = p } label: { PriorityLabel(priority: p) }
            }
        } label: {
            Chip(text: priority.displayName, icon: "flag.fill", tint: Palette.color(for: priority))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// When you'll work on it.
    private var doMenu: some View {
        Menu {
            Section("Do on") {
                ForEach(DueChoice.allCases) { choice in
                    Button(choice.title, systemImage: choice.icon) { scheduled = choice.date }
                }
            }
        } label: {
            Chip(text: scheduled.map { "Do \(dayText($0))" } ?? "Do: any day", icon: "play.circle",
                 tint: scheduled == nil ? .secondary : Palette.important)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Do date — the day you plan to work on it")
    }

    /// The deadline.
    private var dueMenu: some View {
        Menu {
            Section("Due by") {
                ForEach(DueChoice.allCases) { choice in
                    Button(choice.title, systemImage: choice.icon) { due = choice.date }
                }
            }
        } label: {
            Chip(text: due.map { "Due \(dayText($0))" } ?? "No deadline", icon: "flag.checkered",
                 tint: due == nil ? .secondary : Palette.upcoming)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Due date — when it has to be done by")
    }

    private func dayText(_ day: Date) -> String {
        if day == TaskDate.day(offset: 0) { return "today" }
        if day == TaskDate.day(offset: 1) { return "tomorrow" }
        return day.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: - Actions

    private func applyDefaults() {
        if let p = defaults.project { project = p }
        priority = defaults.priority
        due = defaults.due
        scheduled = defaults.scheduled
    }

    private func submit() {
        guard canSubmit else { return }
        let text = title
        isSaving = true
        _Concurrency.Task {
            let ok = await onAdd(text, resolvedProject, priority, due, scheduled)
            isSaving = false
            if ok {
                title = ""
                focus.wrappedValue = true
            }
        }
    }
}

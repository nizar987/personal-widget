import SwiftUI

struct ContentView: View {
    @State private var tasks: [Task] = []
    @State private var projects: [String] = []
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isLoading = true

    @State private var newTitle: String = ""
    @State private var newProject: String = ""
    @State private var newPriority: Priority = .medium
    @State private var newDueDate: Date = Date()
    @State private var newHasDate = true
    @State private var isSaving = false

    var body: some View {
        HStack(spacing: 0) {
            addPanel
                .frame(width: 280)
                .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            listPanel
        }
        .task { await load() }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Add Panel

    private var addPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Task").font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Title").font(.caption).foregroundStyle(.secondary)
                TextField("Task title", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Project").font(.caption).foregroundStyle(.secondary)
                TextField("Project name", text: $newProject)
                    .textFieldStyle(.roundedBorder)
                if !projects.isEmpty {
                    FlowLayout(spacing: 5) {
                        ForEach(projects, id: \.self) { p in
                            Button(p) { newProject = p }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .font(.caption)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Priority").font(.caption).foregroundStyle(.secondary)
                HStack {
                    ForEach(Priority.allCases) { p in
                        Button {
                            newPriority = p
                        } label: {
                            HStack(spacing: 3) {
                                Circle().fill(color(for: p)).frame(width: 7, height: 7)
                                Text(p.displayName).font(.caption)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(newPriority == p ? color(for: p) : nil)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Due date").font(.caption).foregroundStyle(.secondary)
                Toggle("Has due date", isOn: $newHasDate).controlSize(.small)
                if newHasDate {
                    DatePicker("", selection: $newDueDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
            }

            Spacer()

            Button {
                Task { await submit() }
            } label: {
                HStack {
                    if isSaving { ProgressView().controlSize(.small) }
                    Text("Add Task").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmit || isSaving)
        }
        .padding(16)
    }


    // MARK: - List Panel

    private var listPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tasks").font(.headline)
                Spacer()
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise").font(.caption)
                }
                .help("Refresh")
            }

            if isLoading {
                Spacer()
                ProgressView("Loading…").frame(maxWidth: .infinity)
                Spacer()
            } else if tasks.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Text("No tasks yet").font(.headline)
                    Text("Add your first task using the panel on the left.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(tasks) { t in
                            TaskRow(task: t) {
                                Task { await toggle(t.id) }
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
    }

    // MARK: - Data

    private var canSubmit: Bool {
        !newTitle.trimmingCharacters(in: .whitespaces).isEmpty &&
        !newProject.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func color(for p: Priority) -> Color {
        switch p {
        case .low:    return .green
        case .medium: return .orange
        case .high:   return .red
        }
    }

    private func load() async {
        isLoading = true
        do {
            async let t = APIClient.shared.fetchTasks(completed: false)
            async let p = APIClient.shared.fetchProjects()
            tasks = try await t
            projects = try await p
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isLoading = false
    }

    private func submit() async {
        isSaving = true
        defer { isSaving = false }
        let dueDate = newHasDate ? Self.isoDate(newDueDate) : nil
        do {
            let created = await APIClient.shared.createTask(NewTaskInput(
                title: newTitle.trim(),
                project: newProject.trim(),
                priority: newPriority,
                due_date: dueDate,
                description: nil
            ))
            tasks.insert(created, at: 0)
            if !projects.contains(newProject.trim()) {
                projects.append(newProject.trim()); projects.sort()
            }
            newTitle = ""
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func toggle(_ id: Int) async {
        do {
            let updated = await APIClient.shared.toggleTask(id: id)
            if let i = tasks.firstIndex(where: { $0.id == id }) {
                tasks[i] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    static func isoDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: d)
    }
}

// MARK: - TaskRow

struct TaskRow: View {
    let task: Task
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button {
                onToggle()
            } label: {
                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(task.completed ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(task.title).font(.body)
                    if task.completed {
                        Text("(done)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    Text(task.project)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(3)

                    Circle().fill(colorFor(task.priority)).frame(width: 6, height: 6)
                    Text(task.priority.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let dd = task.dueDate {
                        Text(dd).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .cornerRadius(6)
    }

    private func colorFor(_ p: Priority) -> Color {
        switch p {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
}

// MARK: - FlowLayout

struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.replacingUnspecifiedDimensions().width
        var h: CGFloat = 0, cx: CGFloat = 0, row: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if cx + s.width > w { cx = 0; row += s.height + spacing }
            cx += s.width + spacing
            h = max(h, row + s.height)
        }
        return CGSize(width: w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var cx: CGFloat = 0, cy: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if cx + s.width > bounds.width { cx = 0; cy += s.height + spacing }
            sv.place(at: CGPoint(x: bounds.minX + cx, y: bounds.minY + cy), proposal: .unspecified)
            cx += s.width + spacing
        }
    }
}

// MARK: - String ext

extension String {
    func trim() -> String {
        self.trimmingCharacters(in: .whitespaces)
    }
}

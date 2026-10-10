import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    let store: TaskStore

    var body: some View {
        List(selection: $selection) {
            Section("Lists") {
                ForEach(SmartList.allCases) { list in
                    row(.smart(list))
                }
            }
            Section("Planner") {
                row(.calendar)
            }
            Section("Weekly Reports") {
                ForEach(WeekRange.recent(6), id: \.self) { start in
                    row(.report(weekStart: start))
                }
            }
            Section("Projects") {
                if store.projects.isEmpty {
                    Text("No projects yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                ForEach(store.projects, id: \.self) { name in
                    row(.project(name))
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { statusFooter }
        .animation(AppStyle.spring, value: store.projects)
    }

    private func row(_ item: SidebarItem) -> some View {
        let count = badgeCount(for: item)
        return HStack(spacing: 8) {
            Image(systemName: item.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(item.accent))
            Text(item.title)
                .lineLimit(1)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: Double(count)))
            }
        }
        .padding(.vertical, 2)
        .tag(item)
    }

    /// Open tasks for lists, tasks completed that week for reports, none for the calendar.
    private func badgeCount(for item: SidebarItem) -> Int {
        switch item {
        case .report(let start): return WeeklyReport(tasks: store.tasks, weekStart: start).completed.count
        case .calendar: return 0
        case .smart, .project: return item.matching(store.tasks, now: Date()).count
        }
    }

    private var statusFooter: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(store.isOffline ? Palette.today : Palette.done)
                .frame(width: 7, height: 7)
            Text(store.isOffline ? "Backend offline" : "Synced with \(Constants.apiHostLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if store.isLoading {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

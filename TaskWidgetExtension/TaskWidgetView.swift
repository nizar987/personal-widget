import WidgetKit
import SwiftUI

struct TaskWidgetView: View {
    @Environment(\.widgetRenderingMode) var renderingMode
    let entry: TaskProvider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tasks Today").font(.caption2).foregroundStyle(.secondary)
                    Text(entry.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(entry.count)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(priorityColor(entry.priority))
            }
            HStack {
                Circle().fill(priorityColor(entry.priority)).frame(width: 5)
                Text(entry.priority.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .font(.caption)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func priorityColor(_ p: Priority) -> Color {
        switch p {
        case .low:    return .green
        case .medium: return .orange
        case .high:   return .red
        }
    }
}

@main
struct TaskWidgetExtensionWidget: Widget {
    let kind: String = "com.multiagent.taskwidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TaskProvider()) { entry in
            TaskWidgetView(entry: entry)
        }
        .configurationDisplayName("Tasks Today")
        .description("Shows today's task count and next priority.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TaskWidgetView_Previews: PreviewProvider {
    static var previews: some View {
        let entry = TaskEntry(date: Date(), title: "Team meeting", count: 4, priority: .high)
        Group {
            TaskWidgetView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            TaskWidgetView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .systemMedium))
        }
    }
}

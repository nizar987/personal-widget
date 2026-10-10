import SwiftUI
import AppKit

/// Visual tokens for the LockDay-inspired widget look.
enum WidgetTheme {
    static let background = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.09, alpha: 1)
            : NSColor(calibratedWhite: 0.95, alpha: 1)
    })
    static let tile = Color.primary.opacity(0.07)
    static let tileRadius: CGFloat = 14
    static let outerPadding: CGFloat = 10
    static let tileSpacing: CGFloat = 8

    static let todayAccent = Palette.today
    static let importantAccent = Palette.important
    static let upcomingAccent = Palette.upcoming
    static let somedayAccent = Palette.someday

    static func color(for priority: Priority) -> Color { Palette.color(for: priority) }
}

/// One LockDay section: icon, title, accent, tasks.
struct TaskSection {
    let title: String
    let icon: String
    let accent: Color
    let tasks: [Task]

    static func today(_ g: TaskGroups) -> TaskSection {
        TaskSection(title: "Today", icon: "flame.fill", accent: WidgetTheme.todayAccent, tasks: g.today)
    }
    static func important(_ g: TaskGroups) -> TaskSection {
        TaskSection(title: "Important", icon: "star.fill", accent: WidgetTheme.importantAccent, tasks: g.important)
    }
    static func upcoming(_ g: TaskGroups) -> TaskSection {
        TaskSection(title: "Upcoming", icon: "bolt.fill", accent: WidgetTheme.upcomingAccent, tasks: g.upcoming)
    }
    static func someday(_ g: TaskGroups) -> TaskSection {
        TaskSection(title: "Someday", icon: "tray.fill", accent: WidgetTheme.somedayAccent, tasks: g.someday)
    }
    static func upNext(_ g: TaskGroups) -> TaskSection {
        TaskSection(title: "Up next", icon: "checklist", accent: .primary, tasks: g.upNext)
    }
}

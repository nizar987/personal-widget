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

import SwiftUI
import AppKit

/// LockDay-inspired accents shared by the app and the widget.
enum Palette {
    static let today = adaptive(dark: (1.00, 0.42, 0.36), light: (0.90, 0.26, 0.22))     // coral red
    static let important = adaptive(dark: (0.37, 0.62, 1.00), light: (0.16, 0.45, 0.92)) // sky blue
    static let upcoming = adaptive(dark: (1.00, 0.76, 0.24), light: (0.85, 0.55, 0.00))  // amber
    static let done = adaptive(dark: (0.30, 0.82, 0.48), light: (0.13, 0.62, 0.30))      // green
    static let project = adaptive(dark: (0.68, 0.52, 1.00), light: (0.47, 0.30, 0.90))   // violet
    static let someday = Color.secondary

    static func color(for priority: Priority) -> Color {
        switch priority {
        case .high: return today
        case .medium: return upcoming
        case .low: return important
        }
    }

    static func color(for status: TaskStatus) -> Color {
        switch status {
        case .backlog: return someday
        case .inProgress: return .teal
        case .done: return done
        }
    }

    /// Brighter tint on dark backgrounds, deeper tint on light ones for contrast.
    private static func adaptive(dark: (CGFloat, CGFloat, CGFloat), light: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

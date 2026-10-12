import Foundation
import Observation

/// Navigation requests that arrive from outside SwiftUI (widget links, notifications).
@Observable
@MainActor
final class AppRouter {
    /// Task the main window should select; cleared once handled.
    var requestedTaskID: Int?
}

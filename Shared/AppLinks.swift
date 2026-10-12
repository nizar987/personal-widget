import Foundation

/// `taskwidget://` deep links shared by the widget (which opens them) and the app (which handles them).
enum AppLink: Equatable {
    /// Open the quick-capture panel.
    case quickCapture
    /// Open the main window.
    case open
    /// Open the main window with this task selected.
    case task(id: Int)

    static let scheme = "taskwidget"

    var url: URL {
        let path: String
        switch self {
        case .quickCapture: path = "quick-capture"
        case .open: path = "open"
        case .task(let id): path = "task/\(id)"
        }
        // Static, well-formed strings; force-unwrap can't fail.
        return URL(string: "\(Self.scheme)://\(path)")!
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        let parts = ([url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" })
        switch parts.first {
        case "quick-capture": self = .quickCapture
        case "open": self = .open
        case "task":
            guard parts.count == 2, let id = Int(parts[1]), id > 0 else { return nil }
            self = .task(id: id)
        default: return nil
        }
    }
}

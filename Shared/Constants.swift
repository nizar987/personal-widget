import Foundation

enum Constants {
    /// Local Rust backend (`backend/`). Loopback only; see `backend/README.md`.
    static let apiBaseURL = URL(string: "http://127.0.0.1:3220")!
    static var apiHostLabel: String { "\(apiBaseURL.host ?? "127.0.0.1"):\(apiBaseURL.port ?? 3220)" }
    static let appGroupID = "group.com.multiagent.taskwidget"
}

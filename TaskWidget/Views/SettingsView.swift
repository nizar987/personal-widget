import SwiftUI
import KeyboardShortcuts

/// App settings (⌘,).
struct SettingsView: View {
    var body: some View {
        Form {
            Section("General") {
                LaunchAtLoginToggle()
            }
            Section {
                KeyboardShortcuts.Recorder("Quick capture", name: .quickCapture)
                Button("Reset to ⌥Space") { KeyboardShortcuts.reset(.quickCapture) }
                    .buttonStyle(.link)
            } header: {
                Text("Quick Capture")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Type a task anywhere, press ↵. Shortcuts inside the text:")
                    Text("#project   !high !! !   today · besok · lusa · fri · @minggu · next week · 12/10 · 3 hari lagi")
                        .font(.system(.caption, design: .monospaced))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section("Backend") {
                LabeledContent("Server", value: Constants.apiBaseURL.absoluteString)
                Text("Tasks sync with the local Rust server in backend/. It starts at login via a LaunchAgent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Widget") {
                Text("Right-click the desktop → Edit Widgets… → search “TaskWidget”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

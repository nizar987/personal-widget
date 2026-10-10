import SwiftUI
import UserNotifications

/// Settings → Daily Reminder.
struct ReminderSettingsSection: View {
    @State private var settings = DailyReminderSettings.load()
    @State private var authorization: UNAuthorizationStatus = .notDetermined
    @State private var sentTest = false

    private var time: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: settings.hour, minute: settings.minute, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings.hour = parts.hour ?? settings.hour
                settings.minute = parts.minute ?? settings.minute
            }
        )
    }

    var body: some View {
        Section {
            Toggle("Remind me about today's tasks", isOn: $settings.isEnabled)
            if settings.isEnabled {
                DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
                Picker("Repeat every", selection: $settings.repeatInterval) {
                    ForEach(DailyReminderSettings.intervalChoices, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                LabeledContent("Repeats", value: "Up to \(settings.repeatCount)× until you press Understood")
                HStack {
                    Button(sentTest ? "Sent ✓" : "Send test notification") {
                        _Concurrency.Task {
                            await DailyReminderScheduler.shared.sendTest()
                            sentTest = true
                        }
                    }
                    .disabled(authorization == .denied)
                    Spacer()
                }
            }
            if authorization == .denied {
                HStack {
                    Label("Notifications are turned off for TaskWidget", systemImage: "bell.slash")
                        .foregroundStyle(Palette.today)
                    Spacer()
                    Button("Open Settings") { openNotificationSettings() }
                }
            }
        } header: {
            Text("Daily Reminder")
        } footer: {
            Text("A notification lists the tasks due that day (plus overdue ones). Completing all of them cancels the rest.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: settings) {
            settings.save()
            DailyReminderScheduler.shared.settingsChanged()
        }
        .task {
            authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}

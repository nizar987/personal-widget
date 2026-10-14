import SwiftUI
import UserNotifications

/// Settings → Daily Reminder.
struct ReminderSettingsSection: View {
    @State private var settings = DailyReminderSettings.load()
    @State private var authorization: UNAuthorizationStatus = .notDetermined
    @State private var sentTest = false
    @State private var testProblem: String?

    private var startTime: Binding<Date> {
        timeBinding(hour: \.hour, minute: \.minute)
    }

    private var endTime: Binding<Date> {
        timeBinding(hour: \.endHour, minute: \.endMinute)
    }

    private func timeBinding(hour: WritableKeyPath<DailyReminderSettings, Int>,
                             minute: WritableKeyPath<DailyReminderSettings, Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: settings[keyPath: hour], minute: settings[keyPath: minute],
                                      second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings[keyPath: hour] = parts.hour ?? settings[keyPath: hour]
                settings[keyPath: minute] = parts.minute ?? settings[keyPath: minute]
            }
        )
    }

    var body: some View {
        Section {
            Toggle("Remind me about my tasks", isOn: $settings.isEnabled)
            if settings.isEnabled {
                DatePicker("Daily summary at", selection: startTime, displayedComponents: .hourAndMinute)
                Picker("Repeat due tasks every", selection: $settings.repeatInterval) {
                    ForEach(DailyReminderSettings.intervalChoices, id: \.self) { minutes in
                        Text(minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h").tag(minutes)
                    }
                }
                DatePicker("Until", selection: endTime, displayedComponents: .hourAndMinute)
                if !settings.hasRepeatWindow {
                    Label("Pick an end time after the summary time, or due tasks won't repeat.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Palette.upcoming)
                }
                HStack {
                    Button(sentTest ? "Sent ✓" : "Send test notification") {
                        _Concurrency.Task {
                            testProblem = await DailyReminderScheduler.shared.sendTest()
                            authorization = DailyReminderScheduler.shared.authorization
                            sentTest = testProblem == nil
                        }
                    }
                    .disabled(authorization == .denied)
                    Spacer()
                }
                if let testProblem {
                    Label(testProblem, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Palette.today)
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
            Text("Reminders")
        } footer: {
            Text("Every day the summary lists everything still open — overdue, due today, due this week and tasks without a due date — with when each is due. Tasks due today or overdue then repeat until you mark them done; Snooze pauses them for an hour.")
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

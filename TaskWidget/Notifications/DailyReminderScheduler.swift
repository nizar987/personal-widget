import AppKit
import OSLog
import UserNotifications

private let reminderLog = Logger(subsystem: "com.multiagent.taskwidget", category: "reminders")

/// Schedules the morning "tasks due today" notifications and handles the Understood action.
///
/// Notifications are planned 7 days ahead and re-planned whenever tasks or settings change,
/// so the text always reflects the latest tasks and reminders still fire if the app is closed.
@MainActor
final class DailyReminderScheduler: NSObject {
    static let shared = DailyReminderScheduler()

    static let categoryID = "taskwidget.daily"
    static let understoodActionID = "taskwidget.daily.understood"
    private static let acknowledgedKey = "reminder.acknowledgedDays"
    private static let testIdentifierPrefix = "taskwidget.test."

    private let center = UNUserNotificationCenter.current()
    private var tasks: [Task] = []
    private var pendingReschedule: _Concurrency.Task<Void, Never>?
    private var hasScheduled = false
    /// Opens the main window when the notification body is clicked.
    var onOpenApp: (() -> Void)?

    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    /// Call from `applicationWillFinishLaunching` so actions are received even on cold launch.
    func configure() {
        DailyReminderSettings.registerDefaults()
        center.delegate = self
        let understood = UNNotificationAction(identifier: Self.understoodActionID, title: "Understood", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.categoryID, actions: [understood], intentIdentifiers: [],
                                   options: []),
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(dayChanged),
                                               name: .NSCalendarDayChanged, object: nil)
    }

    func requestAuthorization() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            reminderLog.error("notification authorization failed: \(error.localizedDescription, privacy: .public)")
        }
        authorization = await center.notificationSettings().authorizationStatus
    }

    // MARK: - Planning

    /// Debounced: store mutations arrive in bursts.
    func tasksChanged(_ tasks: [Task]) {
        guard tasks != self.tasks || !hasScheduled else { return }
        self.tasks = tasks
        scheduleRefresh()
    }

    func settingsChanged() {
        scheduleRefresh()
    }

    @objc private func dayChanged() {
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        pendingReschedule?.cancel()
        pendingReschedule = _Concurrency.Task { [weak self] in
            try? await _Concurrency.Task.sleep(for: .milliseconds(400))
            guard !_Concurrency.Task.isCancelled else { return }
            await self?.reschedule()
        }
    }

    private func reschedule() async {
        let reminders = DailyReminderPlanner.plan(tasks: tasks, settings: .load(),
                                                  acknowledgedDays: acknowledgedDays())
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier).filter { $0.hasPrefix(DailyReminderPlanner.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        // If today no longer needs a reminder (all done / acknowledged), clear what's on screen too.
        let today = TaskDate.string(from: Date())
        if !reminders.contains(where: { $0.dayKey == today }) {
            await removeDelivered(forDay: today)
        }

        for reminder in reminders {
            do {
                try await center.add(request(for: reminder))
            } catch {
                reminderLog.error("schedule failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        hasScheduled = true
        reminderLog.info("scheduled \(reminders.count) reminders")
    }

    private func request(for reminder: DailyReminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        if let subtitle = reminder.subtitle { content.subtitle = subtitle }
        content.body = reminder.body
        content.sound = .default
        content.categoryIdentifier = Self.categoryID
        content.threadIdentifier = "\(Self.categoryID).\(reminder.dayKey)"
        content.userInfo = ["day": reminder.dayKey]
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        return UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger)
    }

    /// Sends today's reminder now (Settings → "Send test notification").
    /// Returns a user-facing reason when the notification couldn't be shown.
    func sendTest() async -> String? {
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            await requestAuthorization()
        }
        let settings = await center.notificationSettings()
        authorization = settings.authorizationStatus
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return "Notifications are turned off for TaskWidget."
        }

        // Re-using one identifier makes macOS silently replace the previous test in
        // Notification Center instead of showing a banner, so clear old tests and use a fresh id.
        let oldTests = await center.deliveredNotifications()
            .map(\.request.identifier).filter { $0.hasPrefix(Self.testIdentifierPrefix) }
        center.removeDeliveredNotifications(withIdentifiers: oldTests)

        let today = Calendar.current.startOfDay(for: Date())
        let open = tasks.filter { !$0.completed }
        let due = open.filter { $0.dueDay == today }
        let overdue = open.filter { ($0.dueDay ?? .distantFuture) < today }
        let message = due.isEmpty && overdue.isEmpty
            ? (title: "Nothing due today", body: "This is how your morning reminder will look.")
            : DailyReminderPlanner.message(due: due, overdue: overdue)
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.subtitle = "Test"
        content.body = message.body
        content.sound = .default
        content.categoryIdentifier = Self.categoryID
        content.userInfo = ["day": "test"]
        let identifier = "\(Self.testIdentifierPrefix)\(UUID().uuidString)"
        do {
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
        } catch {
            reminderLog.error("test notification failed: \(error.localizedDescription, privacy: .public)")
            return "Couldn't send: \(error.localizedDescription)"
        }
        if settings.alertSetting != .enabled {
            return "Sent to Notification Center, but banners are off for TaskWidget."
        }
        return nil
    }

    // MARK: - Acknowledgement

    private func acknowledgedDays() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.acknowledgedKey) ?? [])
    }

    /// Stops the remaining repeats for `day`. Keeps two weeks of history.
    private func acknowledge(day: String) async {
        let cutoff = TaskDate.string(from: TaskDate.day(offset: -14))
        let days = (acknowledgedDays().filter { $0 >= cutoff }).union([day])
        UserDefaults.standard.set(Array(days).sorted(), forKey: Self.acknowledgedKey)
        let ids = (1...DailyReminderSettings.load().repeatCount)
            .map { "\(DailyReminderPlanner.identifierPrefix)\(day).\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        await removeDelivered(forDay: day)
        reminderLog.info("acknowledged \(day, privacy: .public)")
    }

    private func removeDelivered(forDay day: String) async {
        let prefix = "\(DailyReminderPlanner.identifierPrefix)\(day)."
        let delivered = await center.deliveredNotifications()
            .map(\.request.identifier).filter { $0.hasPrefix(prefix) }
        center.removeDeliveredNotifications(withIdentifiers: delivered)
    }
}

extension DailyReminderScheduler: UNUserNotificationCenterDelegate {
    /// Show banners even while the app is frontmost.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let day = response.notification.request.content.userInfo["day"] as? String
        await handle(action: response.actionIdentifier, day: day)
    }

    private func handle(action: String, day: String?) async {
        if action == Self.understoodActionID, let day, day != "test" {
            await acknowledge(day: day)
        } else if action == UNNotificationDefaultActionIdentifier {
            onOpenApp?()
        }
    }
}

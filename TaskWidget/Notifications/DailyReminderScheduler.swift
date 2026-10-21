import AppKit
import OSLog
import UserNotifications

private let reminderLog = Logger(subsystem: "com.multiagent.taskwidget", category: "reminders")

/// Schedules task reminders (see `DailyReminderPlanner`) and handles their actions.
///
/// The plan is rebuilt whenever tasks or settings change, the day rolls over, and on every
/// background refresh — so the text always matches the latest tasks, repeats are topped up
/// past the 64-pending limit, and summaries a week ahead still fire if the app is closed.
@MainActor
final class DailyReminderScheduler: NSObject {
    static let shared = DailyReminderScheduler()

    static let categoryID = "taskwidget.daily"
    /// Reminders about exactly one task also offer "Mark as Done".
    static let singleTaskCategoryID = "taskwidget.daily.single"
    static let understoodActionID = "taskwidget.daily.understood"
    static let snoozeActionID = "taskwidget.daily.snooze"
    static let doneActionID = "taskwidget.daily.done"
    private static let snoozeKey = "reminder.snoozedUntil"
    private static let acknowledgedKey = "reminder.acknowledged"
    private static let summaryDaysKey = "reminder.summaryDays"
    private static let testIdentifierPrefix = "taskwidget.test."
    private static let snoozeDuration: TimeInterval = 60 * 60

    private let center = UNUserNotificationCenter.current()
    private var tasks: [Task] = []
    private var pendingReschedule: _Concurrency.Task<Void, Never>?
    /// Opens the main window when the notification body is clicked.
    var onOpenApp: (() -> Void)?
    /// "Mark as Done" on a single-task reminder.
    var onCompleteTask: ((Int) -> Void)?

    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    /// Call from `applicationWillFinishLaunching` so actions are received even on cold launch.
    func configure() {
        DailyReminderSettings.registerDefaults()
        center.delegate = self
        let understood = UNNotificationAction(identifier: Self.understoodActionID, title: "Understood", options: [])
        let snooze = UNNotificationAction(identifier: Self.snoozeActionID, title: "Snooze 1 Hour", options: [])
        let done = UNNotificationAction(identifier: Self.doneActionID, title: "Mark as Done", options: [])
        // Understood comes first so it's the button macOS shows; closing the notification
        // (customDismissAction) counts as Understood too.
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.categoryID, actions: [understood, snooze],
                                   intentIdentifiers: [], options: [.customDismissAction]),
            UNNotificationCategory(identifier: Self.singleTaskCategoryID, actions: [understood, done, snooze],
                                   intentIdentifiers: [], options: [.customDismissAction]),
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
        reminderLog.info("notification authorization: \(self.authorization.rawValue)")
    }

    // MARK: - Planning

    /// Debounced: store mutations arrive in bursts. Also called on every background load,
    /// which is what rolls repeats forward past the pending-notification limit.
    func tasksChanged(_ tasks: [Task]) {
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
        let now = Date()
        let settings = DailyReminderSettings.load()
        let today = TaskDate.string(from: now)
        let summaryDays = self.summaryDays()
        let reminders = DailyReminderPlanner.plan(tasks: tasks, settings: settings, snoozedUntil: snoozedUntil(),
                                                  summaryDeliveredToday: summaryDays.contains(today),
                                                  acknowledged: acknowledged(now: now), now: now)

        let pending = await center.pendingNotificationRequests()
            .map(\.identifier).filter { $0.hasPrefix(DailyReminderPlanner.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        // Earlier days' reminders are stale once the day changes.
        let todayPrefix = "\(DailyReminderPlanner.identifierPrefix)\(today)."
        let stale = await center.deliveredNotifications().map(\.request.identifier)
            .filter { $0.hasPrefix(DailyReminderPlanner.identifierPrefix) && !$0.hasPrefix(todayPrefix) }
        center.removeDeliveredNotifications(withIdentifiers: stale)
        // Nothing left for today (all done, or reminders off): clear what's on screen too.
        if !reminders.contains(where: { $0.dayKey == today }) {
            await removeDelivered(forDay: today)
        }

        for reminder in reminders {
            do {
                try await center.add(request(for: reminder, now: now))
            } catch {
                reminderLog.error("schedule failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        recordSummaryDays(reminders, settings: settings, now: now)
        let summaries = reminders.filter { $0.kind == .summary }.count
        let next = reminders.map(\.fireDate).min().map { "\($0)" } ?? "none"
        reminderLog.info("scheduled \(summaries) summaries, \(reminders.count - summaries) repeats; next \(next, privacy: .public)")
    }

    private func request(for reminder: DailyReminder, now: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        if let subtitle = reminder.subtitle { content.subtitle = subtitle }
        content.body = reminder.body
        content.sound = .default
        content.categoryIdentifier = reminder.taskID == nil ? Self.categoryID : Self.singleTaskCategoryID
        content.threadIdentifier = "\(Self.categoryID).\(reminder.dayKey)"
        var info: [String: Any] = ["day": reminder.dayKey, "acknowledgeIDs": reminder.acknowledgeIDs]
        if let id = reminder.taskID { info["taskID"] = id }
        content.userInfo = info
        // Catch-up summaries are due now: deliver immediately.
        let trigger: UNNotificationTrigger? = reminder.fireDate <= now.addingTimeInterval(1)
            ? nil
            : UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second],
                                                              from: reminder.fireDate),
                repeats: false)
        return UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger)
    }

    /// Sends today's summary now (Settings → "Send test notification").
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

        let now = Date()
        let today = Calendar.current.startOfDay(for: now)
        let agenda = DayAgenda(tasks: tasks, day: today)
        let content = UNMutableNotificationContent()
        if agenda.isEmpty {
            content.title = "Nothing to do 🎉"
            content.body = "This is how your daily summary will look."
        } else {
            let summary = DailyReminderPlanner.summary(agenda, dayKey: "test", day: today, at: now)
            content.title = summary.title
            content.body = summary.body
        }
        content.subtitle = "Test"
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

    // MARK: - Snooze

    private func snoozedUntil() -> Date? {
        let date = UserDefaults.standard.object(forKey: Self.snoozeKey) as? Date
        return date.flatMap { $0 > Date() ? $0 : nil }
    }

    /// Pauses repeats for an hour; the daily summary is unaffected.
    private func snooze() {
        UserDefaults.standard.set(Date().addingTimeInterval(Self.snoozeDuration), forKey: Self.snoozeKey)
        reminderLog.info("snoozed for an hour")
        scheduleRefresh()
    }

    // MARK: - Understood

    /// Task ids per day whose repeats were acknowledged; older days are dropped.
    private func acknowledged(now: Date) -> [String: Set<Int>] {
        let stored = UserDefaults.standard.dictionary(forKey: Self.acknowledgedKey) as? [String: [Int]] ?? [:]
        let today = TaskDate.string(from: now)
        return stored.filter { $0.key >= today }.mapValues(Set.init)
    }

    /// "Understood" (or closing the notification): stop repeating these tasks today and clear
    /// today's reminders already on screen. Tasks still open remind again tomorrow.
    private func acknowledge(day: String, taskIDs: [Int]) async {
        guard !taskIDs.isEmpty, day != "test" else { return }
        let current = acknowledged(now: Date())
        let updated = current.merging([day: Set(taskIDs)]) { $0.union($1) }
        UserDefaults.standard.set(updated.mapValues { Array($0).sorted() }, forKey: Self.acknowledgedKey)
        reminderLog.info("understood: \(taskIDs.count) tasks on \(day, privacy: .public)")
        await removeDelivered(forDay: day)
        scheduleRefresh()
    }

    // MARK: - Summary bookkeeping

    /// Days whose summary has been scheduled (or sent as a catch-up). Lets a summary missed
    /// because the app wasn't running yet be sent late, once.
    private func summaryDays() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.summaryDaysKey) ?? [])
    }

    private func recordSummaryDays(_ reminders: [DailyReminder], settings: DailyReminderSettings, now: Date) {
        let today = TaskDate.string(from: now)
        let cutoff = TaskDate.string(from: TaskDate.day(offset: -14, from: now))
        let startPassed = settings.start(of: Calendar.current.startOfDay(for: now)).map { $0 <= now } ?? false
        // Past days stay recorded; today only once its summary time has passed (it fired);
        // future days follow the current plan.
        var days = summaryDays().filter { $0 >= cutoff && ($0 < today || ($0 == today && startPassed)) }
        days.formUnion(reminders.filter { $0.kind == .summary }.map(\.dayKey))
        UserDefaults.standard.set(Array(days).sorted(), forKey: Self.summaryDaysKey)
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
        let info = response.notification.request.content.userInfo
        let taskID = info["taskID"] as? Int
        let day = info["day"] as? String ?? ""
        let acknowledgeIDs = info["acknowledgeIDs"] as? [Int] ?? []
        await handle(action: response.actionIdentifier, taskID: taskID, day: day, acknowledgeIDs: acknowledgeIDs)
    }

    private func handle(action: String, taskID: Int?, day: String, acknowledgeIDs: [Int]) async {
        switch action {
        case Self.understoodActionID, UNNotificationDismissActionIdentifier:
            await acknowledge(day: day, taskIDs: acknowledgeIDs)
        case Self.snoozeActionID:
            snooze()
        case Self.doneActionID:
            if let taskID { onCompleteTask?(taskID) }
        case UNNotificationDefaultActionIdentifier:
            onOpenApp?()
        default:
            break
        }
    }
}

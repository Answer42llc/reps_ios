import Foundation
import UserNotifications

class NotificationManager {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private let practiceKey = "DailyPracticeDate"
    private init() {}

    // Request permission and schedule notifications
    func requestAuthorization() async {
        _ = await PermissionManager.requestNotificationPermission()
    }

    var hasPracticedToday: Bool { hasPracticed(on: Date()) }

    private func hasPracticed(on date: Date) -> Bool {
        if let stored = defaults.object(forKey: practiceKey) as? Date {
            return Calendar.current.isDate(stored, inSameDayAs: date)
        }
        return false
    }

    func markPracticeCompleted() {
        let now = Date()
        if !hasPracticedToday {
            defaults.set(now, forKey: practiceKey)
            scheduleDailyNotifications()
        }
    }

    func scheduleDailyNotifications() {
        center.removePendingNotificationRequests(withIdentifiers: ["morning", "midday1", "midday2", "evening"])

        scheduleMorningReminder()

        let now = Date()
        let targetDate = hasPracticedToday ? Calendar.current.date(byAdding: .day, value: 1, to: now)! : now
        scheduleMiddayReminders(for: targetDate)
        scheduleEveningReminder(for: now)
    }

    private func scheduleMorningReminder() {
        var components = DateComponents()
        components.hour = 7
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let content = UNMutableNotificationContent()
        content.title = "Start your day with affirmations"
        content.body = "Take a moment to practice your affirmations."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "morning", content: content, trigger: trigger)
        center.add(request)
    }

    private func scheduleMiddayReminders(for date: Date) {
        scheduleReminder(identifier: "midday1", on: date, hour: 10, body: "Mid-morning check-in: have you done your affirmations?")
        scheduleReminder(identifier: "midday2", on: date, hour: 16, body: "Afternoon boost: a quick affirmation can help!")
    }

    private func scheduleEveningReminder(for date: Date) {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = 21
        components.minute = 0
        guard let triggerDate = Calendar.current.date(from: components), triggerDate > Date() else { return }

        let content = UNMutableNotificationContent()
        if hasPracticed(on: date) {
            content.title = "Great job today!"
            content.body = "You've completed your affirmation practice. See you tomorrow."
        } else {
            content.title = "Time for reflection"
            content.body = "You haven't practiced affirmations yet. There's still time tonight."
        }
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "evening", content: content, trigger: trigger)
        center.add(request)
    }

    private func scheduleReminder(identifier: String, on date: Date, hour: Int, body: String) {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = 0
        guard let triggerDate = Calendar.current.date(from: components), triggerDate > Date() else { return }
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let content = UNMutableNotificationContent()
        content.title = "Affirmation Reminder"
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request)
    }
}


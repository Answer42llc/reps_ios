import Foundation
import UserNotifications
import CoreData

class NotificationManager: NSObject {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private let practiceKey = "DailyPracticeDate"
    private override init() {}

    // MARK: - Categories
    func registerCategories() {
        let openAction = UNNotificationAction(
            identifier: "START_PRACTICE",
            title: "Start Now",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: "AFFIRMATION_REMINDER",
            actions: [openAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

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
        content.title = localizedRandomTitle(isMorning: true)
        content.body = randomAffirmationBody(fallback: "Take a moment to practice your affirmations.")
        applyCommonContentSettings(content)
        let request = UNNotificationRequest(identifier: "morning", content: content, trigger: trigger)
        center.add(request)
    }

    private func scheduleMiddayReminders(for date: Date) {
        scheduleReminder(identifier: "midday1", on: date, hour: 10)
        scheduleReminder(identifier: "midday2", on: date, hour: 16)
    }

    private func scheduleEveningReminder(for date: Date) {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = 21
        components.minute = 0
        guard let triggerDate = Calendar.current.date(from: components), triggerDate > Date() else { return }

        let content = UNMutableNotificationContent()
        if hasPracticed(on: date) {
            content.title = localizedCongratulationTitle()
            content.body = localizedCongratulationBody()
        } else {
            content.title = localizedRandomTitle(isEvening: true)
            content.body = randomAffirmationBody(fallback: "There's still time tonight.")
        }
        applyCommonContentSettings(content)

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "evening", content: content, trigger: trigger)
        center.add(request)
    }

    private func scheduleReminder(identifier: String, on date: Date, hour: Int) {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = 0
        guard let triggerDate = Calendar.current.date(from: components), triggerDate > Date() else { return }
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let content = UNMutableNotificationContent()
        content.title = localizedRandomTitle()
        content.body = randomAffirmationBody(fallback: "A quick affirmation can help!")
        applyCommonContentSettings(content)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request)
    }

    // MARK: - Helpers
    private func applyCommonContentSettings(_ content: UNMutableNotificationContent) {
        content.sound = .default
        content.categoryIdentifier = "AFFIRMATION_REMINDER"
        content.threadIdentifier = "AFFIRMATION_REMINDERS"
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 0.8
        }
    }

    private func randomAffirmationBody(fallback: String) -> String {
        if let text = getRandomAffirmationText(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let localeId = Locale.current.identifier
            if localeId.hasPrefix("zh") {
                return "“\(text)”"
            } else {
                return "Remember you said: \"\(text)\""
            }
        }
        return fallback
    }

    private func getRandomAffirmationText() -> String? {
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<Affirmation> = Affirmation.fetchRequest()
        do {
            let count = try context.count(for: request)
            guard count > 0 else { return nil }
            let offset = Int.random(in: 0..<count)
            request.fetchLimit = 1
            request.fetchOffset = offset
            let results = try context.fetch(request)
            return results.first?.text
        } catch {
            return nil
        }
    }

    private func localizedRandomTitle(isMorning: Bool = false, isEvening: Bool = false) -> String {
        let isChinese = Locale.current.identifier.hasPrefix("zh")
        if isChinese {
            let titles = isMorning ? [
                "开始今天的复诵",
                "早安，来一条自我肯定",
                "新一天，立刻复诵"
            ] : isEvening ? [
                "睡前来一条复诵",
                "还差一次复诵就更棒了",
                "现在复诵一下吧"
            ] : [
                "现在复诵一下",
                "记得你说过",
                "来一条自我肯定"
            ]
            return titles.randomElement() ?? "现在复诵一下"
        } else {
            let titles = isMorning ? [
                "Let's rep now",
                "Morning boost: affirm now",
                "Kickstart with a rep"
            ] : isEvening ? [
                "One last rep tonight",
                "Wind down with a rep",
                "Don't miss tonight's rep"
            ] : [
                "Let's rep now",
                "Don't forget a rep",
                "Remember you said"
            ]
            return titles.randomElement() ?? "Let's rep now"
        }
    }

    private func localizedCongratulationTitle() -> String {
        if Locale.current.identifier.hasPrefix("zh") {
            return "今天做得很棒！"
        }
        return "Great job today!"
    }

    private func localizedCongratulationBody() -> String {
        if Locale.current.identifier.hasPrefix("zh") {
            return "你已完成今天的复诵，明天见。"
        }
        return "You've completed your affirmation practice. See you tomorrow."
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let openPracticeFromNotification = Notification.Name("OpenPracticeFromNotification")
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .list, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Post an app-internal notification so SwiftUI can navigate appropriately
        NotificationCenter.default.post(name: .openPracticeFromNotification, object: nil, userInfo: ["action": response.actionIdentifier])
        completionHandler()
    }
}

// MARK: - Debug Utilities
extension NotificationManager {
    @MainActor
    func debugPrintNotificationSettings() async {
        let settings = await center.notificationSettings()
        print("🔧 [Notifications] Authorization: \(settings.authorizationStatus.rawValue)")
        print("🔧 [Notifications] Alert: \(settings.alertSetting.rawValue), Sound: \(settings.soundSetting.rawValue), Badge: \(settings.badgeSetting.rawValue)")
        print("🔧 [Notifications] LockScreen: \(settings.lockScreenSetting.rawValue), NotificationCenter: \(settings.notificationCenterSetting.rawValue)")
        #if canImport(UIKit)
        if #available(iOS 15.0, *) {
            print("🔧 [Notifications] TimeSensitive: \(settings.timeSensitiveSetting.rawValue), ScheduledSummary: \(settings.scheduledDeliverySetting.rawValue)")
        }
        #endif
        print("🔧 [Notifications] AlertStyle: \(settings.alertStyle.rawValue)")
    }

    func debugPrintPendingRequests() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            center.getPendingNotificationRequests { requests in
                print("📝 [Notifications] Pending count: \(requests.count)")
                for req in requests {
                    let content = req.content
                    var triggerDesc = "unknown"
                    if let cal = req.trigger as? UNCalendarNotificationTrigger {
                        #if swift(>=5.7)
                        let nextDate = cal.nextTriggerDate()
                        triggerDesc = "Calendar(repeats: \(cal.repeats), next: \(nextDate?.description ?? "nil"))"
                        #else
                        triggerDesc = "Calendar(repeats: \(cal.repeats))"
                        #endif
                    } else if let time = req.trigger as? UNTimeIntervalNotificationTrigger {
                        triggerDesc = "TimeInterval(\(time.timeInterval)s, repeats: \(time.repeats))"
                    }
                    print("— id=\(req.identifier), title=\(content.title), body=\(content.body.prefix(60))…")
                    print("    category=\(content.categoryIdentifier), thread=\(content.threadIdentifier), trigger=\(triggerDesc)")
                }
                continuation.resume()
            }
        }
    }

    func scheduleQuickTestNotification(after seconds: TimeInterval = 10) {
        let content = UNMutableNotificationContent()
        content.title = "Test now"
        content.body = "Quick test notification (\(Int(seconds))s)"
        applyCommonContentSettings(content)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(5, seconds), repeats: false)
        let request = UNNotificationRequest(identifier: "quick_test_\(Int(Date().timeIntervalSince1970))", content: content, trigger: trigger)
        center.add(request)
        print("🚀 [Notifications] Scheduled quick test in \(Int(seconds))s")
    }
}


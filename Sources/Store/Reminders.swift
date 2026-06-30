import Foundation
import UserNotifications

enum ReminderSlot: String, CaseIterable, Identifiable {
    case morning, midday, evening
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var defaultTime: DateComponents {
        switch self {
        case .morning: return DateComponents(hour: 8, minute: 0)
        case .midday:  return DateComponents(hour: 13, minute: 0)
        case .evening: return DateComponents(hour: 20, minute: 0)
        }
    }
    var message: String {
        switch self {
        case .morning: return "New day, new missions. Let's show up."
        case .midday:  return "Midday check-in — how's today looking?"
        case .evening: return "Close out strong. Tap off what's left."
        }
    }
}

/// Schedules the three soft daily check-ins as repeating local notifications.
enum Reminders {
    static func requestAuth() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func schedule(_ slot: ReminderSlot, at time: DateComponents) {
        let content = UNMutableNotificationContent()
        content.title = "75 Her"
        content.body = slot.message
        content.sound = .default
        var comps = DateComponents(); comps.hour = time.hour; comps.minute = time.minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let req = UNNotificationRequest(identifier: "reminder.\(slot.rawValue)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }

    static func cancel(_ slot: ReminderSlot) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["reminder.\(slot.rawValue)"])
    }
}

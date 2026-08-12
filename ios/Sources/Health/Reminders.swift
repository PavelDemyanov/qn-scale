import Foundation
import UserNotifications

/// Напоминания взвеситься.
///
/// «Пуш придёт, только если в этот день ещё не было измерения» — локальные уведомления
/// нельзя отменить условием, поэтому вместо одного повторяющегося планируем по одному
/// на каждый из ближайших дней и снимаем сегодняшнее сразу после взвешивания.
enum Reminders {
    private static let center = UNUserNotificationCenter.current()
    private static let prefix = "weigh-in-"
    private static let horizon = 14

    static func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func reschedule(enabled: Bool, time: String, lastWeighIn: Date?) async {
        center.removePendingNotificationRequests(withIdentifiers: (0..<horizon).map { prefix + String($0) })
        guard enabled, await requestAuthorization() else { return }

        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weighedToday = lastWeighIn.map { cal.isDateInToday($0) } ?? false

        let content = UNMutableNotificationContent()
        content.title = "Пора взвеситься"
        content.body = "Утреннее взвешивание — самое показательное: до еды и воды."
        content.sound = .default

        for offset in 0..<horizon {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            var components = cal.dateComponents([.year, .month, .day], from: day)
            components.hour = parts[0]
            components.minute = parts[1]
            guard let fireDate = cal.date(from: components), fireDate > Date() else { continue }
            if offset == 0 && weighedToday { continue }

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
                repeats: false)
            let request = UNNotificationRequest(identifier: prefix + String(offset),
                                                content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    /// Снимает сегодняшнее напоминание — взвешивание уже состоялось.
    static func cancelToday() {
        center.removePendingNotificationRequests(withIdentifiers: [prefix + "0"])
    }
}

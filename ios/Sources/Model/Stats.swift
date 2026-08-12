import Foundation

/// Сводка по истории взвешиваний: дельты, темп, прогноз, серия.
/// Порт логики `st` из прототипа, но с защитой от пустой и короткой истории.
struct Stats {
    /// История по возрастанию даты.
    let items: [WeighIn]
    let goal: Double

    var last: WeighIn? { items.last }
    var previous: WeighIn? { items.count >= 2 ? items[items.count - 2] : nil }

    private static let day: TimeInterval = 86_400

    /// Среднее за окно [aДней; bДней) назад от последнего взвешивания.
    private func average(from a: Double, to b: Double) -> Double? {
        guard let last else { return nil }
        let hi = last.date.addingTimeInterval(-a * Self.day)
        let lo = last.date.addingTimeInterval(-b * Self.day)
        let window = items.filter { $0.date > lo && $0.date <= hi }
        guard !window.isEmpty else { return nil }
        return window.reduce(0) { $0 + $1.weightKg } / Double(window.count)
    }

    /// Ближайшее по времени измерение к заданной дате.
    private func nearest(to date: Date) -> WeighIn? {
        items.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    var dayDelta: Double? {
        guard let last, let previous else { return nil }
        return last.weightKg - previous.weightKg
    }

    var weekDelta: Double? {
        guard let last else { return nil }
        if let a = average(from: 0, to: 7), let b = average(from: 7, to: 14) { return a - b }
        guard let n = nearest(to: last.date.addingTimeInterval(-7 * Self.day)), n.id != last.id else { return nil }
        return last.weightKg - n.weightKg
    }

    var monthDelta: Double? {
        guard let last else { return nil }
        if let a = average(from: 0, to: 30), let b = average(from: 30, to: 60) { return a - b }
        guard let n = nearest(to: last.date.addingTimeInterval(-30 * Self.day)), n.id != last.id else { return nil }
        return last.weightKg - n.weightKg
    }

    /// Наклон линейной регрессии по последним 30 дням, кг в сутки.
    /// nil, если точек меньше трёх — по двум замерам «темп» был бы выдумкой.
    var slope: Double? {
        guard let last else { return nil }
        let from = last.date.addingTimeInterval(-30 * Self.day)
        let pts = items.filter { $0.date >= from }
        guard pts.count >= 3 else { return nil }
        var sx = 0.0, sy = 0.0, sxy = 0.0, sxx = 0.0
        let m = Double(pts.count)
        for p in pts {
            let x = p.date.timeIntervalSince(from) / Self.day
            let y = p.weightKg
            sx += x; sy += y; sxy += x * y; sxx += x * x
        }
        let denom = m * sxx - sx * sx
        guard abs(denom) > 1e-9 else { return nil }
        return (m * sxy - sx * sy) / denom
    }

    /// Темп в килограммах за неделю.
    var ratePerWeek: Double? { slope.map { $0 * 7 } }

    var toGoal: Double? { last.map { $0.weightKg - goal } }

    /// Дата достижения цели по текущему темпу. nil, если вес не снижается.
    var goalDate: Date? {
        guard let last, let slope, let toGoal, slope < -0.004, toGoal > 0 else { return nil }
        let days = toGoal / -slope
        guard days.isFinite, days < 3650 else { return nil }
        return last.date.addingTimeInterval(days * Self.day)
    }

    var goalDateLabel: String {
        goalDate.map(Fmt.dayMonth) ?? "темп не задан"
    }

    /// Прогноз веса через N дней.
    func forecast(days: Double) -> Double? {
        guard let last, let slope else { return nil }
        return last.weightKg + slope * days
    }

    /// Сколько дней подряд, считая от сегодня, были взвешивания.
    var streak: Int {
        let cal = Calendar.current
        let measured = Set(items.map { cal.startOfDay(for: $0.date) })
        var n = 0
        var cursor = cal.startOfDay(for: Date())
        while measured.contains(cursor) {
            n += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return n
    }

    /// Сколько календарных дней прошло с первого взвешивания.
    var daysWithScale: Int {
        guard let first = items.first else { return 0 }
        let cal = Calendar.current
        let d = cal.dateComponents([.day], from: cal.startOfDay(for: first.date),
                                   from: cal.startOfDay(for: Date())).day ?? 0
        return max(1, d + 1)
    }

    var startWeight: Double? { items.first?.weightKg }

    /// Доля пройденного пути к цели, 0…1 — для кольца в компоновке «Цель».
    var goalProgress: Double {
        guard let start = startWeight, let last else { return 0 }
        let total = start - goal
        guard abs(total) > 0.1 else { return last.weightKg <= goal ? 1 : 0 }
        return min(max((start - last.weightKg) / total, 0), 1)
    }

    /// День недели со своей дельтой — для столбиков.
    struct DayBar: Identifiable {
        /// 0 — понедельник.
        let id: Int
        let weekday: String
        let date: Date
        let delta: Double?
        /// День ещё не наступил: столбика нет и не будет до самого дня.
        let isFuture: Bool
        let isToday: Bool
    }

    /// Дельты по дням ТЕКУЩЕЙ недели, с понедельника по воскресенье.
    ///
    /// Именно календарная неделя, а не «последние семь дней»: скользящее окно
    /// каждый день переставляет подписи, и понедельник оказывается то слева,
    /// то в середине — по такой картинке нельзя сказать «в эту среду было».
    /// Понедельник задан ЯВНО, а не первым днём локали: в части локалей неделя
    /// начинается с воскресенья, а просили пн — вс.
    var currentWeek: [DayBar] {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let today = cal.startOfDay(for: Date())
        guard let monday = cal.dateInterval(of: .weekOfYear, for: today)?.start else { return [] }
        return (0..<7).map { i -> DayBar in
            let date = cal.date(byAdding: .day, value: i, to: monday) ?? monday
            let weekday = date.formatted(.dateTime.weekday(.abbreviated))
            let future = date > today
            let isToday = cal.isDate(date, inSameDayAs: today)
            guard let idx = items.firstIndex(where: { cal.isDate($0.date, inSameDayAs: date) }) else {
                return DayBar(id: i, weekday: weekday, date: date, delta: nil,
                              isFuture: future, isToday: isToday)
            }
            let delta = idx > 0 ? items[idx].weightKg - items[idx - 1].weightKg : 0
            return DayBar(id: i, weekday: weekday, date: date, delta: delta,
                          isFuture: future, isToday: isToday)
        }
    }
}

private extension Calendar {
    /// Удобная обёртка, чтобы не городить две переменные под dateComponents.
    func dateComponents(_ set: Set<Calendar.Component>, from: Date, from other: Date) -> DateComponents {
        dateComponents(set, from: from, to: other)
    }
}

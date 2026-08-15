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

    /// Изменение веса ВНУТРИ периода: последнее взвешивание минус последнее
    /// взвешивание ДО начала периода. Именно так считается «за эту неделю»:
    /// это ровно сумма столбиков по дням, и цифра сходится с картинкой.
    ///
    /// Скользящее окно «последние 7 дней против предыдущих 7» тут не годится:
    /// подпись обещает календарный период, а показывала бы бегущее среднее.
    private func delta(since start: Date) -> Double? {
        guard let last, last.date >= start else { return nil }
        if let before = items.last(where: { $0.date < start }) {
            return last.weightKg - before.weightKg
        }
        // До начала периода взвешиваний не было — считаем от первого внутри него.
        guard let first = items.first(where: { $0.date >= start }), first.id != last.id else { return nil }
        return last.weightKg - first.weightKg
    }

    /// Начало текущей недели. Понедельник задан явно, как и у столбиков.
    var startOfWeek: Date {
        var cal = Calendar.current
        cal.firstWeekday = 2
        return cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
    }

    var startOfMonth: Date {
        let cal = Calendar.current
        return cal.dateInterval(of: .month, for: Date())?.start ?? Date()
    }

    var weekDelta: Double? { delta(since: startOfWeek) }
    var monthDelta: Double? { delta(since: startOfMonth) }

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

    /// Почему даты достижения цели нет. Раньше на все случаи была одна подпись
    /// «темп не задан» — и она врала: темп посчитан и написан строкой ниже,
    /// просто ведёт он не к цели.
    enum GoalOutlook {
        case date(Date)
        /// Вес уже не выше цели.
        case reached
        /// Темп известен, но вес не снижается — цель не приближается.
        case notFalling
        /// Снижение есть, но дата уходит за горизонт (больше десяти лет).
        case tooSlow
        /// Меньше трёх взвешиваний за 30 дней — темпа нет.
        case noRate
    }

    var goalOutlook: GoalOutlook {
        guard let last, let toGoal else { return .noRate }
        guard toGoal > 0 else { return .reached }
        guard let slope else { return .noRate }
        guard slope < -0.004 else { return .notFalling }
        let days = toGoal / -slope
        guard days.isFinite, days < 3650 else { return .tooSlow }
        return .date(last.date.addingTimeInterval(days * Self.day))
    }

    /// Дата достижения цели по текущему темпу. nil, если вес не снижается.
    var goalDate: Date? {
        if case .date(let d) = goalOutlook { return d }
        return nil
    }

    /// Короткая пометка в правой колонке строки — там места на фразу нет.
    var goalDateLabel: String {
        switch goalOutlook {
        case .date(let d):  return Fmt.dayMonth(d)
        case .reached:      return L("goal reached")
        case .notFalling:   return L("not falling")
        case .tooSlow:      return L("very slow")
        case .noRate:       return L("not enough data")
        }
    }

    /// То же самое фразой — там, где под текст отведена целая строка.
    var goalHint: String {
        switch goalOutlook {
        case .date(let d):  return Fmt.dayMonth(d)
        case .reached:      return L("the goal is already reached")
        case .notFalling:   return L("weight isn't going down, so the goal isn't getting closer")
        case .tooSlow:      return L("at this rate the goal is more than ten years away")
        case .noRate:       return L("the rate appears after a few measurements")
        }
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
            // Через Fmt — там локаль берётся из языка ПРИЛОЖЕНИЯ, а не телефона:
            // иначе в английском интерфейсе столбики подписаны «ПН ВТ СР».
            let weekday = Fmt.weekday(date)
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

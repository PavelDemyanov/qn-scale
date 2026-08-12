import Foundation

/// Периоды графика.
///
/// Тег — ЭНУМ, а не `Double`: у прежнего `Picker` тег «Всё» равнялся
/// `max(7, длина истории)`, и на короткой истории два сегмента получали ОДИН
/// И ТОТ ЖЕ тег 7.0 — поведение сегментированного контрола в этом случае не
/// определено. Вдобавок тег «Всё» менялся после каждого взвешивания, и выбор
/// слетал сам собой.
enum WeightPeriod: String, CaseIterable, Identifiable {
    case d7, d30, d90, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .d7: return L("7 days")
        case .d30: return L("30 days")
        case .d90: return L("90 days")
        case .all: return L("All")
        }
    }

    /// Суток ДАННЫХ в окне; nil — вся история.
    var days: Double? {
        switch self {
        case .d7: return 7
        case .d30: return 30
        case .d90: return 90
        case .all: return nil
        }
    }
}

/// Ось времени графика: переводит доли окна (0…1) в даты и обратно.
///
/// ХВОСТ ПРОГНОЗА ЖИВЁТ ЗДЕСЬ, а не множителем ширины окна. Когда он считался
/// от окна (`tMax = t1 + windowDays * 0.3`), в момент, когда окно уезжало влево
/// и прогноз пропадал, масштаб по X скачком менялся на 30 % прямо посреди
/// протяжки: палец идёт ровно, а график под ним ускоряется.
struct WeightTimeline: Equatable {

    static let day: TimeInterval = 86_400

    /// Ячейка сетки = ЧАС. Мельче не нужно (взвешиваются раз в день), крупнее
    /// нельзя: при суточной ячейке минимальное окно было бы 48 суток.
    static let cellsPerDay: Double = 24

    /// Первое взвешивание.
    let start: Date
    /// Последнее взвешивание.
    let dataEnd: Date
    /// Правый край домена: `dataEnd` плюс хвост прогноза.
    let end: Date
    let cells: Int

    /// Хвост — свойство НАБОРА ДАННЫХ, а не окна. Потолок двое суток на неделю
    /// истории и не больше 14 суток вообще: на двухнедельной истории месячный
    /// прогноз — выдумка.
    static func tailDays(historyDays: Double) -> Double {
        Swift.max(0, Swift.min(14, historyDays * 0.3))
    }

    init(start: Date = Date(), dataEnd: Date = Date(), forecast: Bool = true) {
        let last = Swift.max(dataEnd, start)
        let historyDays = last.timeIntervalSince(start) / Self.day
        let tail = forecast ? Self.tailDays(historyDays: historyDays) : 0
        self.start = start
        self.dataEnd = last
        self.end = last.addingTimeInterval(tail * Self.day)
        let totalDays = Swift.max(end.timeIntervalSince(start) / Self.day, 1.0 / 24)
        self.cells = Swift.max(2, Int((totalDays * Self.cellsPerDay).rounded()) + 1)
    }

    var span: TimeInterval { Swift.max(end.timeIntervalSince(start), 3600) }
    var tail: TimeInterval { end.timeIntervalSince(dataEnd) }

    func date(at f: Double) -> Date {
        start.addingTimeInterval(Swift.min(Swift.max(f.isFinite ? f : 0, 0), 1) * span)
    }

    func fraction(of d: Date) -> Double {
        Swift.min(Swift.max(d.timeIntervalSince(start) / span, 0), 1)
    }

    /// Ширина окна в СУТКАХ ДАННЫХ, без хвоста прогноза — для подписи
    /// «диапазон · N дн.».
    func dataDays(_ w: ChartWindow) -> Double {
        Swift.max(0, Swift.min(date(at: w.w1), dataEnd).timeIntervalSince(date(at: w.w0)) / Self.day)
    }

    // MARK: Пресеты — связь с окном В ОБЕ СТОРОНЫ

    /// Пресет ВСЕГДА прижимается к правому краю данных — это ровно прежнее
    /// поведение `endDate = nil`, и именно оно делает связь взаимно
    /// однозначной. Хвост прогноза берётся долей 0,3 от ширины окна, но
    /// ЗАЖАТЫЙ реальным хвостом домена, — вид в момент нажатия остаётся
    /// прежним.
    func window(for p: WeightPeriod) -> ChartWindow {
        guard let n = p.days else { return .full }
        let tailShown = Swift.min(tail, n * 0.3 * Self.day)
        let hi = fraction(of: dataEnd.addingTimeInterval(tailShown))
        let lo = fraction(of: dataEnd.addingTimeInterval(-n * Self.day))
        return ChartWindow(w0: lo, w1: hi, cells: cells)
    }

    /// Пресеты, которые на ЭТОЙ истории означают разное.
    ///
    /// На трёхдневной истории «7 дней», «30 дней», «90 дней» и «Всё» дают одно
    /// и то же окно, и четыре сегмента, делающие одно и то же, врут о выборе:
    /// нажимаешь «30 дней», а подсвечивается «7 дней» (первый совпавший).
    /// Поэтому короткие пресеты просто не показываются, пока история их не
    /// переросла. «Всё» есть всегда.
    var availablePeriods: [WeightPeriod] {
        let historyDays = dataEnd.timeIntervalSince(start) / Self.day
        var out = WeightPeriod.allCases.filter { p in
            guard let n = p.days else { return false }
            return n < historyDays - 0.5
        }
        out.append(.all)
        return out
    }

    /// Обратная сторона той же связи. Считается ЧЕРЕЗ `window(for:)`, поэтому
    /// круг «пресет → окно → пресет» замкнут по построению, а не по совпадению
    /// двух формул. Не совпало ни с чем (щипок дал 43,7 дня) — НИ ОДИН сегмент
    /// не подсвечен: подсветить наугад значит соврать ровно там, где щётка
    /// говорит правду.
    func period(of w: ChartWindow) -> WeightPeriod? {
        availablePeriods.first { p in
            let c = window(for: p)
            return abs(c.w0 - w.w0) < 1e-4 && abs(c.w1 - w.w1) < 1e-4
        }
    }
}

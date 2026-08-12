import CoreGraphics
import Foundation
import SwiftData

/// Одно измерение обычной структурой.
///
/// Снимок `@Model`-объектов делается ОДИН раз на смену истории: геометрия,
/// обзор щётки, поиск метки и таблица дельт обращаются к весу и дате десятки
/// тысяч раз за секунду жеста, а каждое обращение к SwiftData — поход в
/// хранилище с регистрацией наблюдения, а не чтение поля структуры.
struct WeightPoint: Identifiable, Equatable {
    let id: PersistentIdentifier
    let date: Date
    let kg: Double
    let fat: Double?
    /// Перед этой точкой перерыв дольше `gapDays` — линия на участке домысел.
    /// Признак ПАРЫ, поэтому живёт у правой точки.
    let gapBefore: Bool
}

/// Данные графика одним снимком: точки, дельты, ось времени, обзор для щётки.
struct WeightSnapshot {

    /// Дольше этого перерыв между взвешиваниями считается «данных не было»,
    /// и линия на этом отрезке — интерполяция. Двое суток: при обычном
    /// ежедневном взвешивании пропуск одного дня ещё не разрыв.
    static let gapDays: Double = 2

    var version = 0
    var points: [WeightPoint] = []
    var deltas: [PersistentIdentifier: Double] = [:]
    var timeline = WeightTimeline()
    var slope: Double?
    /// Мини-превью всей истории для щётки: x — доля домена, y — доля размаха.
    var overview: [CGPoint] = []
    var overviewBreaks: [Bool] = []

    static let empty = WeightSnapshot()
    var isEmpty: Bool { points.isEmpty }

    func range(_ w: ChartWindow) -> ArraySlice<WeightPoint> {
        let a = timeline.date(at: w.w0), b = timeline.date(at: w.w1)
        guard let f = points.firstIndex(where: { $0.date >= a }),
              let l = points.lastIndex(where: { $0.date <= b }), f <= l else { return [] }
        return points[f...l]
    }

    /// Значение кривой РОВНО в момент `at` — линейная интерполяция между
    /// соседями. Нужно вертикальному масштабу: точка, уезжающая за край окна,
    /// заменяется краевым значением, которое к ней стремится, — диапазон
    /// меняется непрерывно вместо прыжка всей кривой.
    func value(at d: Date) -> Double? {
        guard let first = points.first, let last = points.last else { return nil }
        if d <= first.date { return first.kg }
        if d >= last.date { return last.kg }
        guard let i = points.firstIndex(where: { $0.date >= d }), i > 0 else { return first.kg }
        let a = points[i - 1], b = points[i]
        let t = b.date.timeIntervalSince(a.date)
        guard t > 0 else { return b.kg }
        return a.kg + (b.kg - a.kg) * (d.timeIntervalSince(a.date) / t)
    }

    /// `items` обязаны идти ПО ВОЗРАСТАНИЮ даты — так их и отдаёт `@Query`.
    static func build(items: [WeighIn], profile: Profile, goal: Double,
                      showForecast: Bool, version: Int) -> WeightSnapshot {
        guard let first = items.first, let last = items.last else { return .empty }
        var s = WeightSnapshot()
        s.version = version
        var pts: [WeightPoint] = []
        pts.reserveCapacity(items.count)
        var prev: WeighIn?
        for it in items {
            let gap = prev.map {
                it.date.timeIntervalSince($0.date) > gapDays * WeightTimeline.day
            } ?? false
            pts.append(WeightPoint(id: it.persistentModelID, date: it.date, kg: it.weightKg,
                                   fat: it.fatPercent(for: profile), gapBefore: gap))
            if let p = prev { s.deltas[it.persistentModelID] = it.weightKg - p.weightKg }
            prev = it
        }
        s.points = pts
        s.slope = Stats(items: items, goal: goal).slope
        s.timeline = WeightTimeline(start: first.date, dataEnd: last.date,
                                    forecast: showForecast && s.slope != nil)
        let overview = overviewSeries(pts, timeline: s.timeline)
        s.overview = overview.0
        s.overviewBreaks = overview.1
        return s
    }

    /// Обзор для щётки: до 120 точек (полоса шириной в треть экрана подробнее
    /// не покажет), нормализованных в 0…1. Считается ОДИН раз на смену истории
    /// — в кадре жеста щётка не делает ни одного прохода по данным.
    private static func overviewSeries(_ pts: [WeightPoint],
                                       timeline: WeightTimeline) -> ([CGPoint], [Bool]) {
        guard pts.count > 1 else { return ([], []) }
        // Разрыв — свойство ОТРЕЗКА, а не выбранной точки: при прореживании
        // флаг собирается ИЛИ по всем пропущенным точкам, иначе на истории
        // длиннее 120 измерений перерывы из щётки просто исчезали.
        let step = Swift.max(1, pts.count / 120)
        var picked: [WeightPoint] = []
        var breaks: [Bool] = []
        var from = 0
        for i in stride(from: 0, to: pts.count, by: step) {
            picked.append(pts[i])
            breaks.append(pts[from...i].contains { $0.gapBefore })
            from = i + 1
        }
        if picked.last?.id != pts.last?.id, let l = pts.last {
            picked.append(l)
            breaks.append(from < pts.count ? pts[from...].contains { $0.gapBefore } : l.gapBefore)
        }
        let ws = picked.map(\.kg)
        let lo = ws.min() ?? 0, hi = ws.max() ?? 1
        let span = Swift.max(hi - lo, 0.6)
        let out = picked.map {
            CGPoint(x: timeline.fraction(of: $0.date), y: ($0.kg - lo) / span)
        }
        return (out, breaks)
    }
}

/// Сводка окна: считается ОДИН раз на ЗАФИКСИРОВАННОЕ окно, никогда в `body`.
/// Прежде «видимые измерения» вычислялись около девяти раз за проход тела,
/// наклон — дважды, а дельта каждой строки списка — линейным поиском по всей
/// истории.
struct WindowDigest: Equatable {
    var window: ChartWindow?
    var count = 0
    var lo: Double?
    var hi: Double?
    var change: Double?
    var rows: [WeightPoint] = []
    /// Втягивать ли цель в вертикальный масштаб. Решение принимается по
    /// ЗАФИКСИРОВАННОМУ окну: порог «цель недалеко от данных» переключался
    /// прямо при панорамировании и дёргал масштаб на ровном месте.
    var pullGoal = true
    static let empty = WindowDigest()
}

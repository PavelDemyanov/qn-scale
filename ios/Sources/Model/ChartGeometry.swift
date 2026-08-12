import SwiftUI
import SwiftData

/// Геометрия графика веса — порт функций `geom` и `smooth` из прототипа.
/// Считает масштаб по видимому окну, сглаживает кривую и строит пунктир прогноза.
struct ChartGeometry {

    struct Sample: Identifiable {
        let id: PersistentIdentifier
        let point: CGPoint
        let item: WeighIn
    }

    /// Дольше этого перерыв между взвешиваниями считается «данных не было»,
    /// и линия на этом отрезке — интерполяция. Двое суток: при обычном
    /// ежедневном взвешивании пропуск одного дня ещё не разрыв.
    static let gapDays: Double = 2

    struct Padding {
        var top: CGFloat = 0
        var bottom: CGFloat = 0
        var leading: CGFloat = 0
        var trailing: CGFloat = 0
    }

    let size: CGSize
    let padding: Padding
    let lo: Double
    let hi: Double
    let t0: Date
    let t1: Date
    let tMax: Date
    let samples: [Sample]
    /// Вся кривая одним путём — по ней строится заливка.
    let line: Path
    /// Кривая между СОСЕДНИМИ по времени измерениями (разрыв не больше
    /// `gapDays`) — рисуется цветом данных.
    let lineSolid: Path
    /// Участки, где измерений не было дольше `gapDays`: линия там —
    /// домысел, а не данные, поэтому рисуется серым (заказ владельца
    /// 12.08.2026: «чтобы было понятно, что данные интерполированы»).
    let lineGap: Path
    let area: Path
    let forecast: Path
    let goalY: CGFloat
    let goalInRange: Bool

    var lastPoint: CGPoint? { samples.last?.point }

    func x(_ date: Date) -> CGFloat {
        let span = tMax.timeIntervalSince(t0)
        guard span > 0 else { return padding.leading }
        let k = date.timeIntervalSince(t0) / span
        return padding.leading + CGFloat(k) * (size.width - padding.leading - padding.trailing)
    }

    func y(_ weight: Double) -> CGFloat {
        guard hi > lo else { return padding.top }
        let k = (hi - weight) / (hi - lo)
        return padding.top + CGFloat(k) * (size.height - padding.top - padding.bottom)
    }

    /// Ближайшая к точке касания засечка — для выбора измерения на графике.
    func nearest(toX px: CGFloat, maxDistance: CGFloat = 44) -> Sample? {
        guard let best = samples.min(by: { abs($0.point.x - px) < abs($1.point.x - px) }) else { return nil }
        return abs(best.point.x - px) <= maxDistance ? best : nil
    }

    static func build(items: [WeighIn],
                      goal: Double,
                      windowDays: Double,
                      endDate: Date,
                      size: CGSize,
                      padding: Padding,
                      forecastDays: Double,
                      slope: Double?,
                      includeGoal: Bool = true) -> ChartGeometry {

        let day: TimeInterval = 86_400
        let t1 = endDate
        let t0 = t1.addingTimeInterval(-windowDays * day)

        // Прогноз рисуем только если окно доведено до последнего измерения.
        let lastItem = items.last
        let atEnd = lastItem.map { t1 >= $0.date.addingTimeInterval(-day / 2) } ?? false
        let fcDays = (atEnd && slope != nil) ? forecastDays : 0
        let tMax = t1.addingTimeInterval(fcDays * day)

        let visible = items.filter { $0.date >= t0 && $0.date <= t1 }
        // Кривую строим ШИРЕ окна: берём по одному измерению за каждым краем,
        // иначе линия обрывается о край экрана, а при пустой неделе внутри
        // окна пропадает вовсе — график выглядел «оторванным» (12.08.2026).
        // Масштаб по вертикали при этом считаем ТОЛЬКО по видимым точкам:
        // соседи за кадром не должны сплющивать кривую.
        let before = items.last { $0.date < t0 }
        let after = items.first { $0.date > t1 }
        let curveItems = [before].compactMap { $0 } + visible + [after].compactMap { $0 }
        let weights = visible.map(\.weightKg)

        var lo = weights.min() ?? goal
        var hi = weights.max() ?? goal

        let fcEnd = (lastItem?.weightKg ?? goal) + (slope ?? 0) * fcDays
        if fcDays > 0 {
            lo = Swift.min(lo, fcEnd)
            hi = Swift.max(hi, fcEnd)
        }
        var span = Swift.max(hi - lo, 0.6)
        // Линию цели втягиваем в кадр, только если она недалеко от данных.
        if includeGoal, goal > lo - span * 1.35 {
            lo = Swift.min(lo, goal)
            hi = Swift.max(hi, goal)
        }
        span = Swift.max(hi - lo, 0.6)
        let padY = span * 0.14
        lo -= padY
        hi += padY

        // Замыкание-обёртка: нужны те же формулы, что и в методах x/y ниже.
        let spanT = tMax.timeIntervalSince(t0)
        let plotW = size.width - padding.leading - padding.trailing
        let plotH = size.height - padding.top - padding.bottom
        func px(_ d: Date) -> CGFloat {
            guard spanT > 0 else { return padding.leading }
            return padding.leading + CGFloat(d.timeIntervalSince(t0) / spanT) * plotW
        }
        func py(_ w: Double) -> CGFloat {
            guard hi > lo else { return padding.top }
            return padding.top + CGFloat((hi - w) / (hi - lo)) * plotH
        }

        // Метки и точки — только по ВИДИМЫМ измерениям: соседи за кадром
        // нужны линии, но выбирать их пальцем и рисовать точками нечего.
        let samples = visible.map {
            Sample(id: $0.persistentModelID, point: CGPoint(x: px($0.date), y: py($0.weightKg)), item: $0)
        }
        let pts = curveItems.map { CGPoint(x: px($0.date), y: py($0.weightKg)) }
        // Разрыв в данных — свойство ПАРЫ соседних измерений, поэтому флаги
        // считаем по тем же элементам, из которых построены точки.
        let interpolated = zip(curveItems, curveItems.dropFirst()).map {
            $1.date.timeIntervalSince($0.date) > gapDays * day
        }

        let segments = smoothSegments(pts)
        var line = Path()
        var lineSolid = Path()
        var lineGap = Path()
        for (i, seg) in segments.enumerated() {
            line.addPath(seg.path)
            if i < interpolated.count, interpolated[i] {
                lineGap.addPath(seg.path)
            } else {
                lineSolid.addPath(seg.path)
            }
        }

        var area = Path()
        if let first = pts.first, let last = pts.last {
            area = line
            let base = size.height - padding.bottom
            area.addLine(to: CGPoint(x: last.x, y: base))
            area.addLine(to: CGPoint(x: first.x, y: base))
            area.closeSubpath()
        }

        var forecast = Path()
        if fcDays > 0, let last = pts.last {
            forecast.move(to: last)
            forecast.addLine(to: CGPoint(x: px(tMax), y: py(fcEnd)))
        }

        let rawGoalY = py(goal)
        let base = size.height - padding.bottom

        return ChartGeometry(size: size, padding: padding, lo: lo, hi: hi,
                             t0: t0, t1: t1, tMax: tMax, samples: samples,
                             line: line, lineSolid: lineSolid, lineGap: lineGap,
                             area: area, forecast: forecast,
                             goalY: Swift.max(padding.top, Swift.min(base, rawGoalY)),
                             goalInRange: rawGoalY >= padding.top && rawGoalY <= base)
    }

    /// Сглаживание Катмулла–Рома, переведённое в кубические Безье — как в
    /// прототипе, но ПООТРЕЗОЧНО: каждый отрезок между соседними точками
    /// возвращается своим путём, чтобы интерполированные участки можно было
    /// закрасить отдельно. Контрольные точки по-прежнему смотрят на соседей,
    /// поэтому склейка отрезков даёт ту же гладкую кривую, что и раньше.
    private static func smoothSegments(_ p: [CGPoint]) -> [(path: Path, from: CGPoint, to: CGPoint)] {
        guard p.count > 1 else { return [] }
        var out: [(Path, CGPoint, CGPoint)] = []
        for i in 0..<(p.count - 1) {
            let p1 = p[i], p2 = p[i + 1]
            var seg = Path()
            seg.move(to: p1)
            if p.count < 3 {
                seg.addLine(to: p2)
            } else {
                let p0 = i > 0 ? p[i - 1] : p[i]
                let p3 = i + 2 < p.count ? p[i + 2] : p[i + 1]
                let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 8, y: p1.y + (p2.y - p0.y) / 8)
                let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 8, y: p2.y - (p3.y - p1.y) / 8)
                seg.addCurve(to: p2, control1: c1, control2: c2)
            }
            out.append((seg, p1, p2))
        }
        return out
    }
}

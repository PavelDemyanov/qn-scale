import SwiftUI
import SwiftData

/// Всё, что нужно нарисовать в кадре. Строится РОВНО ОДИН раз за проход тела
/// карточки и передаётся вниз готовым.
///
/// Прежняя `ChartGeometry` собиралась заново на КАЖДЫЙ из шести видов кривой
/// плюс отдельно ради `boundingRect` заливки плюс ещё раз в самой `HistoryView`
/// — семь-восемь полных сборок на кадр, и каждая рожала по отдельному пути на
/// каждый отрезок.
struct WeightPlot {

    struct Padding: Equatable {
        var top: CGFloat = 0
        var bottom: CGFloat = 0
        var leading: CGFloat = 0
        var trailing: CGFloat = 0
    }

    struct Sample: Identifiable {
        let id: PersistentIdentifier
        let date: Date
        let kg: Double
        /// У ручных записей и импорта из «Здоровья» импеданса нет — жира тоже.
        let fat: Double?
        /// Изменение к предыдущему измерению — берётся ГОТОВЫМ из снимка.
        let delta: Double?
        /// Вершина или впадина кривой: соседи по обе стороны ниже (или оба
        /// выше). Только такие точки подписываются плашками — на подписи у
        /// каждой точки график превращается в кашу.
        let isExtreme: Bool
        let point: CGPoint
    }

    /// Штамп СТРУКТУРОЙ: по нему полотно отвечает на `==`, и Canvas не
    /// перерисовывается от движения метки или тултипа.
    struct Stamp: Equatable {
        var version = -1
        var w0 = 0.0
        var w1 = 1.0
        var width: CGFloat = 0
        var height: CGFloat = 0
        var goal = 0.0
        var pullGoal = false
        var goalLine = false
        var forecast = false
        var dots = false
        var niceScale = false
        var fat = false
        var deltas = false
        var smooth = false
    }

    var stamp = Stamp()
    var size: CGSize = .zero
    var padding = Padding()
    var t0 = Date()
    var t1 = Date()
    var lo = 0.0
    var hi = 1.0
    var step = 1.0
    var samples: [Sample] = []
    var solid = Path()
    var gap = Path()
    /// Заливка под УЧАСТКАМИ С ДАННЫМИ и под интерполяцией — врозь: под серой
    /// линией фон тоже серый, иначе домысел выглядит как измерения.
    var areaSolid = Path()
    var areaGap = Path()
    var forecast = Path()
    var dots = Path()
    var areaTop: CGFloat = 0
    var areaBottom: CGFloat = 1
    var goalY: CGFloat = 0
    var goalInRange = false
    var lastPoint: CGPoint?

    /// Второй ряд — процент жира. Своя шкала: проценты и килограммы несравнимы,
    /// и на общей оси обе кривые расплющило бы в прямые.
    var fatLine = Path()
    var fatLo = 0.0
    var fatHi = 1.0
    var fatStep = 0.0
    /// Ряд включён И в окне есть хотя бы одно измерение с жиром.
    var hasFat = false

    /// ПОЛОСА ЛИНИИ — без колонки подписей справа. Именно её ширину получает
    /// жестовый слой: прежде сдвиг делился на полную ширину вью и не учитывал
    /// хвост, отчего график ехал заметно медленнее пальца.
    var plot: CGRect {
        CGRect(x: padding.leading, y: 0,
               width: Swift.max(1, size.width - padding.leading - padding.trailing),
               height: size.height)
    }

    func x(_ d: Date) -> CGFloat {
        let span = t1.timeIntervalSince(t0)
        guard span > 0 else { return padding.leading }
        return padding.leading + CGFloat(d.timeIntervalSince(t0) / span) * plot.width
    }

    func y(_ v: Double) -> CGFloat {
        guard hi > lo else { return padding.top }
        return padding.top + CGFloat((hi - v) / (hi - lo)) * (size.height - padding.top - padding.bottom)
    }

    /// Жир — в своей шкале, но по ТОЙ ЖЕ высоте кадра, что и вес.
    func fatY(_ v: Double) -> CGFloat {
        guard fatHi > fatLo else { return padding.top }
        return padding.top + CGFloat((fatHi - v) / (fatHi - fatLo)) * (size.height - padding.top - padding.bottom)
    }

    func date(atX px: CGFloat) -> Date {
        guard plot.width > 0 else { return t0 }
        let f = Double((px - plot.minX) / plot.width)
        return t0.addingTimeInterval(t1.timeIntervalSince(t0) * Swift.min(Swift.max(f, 0), 1))
    }

    /// Ближайшая к пальцу засечка. Порог 44 pt: без него долгое нажатие в
    /// пустой части графика цепляло сколь угодно далёкую точку, и подпись врала.
    func nearest(toX px: CGFloat, maxDistance: CGFloat = 44) -> Sample? {
        guard let best = samples.min(by: { abs($0.point.x - px) < abs($1.point.x - px) })
        else { return nil }
        return abs(best.point.x - px) <= maxDistance ? best : nil
    }

    /// Вертикальный размах ВСЕГО, что видно в окне, кроме цели: измерения,
    /// значения ровно на краях окна и видимая часть прогноза.
    ///
    /// Один расчёт на две задачи — шкалу и решение «втягивать ли цель». Порознь
    /// они разошлись сразу: порог, посчитанный по одним лишь измерениям, оказался
    /// строже прежнего (77,96 против 76,79) и молча выкинул линию цели 77,5,
    /// которая до того была на графике.
    static func dataExtent(_ s: WeightSnapshot, t0: Date, t1: Date,
                           showForecast: Bool) -> (lo: Double, hi: Double)? {
        guard !s.isEmpty else { return nil }
        var vals: [Double] = []
        for pt in s.points where pt.date >= t0 && pt.date <= t1 { vals.append(pt.kg) }
        // Значения РОВНО НА КРАЯХ окна: из-за них диапазон меняется НЕПРЕРЫВНО.
        // Экстремум, уезжающий за кадр, в момент выхода равен краевому значению,
        // так что кривая едет вместо прыжка.
        if let a = s.value(at: t0) { vals.append(a) }
        if let b = s.value(at: Swift.min(t1, s.timeline.dataEnd)) { vals.append(b) }
        // Прогноз входит ВИДИМОЙ частью: выезжая за правый край, он перестаёт
        // влиять постепенно, а не разом по порогу «окно доведено до конца».
        if showForecast, let slope = s.slope, let last = s.points.last,
           s.timeline.tail > 0, t1 > last.date {
            let shown = Swift.min(t1, s.timeline.end).timeIntervalSince(last.date) / WeightTimeline.day
            vals.append(last.kg + slope * shown)
        }
        guard let lo = vals.min(), let hi = vals.max() else { return nil }
        return (lo, hi)
    }

    /// Помещается ли цель в кадр вместе с данными. Считается по
    /// ЗАФИКСИРОВАННОМУ окну — см. `WindowDigest.pullGoal`: порог, пересчитанный
    /// на каждом кадре, переключался прямо при панорамировании и дёргал масштаб.
    static func goalFits(_ s: WeightSnapshot, window: ChartWindow,
                         goal: Double, showForecast: Bool) -> Bool {
        let t0 = s.timeline.date(at: window.w0), t1 = s.timeline.date(at: window.w1)
        guard let e = dataExtent(s, t0: t0, t1: t1, showForecast: showForecast) else { return true }
        // Порог СИММЕТРИЧЕН: цель выше сегодняшнего веса (набор массы) так же
        // растягивает шкалу и так же плющит кривую в прямую, как цель далеко
        // внизу.
        let m = Swift.max(e.hi - e.lo, 0.6) * 1.35
        return goal > e.lo - m && goal < e.hi + m
    }

    static func build(_ s: WeightSnapshot, window: ChartWindow, goal: Double,
                      pullGoal: Bool, showGoalLine: Bool, showForecast: Bool,
                      showDots: Bool, size: CGSize, padding: Padding,
                      niceScale: Bool = false, showFat: Bool = false,
                      showDeltas: Bool = false, smooth: Bool = false) -> WeightPlot {
        var p = WeightPlot()
        p.size = size
        p.padding = padding
        p.stamp = Stamp(version: s.version, w0: window.w0, w1: window.w1,
                        width: size.width, height: size.height, goal: goal,
                        pullGoal: pullGoal, goalLine: showGoalLine,
                        forecast: showForecast, dots: showDots, niceScale: niceScale,
                        fat: showFat, deltas: showDeltas, smooth: smooth)
        guard size.width > 1, size.height > 1, !s.isEmpty else { return p }

        p.t0 = s.timeline.date(at: window.w0)
        p.t1 = s.timeline.date(at: window.w1)

        // ---- вертикальный диапазон
        let extent = dataExtent(s, t0: p.t0, t1: p.t1, showForecast: showForecast)
        var fcEnd: Double?
        if showForecast, let slope = s.slope, let last = s.points.last, s.timeline.tail > 0 {
            let full = s.timeline.end.timeIntervalSince(last.date) / WeightTimeline.day
            fcEnd = last.kg + slope * full
        }

        var lo = extent?.lo ?? goal
        var hi = extent?.hi ?? goal
        if pullGoal {
            lo = Swift.min(lo, goal)
            hi = Swift.max(hi, goal)
        }
        // Запас по вертикали. С плашками он больше: подпись занимает над своей
        // точкой ~25 пунктов, и на прежних 14 % самая верхняя точка окна
        // оказывалась к краю кадра ближе, чем высота плашки, — та садилась
        // прямо на вершину кривой.
        let pad = Swift.max(hi - lo, 0.6) * (showDeltas ? 0.30 : 0.14)
        lo -= pad
        hi += pad
        if niceScale {
            // Круглые деления нужны ТОЛЬКО там, где подписана ось: иначе они
            // без всякой пользы отдают кривой часть высоты кадра, и спарклайн
            // на главном экране заметно плющится.
            let n = WeightAxis.nice(lo: lo, hi: hi)
            p.lo = n.lo
            p.hi = n.hi
            p.step = n.step
        } else {
            p.lo = lo
            p.hi = hi
            p.step = 0
        }

        // ---- какие точки нужны кривой
        // Берём ПО ОДНОЙ ШИРЕ окна с каждой стороны: иначе линия обрывается о
        // край экрана. Лишнее срежет отсечка при отрисовке.
        let firstIn = s.points.firstIndex { $0.date >= p.t0 }
        let lastIn = s.points.lastIndex { $0.date <= p.t1 }
        var a: Int, b: Int
        if let f = firstIn, let l = lastIn, f <= l {
            a = f
            b = l
        } else {
            // В окне нет ни одного измерения (перерыв длиннее периода) — берём
            // соседей по обе стороны, чтобы линия всё-таки была.
            let after = firstIn ?? s.points.count
            a = Swift.max(0, after - 1)
            b = Swift.min(s.points.count - 1, after)
        }
        let from = Swift.max(0, a - 1)
        let to = Swift.min(s.points.count - 1, b + 1)
        guard from <= to else { return p }
        let seg = Array(s.points[from...to])
        let pts = seg.map { CGPoint(x: p.x($0.date), y: p.y($0.kg)) }

        // ---- кривая: ПРЯМЫЕ отрезки, по участку на каждый род линии
        //
        // Сглаживание убрано (заказ владельца 12.08.2026: «линии загибаются
        // петлёй назад, чего быть не может»). Это не вкусовщина: контрольные
        // точки Катмулла–Рома смотрят на соседей, и на зубчатых данных —
        // а вес и есть зубчатые данные, ±1 кг за сутки при шаге в пиксели —
        // отрезок перелетал вершину и заворачивался петлёй, показывая вес,
        // которого не было. Прямая между измерениями честнее: она ровно то,
        // что известно, и ничего не добавляет. Так же сделано в EUC Logger.
        if pts.count > 1 {
            let base = size.height - padding.bottom
            var run: [CGPoint] = [pts[0]]
            var runIsGap = seg[1].gapBefore

            func flush() {
                guard run.count > 1 else { return }
                var line = Path()
                // Заливка участка — замкнутая фигура до основания. Соседние
                // участки делят крайнюю точку, поэтому заливки смыкаются без
                // щели.
                var area = Path()
                area.move(to: CGPoint(x: run[0].x, y: base))
                area.addLine(to: run[0])
                if smooth {
                    // Сглаживание, которое не выходит за пределы измерений —
                    // см. MonotoneCurve. Линия и заливка идут по ОДНИМ
                    // сегментам, иначе заливка выглядывала бы из-под кривой.
                    line.move(to: run[0])
                    for sg in MonotoneCurve.segments(run) {
                        line.addCurve(to: sg.end, control1: sg.control1, control2: sg.control2)
                        area.addCurve(to: sg.end, control1: sg.control1, control2: sg.control2)
                    }
                } else {
                    line.addLines(run)
                    for pt in run.dropFirst() { area.addLine(to: pt) }
                }
                area.addLine(to: CGPoint(x: run[run.count - 1].x, y: base))
                area.closeSubpath()
                if runIsGap {
                    p.gap.addPath(line)
                    p.areaGap.addPath(area)
                } else {
                    p.solid.addPath(line)
                    p.areaSolid.addPath(area)
                }
            }

            for i in 1..<pts.count {
                let isGap = seg[i].gapBefore
                if isGap != runIsGap {
                    flush()
                    run = [pts[i - 1]]
                    runIsGap = isGap
                }
                run.append(pts[i])
            }
            flush()

            // Границы градиента — по ОБЕИМ заливкам разом, чтобы синяя и серая
            // гасли на одной высоте.
            let r = p.areaSolid.boundingRect.union(p.areaGap.boundingRect)
            if size.height > 0, !r.isNull, !r.isEmpty, r.height.isFinite {
                p.areaTop = Swift.max(0, r.minY / size.height)
                p.areaBottom = Swift.min(1, r.maxY / size.height)
            }
        }

        // ---- второй ряд: процент жира
        //
        // Шкала считается ПО ВИДИМОМУ ОКНУ, как и вес: иначе кривая жира,
        // размах которого за всю историю вдвое шире дневного, прижималась бы
        // к середине кадра и не читалась вовсе.
        if showFat {
            var vals: [Double] = []
            for pt in s.points where pt.date >= p.t0 && pt.date <= p.t1 {
                if let f = pt.fat { vals.append(f) }
            }
            if let flo = vals.min(), let fhi = vals.max() {
                let fpad = Swift.max(fhi - flo, 0.6) * 0.14
                // Засечек РОВНО столько же, сколько у веса: сетку рисует вес, и
                // оранжевые подписи обязаны стоять на его линиях, а не между.
                let want = WeightAxis.ticks(lo: p.lo, hi: p.hi, step: p.step).count
                let n = WeightAxis.aligned(lo: flo - fpad, hi: fhi + fpad, ticks: want)
                p.fatLo = n.lo
                p.fatHi = n.hi
                p.fatStep = n.step
                p.hasFat = true
                // Линия РВЁТСЯ там, где жира нет: у записей, добавленных руками
                // или пришедших из «Здоровья», импеданса не бывает, и тянуть
                // отрезок сквозь них значит выдумывать измерение.
                var run: [CGPoint] = []
                func flushFat() {
                    guard run.count > 1 else { return }
                    var line = Path()
                    if smooth {
                        line.move(to: run[0])
                        for sg in MonotoneCurve.segments(run) {
                            line.addCurve(to: sg.end, control1: sg.control1, control2: sg.control2)
                        }
                    } else {
                        line.addLines(run)
                    }
                    p.fatLine.addPath(line)
                }
                for q in seg {
                    guard let f = q.fat else {
                        flushFat()
                        run = []
                        continue
                    }
                    run.append(CGPoint(x: p.x(q.date), y: p.fatY(f)))
                }
                flushFat()
            }
        }

        // ---- точки, прогноз, цель
        // Экстремумы ищутся по `seg` — он шире окна на точку с каждой стороны,
        // поэтому у крайних видимых засечек соседи настоящие, а не обрезанные
        // краем кадра.
        p.samples = seg.indices.compactMap { i -> Sample? in
            let q = seg[i]
            guard q.date >= p.t0, q.date <= p.t1 else { return nil }
            let extreme: Bool
            if showDeltas, i > 0, i < seg.count - 1 {
                // Произведение разностей с соседями положительно и у вершины,
                // и у впадины; ноль (сосед с тем же весом) экстремумом не
                // считается — подписывать плато нечем.
                extreme = (q.kg - seg[i - 1].kg) * (q.kg - seg[i + 1].kg) > 0
            } else {
                extreme = false
            }
            // Дельта достаётся из словаря ТОЛЬКО когда её собираются рисовать:
            // на кадрах жеста в «Истории» это лишний поиск на каждую засечку.
            return Sample(id: q.id, date: q.date, kg: q.kg, fat: q.fat,
                          delta: showDeltas ? s.deltas[q.id] : nil,
                          isExtreme: extreme,
                          point: CGPoint(x: p.x(q.date), y: p.y(q.kg)))
        }
        if showDots {
            for sm in p.samples {
                p.dots.addEllipse(in: CGRect(x: sm.point.x - 2.6, y: sm.point.y - 2.6,
                                             width: 5.2, height: 5.2))
            }
        }
        if let last = s.points.last {
            let end = CGPoint(x: p.x(last.date), y: p.y(last.kg))
            p.lastPoint = end
            if let e = fcEnd {
                p.forecast.move(to: end)
                p.forecast.addLine(to: CGPoint(x: p.x(s.timeline.end), y: p.y(e)))
            }
        }
        let rawGoalY = p.y(goal)
        let base = size.height - padding.bottom
        p.goalY = Swift.max(padding.top, Swift.min(base, rawGoalY))
        p.goalInRange = rawGoalY >= padding.top && rawGoalY <= base
        return p
    }
}

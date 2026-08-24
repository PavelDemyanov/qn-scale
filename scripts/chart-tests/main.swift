import Foundation

// Проверки ядра графика: окно, щётка, ось времени, шкала. Всё это чистая
// арифметика без SwiftUI и SwiftData, поэтому собирается и гоняется за секунду
// (см. scripts/chart-tests.sh). Каждая проверка сторожит инвариант, который
// уже ломался: смотрите комментарии в самих файлах.

var failures = 0
var checks = 0

func check(_ ok: Bool, _ what: String, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if !ok {
        failures += 1
        let d = detail()
        print("❌ \(what)\(d.isEmpty ? "" : " — \(d)")")
    }
}

func near(_ a: Double, _ b: Double, _ eps: Double = 1e-6) -> Bool { abs(a - b) <= eps }

// MARK: Пол окна

let day: TimeInterval = 86_400
let hour: TimeInterval = 3600

do {
    // История ровно 100 суток, ячейка — час.
    let start = Date(timeIntervalSinceReferenceDate: 0)
    let t = WeightTimeline(start: start, dataEnd: start.addingTimeInterval(100 * day), forecast: false)
    let floor = ChartWindow.minSpan(cells: t.cells)
    let w = ChartWindow(w0: 0.5, w1: 0.5, cells: t.cells)   // схлопнутое окно
    check(near(w.span, floor, 1e-9), "схлопнутое окно расширяется до пола")
    let hours = w.span * Double(t.cells - 1)
    check(near(hours, Double(ChartWindow.minCells), 1e-6),
          "пол окна равен minCells часов", "получилось \(hours)")

    // Пол в ЯЧЕЙКАХ, а не в долях: на вдвое длинной истории тот же пол в часах.
    let t2 = WeightTimeline(start: start, dataEnd: start.addingTimeInterval(200 * day), forecast: false)
    let w2 = ChartWindow(w0: 0.5, w1: 0.5, cells: t2.cells)
    let hours2 = w2.span * Double(t2.cells - 1)
    check(near(hours2, Double(ChartWindow.minCells), 1e-6),
          "пол окна не зависит от длины истории", "получилось \(hours2)")

    // Перевёрнутые края чинятся молча, а не роняют.
    let flipped = ChartWindow(w0: 0.8, w1: 0.2, cells: t.cells)
    check(flipped.w0 < flipped.w1, "перевёрнутые края меняются местами")
    let nan = ChartWindow(w0: .nan, w1: .infinity, cells: t.cells)
    check(nan.w0.isFinite && nan.w1.isFinite, "нечисло не проходит в окно")
    check(ChartWindow.minSpan(cells: 1) == 1, "сетки нет — окно только целиком")
}

// MARK: Щипок и протяжка

do {
    let cells = 2401                                   // 100 суток по часу
    let w = ChartWindow(w0: 0.4, w1: 0.6, cells: cells)

    // Якорь: глобальная доля точки под пальцами остаётся на месте.
    for anchor in [0.0, 0.25, 0.5, 0.75, 1.0] {
        let z = w.zoomed(by: 2, around: anchor, cells: cells)
        let before = w.w0 + anchor * w.span
        let after = z.w0 + anchor * z.span
        check(near(before, after, 1e-9), "щипок держит якорь \(anchor)",
              "было \(before), стало \(after)")
    }

    // У края домена окно ЕДЕТ, а не теряет ширину.
    let atEdge = ChartWindow(w0: 0.0, w1: 0.2, cells: cells)
    let zoomedOut = atEdge.zoomed(by: 0.5, around: 0, cells: cells)
    check(near(zoomedOut.span, 0.4, 1e-9), "у края окно расширяется внутрь домена",
          "ширина \(zoomedOut.span)")
    let panned = atEdge.panned(byWindowFraction: -5, cells: cells)
    check(near(panned.span, atEdge.span, 1e-9), "протяжка за край не теряет ширину")
    check(panned.w0 == 0, "протяжка за левый край упирается в ноль")
    let pannedRight = ChartWindow(w0: 0.8, w1: 1, cells: cells)
        .panned(byWindowFraction: 5, cells: cells)
    check(near(pannedRight.span, 0.2, 1e-9) && pannedRight.w1 == 1,
          "протяжка за правый край не теряет ширину")

    // Вырожденный масштаб ничего не двигает.
    check(w.zoomed(by: 0, around: 0.5, cells: cells) == w, "нулевой масштаб не двигает окно")
    check(w.zoomed(by: .nan, around: 0.5, cells: cells) == w, "нечисловой масштаб не двигает окно")
    check(w.panned(byWindowFraction: .nan, cells: cells) == w, "нечисловой сдвиг не двигает окно")

    // Щипок сильнее пола не ужимает.
    let tiny = w.zoomed(by: 10_000, around: 0.5, cells: cells)
    check(tiny.span >= ChartWindow.minSpan(cells: cells) - 1e-12, "щипок не пробивает пол окна")
}

// MARK: Щётка

do {
    let cells = 8761                                   // год по часу
    // Окно «неделя» на годовой истории — это около 2 % полосы.
    let w = ChartWindow(w0: 0.97, w1: 0.99, cells: cells)

    for width in [342.0, 502.0] {
        let l = BrushLayout(window: w, width: width)
        check(l.hi - l.lo >= BrushLayout.minThumb - 1e-9,
              "бегунок не уже пола при ширине \(width)", "\(l.hi - l.lo)")
        check(l.widened, "раздутый бегунок помечен как врущий")

        // Обе ручки и середина достижимы.
        check(l.hit(l.lo) == .left, "левая ручка ловится (\(width))")
        check(l.hit(l.hi) == .right, "правая ручка ловится (\(width))")
        check(l.hasPan, "у бегунка есть середина (\(width))")
        check(l.hit((l.lo + l.hi) / 2) == .pan, "середина тащит окно (\(width))")

        // Зоны смыкаются ровно на краях капсул, дыр нет.
        check(l.hit(l.lo + BrushLayout.inwardGrab - 0.5) == .left,
              "зона левой ручки кончается на краю капсулы (\(width))")
        check(l.hit(l.lo + BrushLayout.inwardGrab + 0.5) == .pan,
              "сразу за капсулой начинается середина (\(width))")
        check(l.hit(l.lo - BrushLayout.grab / 2 + 0.5) == .left,
              "наружу зона ручки шириной в половину цели (\(width))")
        check(l.hit(l.lo - BrushLayout.grab / 2 - 1) == nil,
              "дальше зоны — промах, то есть перенос окна (\(width))")

        // Цель пальца — величина ФИЗИЧЕСКАЯ: одинакова в пунктах на любой полосе.
        let target = (l.lo + BrushLayout.inwardGrab) - (l.lo - BrushLayout.grab / 2)
        check(near(target, BrushLayout.grab / 2 + BrushLayout.inwardGrab, 1e-9),
              "цель ручки одинакова в пунктах (\(width))", "\(target)")
    }

    // Вся ВИДИМАЯ капсула хватается, даже когда бегунок прижат к краю полосы.
    // Прежде зажим капсулы жил в рисовании, и внутренняя половина ручки была
    // мёртвой: на окне «Всё» ручка нарисована в [0…14], а ловилась до 7.
    for window in [ChartWindow.full,
                   ChartWindow(w0: 0, w1: 0.02, cells: cells),
                   ChartWindow(w0: 0.98, w1: 1, cells: cells)] {
        let l = BrushLayout(window: window, width: 342)
        let half = BrushLayout.handle / 2
        for dx in stride(from: -half + 0.5, through: half - 0.5, by: 1) {
            check(l.hit(l.capLo + dx) == .left,
                  "вся левая капсула ловится (окно \(window.w0)…\(window.w1), смещение \(dx))")
            check(l.hit(l.capHi + dx) == .right,
                  "вся правая капсула ловится (окно \(window.w0)…\(window.w1), смещение \(dx))")
        }
        // Капсула целиком внутри полосы — за краем рисовать нечего.
        check(l.capLo >= half - 1e-9 && l.capHi <= 342 - half + 1e-9,
              "капсулы не выезжают за полосу")
        // Середина, если она есть, по-прежнему тащит окно.
        if l.hasPan {
            check(l.hit((l.capLo + l.capHi) / 2) == .pan, "середина между капсулами тащит окно")
        }
    }

    // Нулевая и нечисловая ширина не роняют арифметику.
    let zero = BrushLayout(window: w, width: 0)
    check(zero.width >= 1, "нулевая ширина полосы чинится")
    let nanW = BrushLayout(window: w, width: .nan)
    check(nanW.width >= 1, "нечисловая ширина полосы чинится")

    // Захват помнит смещение: край едет за пальцем без прыжка.
    let width = 342.0
    let l = BrushLayout(window: w, width: width)
    let grabX = (l.lo - 10) / width                    // палец в 10 pt снаружи от ручки
    let begun = ChartWindow.begin(at: grabX, in: w, cells: cells, width: width)
    if case .left(let offset) = begun.grab {
        check(near(offset, grabX - w.w0, 1e-12), "захват левого края помнит смещение")
        let moved = w.dragging(begun.grab, to: grabX - 0.1, cells: cells)
        check(near(moved.w0, w.w0 - 0.1, 1e-9), "край едет ровно за пальцем",
              "\(moved.w0) против \(w.w0 - 0.1)")
        check(near(moved.w1, w.w1, 1e-12), "неподвижный край не шевелится")
    } else {
        check(false, "захват за 10 pt снаружи — это левая ручка", "\(begun.grab)")
    }

    // Тап МИМО бегунка переносит окно центром под палец.
    let far = ChartWindow.begin(at: 0.2, in: w, cells: cells, width: width)
    check(near((far.window.w0 + far.window.w1) / 2, 0.2, 1e-9),
          "тап мимо бегунка переносит окно под палец")
    check(near(far.window.span, w.span, 1e-9), "перенос не меняет ширину окна")
    if case .pan = far.grab {} else { check(false, "после переноса палец держит середину") }

    // Пол ширины при перетаскивании края: движется ТОЛЬКО схваченный край.
    let floor = ChartWindow.minSpan(cells: cells)
    let squeezed = w.dragging(.left(offset: 0), to: w.w1 + 0.5, cells: cells)
    check(near(squeezed.w1, w.w1, 1e-9), "правый край не уезжает от левого")
    check(squeezed.span >= floor - 1e-12, "ширина не проваливается ниже пола")
}

// MARK: Пресеты — круг «пресет → окно → пресет»

do {
    let start = Date(timeIntervalSinceReferenceDate: 0)
    let histories: [(String, Double, Bool)] = [
        ("3 дня", 3, true), ("ровно 7 дней", 7, true), ("ровно 30 дней", 30, true),
        ("90 дней", 90, true), ("год", 365, true), ("год без прогноза", 365, false),
        ("сутки", 1, true),
    ]
    for (name, days, forecast) in histories {
        let t = WeightTimeline(start: start, dataEnd: start.addingTimeInterval(days * day),
                               forecast: forecast)
        // Показываются только пресеты, которые на этой истории означают разное.
        check(t.availablePeriods.contains(.all), "«Всё» есть всегда («\(name)»)")
        for p in t.availablePeriods {
            let w = t.window(for: p)
            check(t.period(of: w) == p, "круг пресета \(p.title) замкнут на истории «\(name)»",
                  "вернулось \(String(describing: t.period(of: w)))")
        }
        for p in WeightPeriod.allCases where !t.availablePeriods.contains(p) {
            check((p.days ?? 0) >= days - 0.5,
                  "спрятан только пресет длиннее истории («\(name)»: \(p.title))")
        }
        // Своё окно (щипок) НЕ должно совпасть ни с одним пресетом. На совсем
        // короткой истории увеличивать нечего — любое окно там равно полному,
        // и «Всё» подсвечено правильно.
        if ChartWindow.minSpan(cells: t.cells) < 1 {
            let odd = ChartWindow(w0: 0.13, w1: 0.61, cells: t.cells)
            if t.period(of: odd) != nil {
                check(false, "произвольное окно не подсвечивает сегмент на истории «\(name)»")
            }
        }
        // Пресет всегда прижат к правому краю ДАННЫХ.
        let w30 = t.window(for: .d30)
        let right = t.date(at: w30.w1)
        check(right >= t.dataEnd.addingTimeInterval(-hour) && right <= t.end.addingTimeInterval(hour),
              "пресет прижат к правому краю данных («\(name)»)")
    }

    // Хвост прогноза — свойство данных: не больше 14 суток и не больше 30 % истории.
    check(near(WeightTimeline.tailDays(historyDays: 10), 3), "хвост — 30 % короткой истории")
    check(near(WeightTimeline.tailDays(historyDays: 1000), 14), "хвост упирается в 14 суток")
    check(near(WeightTimeline.tailDays(historyDays: 0), 0), "у пустой истории хвоста нет")

    // Ось времени: доля и дата обратимы.
    let t = WeightTimeline(start: start, dataEnd: start.addingTimeInterval(100 * day))
    for f in [0.0, 0.3, 0.77, 1.0] {
        check(near(t.fraction(of: t.date(at: f)), f, 1e-9), "доля ↔ дата обратимы (\(f))")
    }
}

// MARK: Шкала весов

do {
    let n = WeightAxis.nice(lo: 80.685, hi: 83.565)
    check(n.step == 1, "шаг шкалы круглый", "\(n.step)")
    check(n.lo <= 80.685 && n.hi >= 83.565, "шкала накрывает данные")
    check(near(n.lo.truncatingRemainder(dividingBy: n.step), 0, 1e-9), "низ шкалы кратен шагу")
    let ticks = WeightAxis.ticks(lo: n.lo, hi: n.hi, step: n.step)
    check(ticks.count >= 2 && ticks.count <= 5, "засечек не больше пяти", "\(ticks.count)")
    // Шкала не растягивает кадр вдвое ради круглого шага: размах 16,8 кг
    // (данные 81…90,6 плюс цель 77,5) обязан лечь в 75…95, а не в 70…100.
    let wide = WeightAxis.nice(lo: 75.66, hi: 92.49)
    check(wide.step == 5, "выбран самый тесный круглый шаг", "\(wide.step)")
    check(wide.lo == 75 && wide.hi == 95, "шкала не раздувается",
          "\(wide.lo)…\(wide.hi)")
    check(WeightAxis.ticks(lo: wide.lo, hi: wide.hi, step: wide.step).count == 5,
          "на широком размахе пять засечек")
    // Вырожденный вход не вешает stride.
    check(WeightAxis.ticks(lo: 5, hi: 5, step: 0).count == 1, "нулевой шаг не роняет засечки")
    check(WeightAxis.ticks(lo: 0, hi: 1e9, step: 0.2).count == 1, "абсурдный размах не плодит засечки")
    // Плоская история: размах меньше пола 0,6 всё равно даёт рабочую шкалу.
    let flat = WeightAxis.nice(lo: 81.0, hi: 81.0)
    check(flat.hi > flat.lo, "плоская история не схлопывает шкалу")
}

// MARK: Шкала второго ряда

do {
    // Сетку рисует ВЕС, значит у жира должно быть ровно столько же засечек:
    // иначе оранжевые подписи висят между серыми линиями и читаются как брак.
    let w = WeightAxis.nice(lo: 79.4, hi: 83.1)
    let want = WeightAxis.ticks(lo: w.lo, hi: w.hi, step: w.step).count
    let f = WeightAxis.aligned(lo: 24.2, hi: 28.7, ticks: want)
    let got = WeightAxis.ticks(lo: f.lo, hi: f.hi, step: f.step)
    check(got.count == want, "у жира столько же засечек, сколько у веса",
          "\(got.count) против \(want)")
    check(f.lo <= 24.2 && f.hi >= 28.7, "шкала жира накрывает данные",
          "\(f.lo)…\(f.hi)")
    check(near(f.lo.truncatingRemainder(dividingBy: f.step), 0, 1e-9),
          "низ шкалы жира кратен шагу")

    // Дотягивать приходится и снизу, и сверху: проверяем на нескольких
    // размахах, что число засечек совпадает ВСЕГДА, а не случайно.
    for (lo, hi) in [(10.0, 11.0), (18.5, 33.2), (25.0, 25.0), (0.4, 0.9)] {
        for want in 2...5 {
            let a = WeightAxis.aligned(lo: lo, hi: hi, ticks: want)
            let n = WeightAxis.ticks(lo: a.lo, hi: a.hi, step: a.step).count
            check(n == want, "совмещение держится на размахе \(lo)…\(hi) при \(want) засечках",
                  "получилось \(n)")
            check(a.lo <= lo && a.hi >= hi, "совмещённая шкала накрывает данные \(lo)…\(hi)",
                  "\(a.lo)…\(a.hi)")
        }
    }

    // Вырожденная просьба не роняет и не зацикливает.
    let one = WeightAxis.aligned(lo: 20, hi: 30, ticks: 1)
    check(one.hi > one.lo, "просьба об одной засечке не схлопывает шкалу")
}

print(failures == 0
      ? "✅ ядро графика: \(checks) проверок, все прошли"
      : "\(failures) из \(checks) проверок упали")
exit(failures == 0 ? 0 : 1)

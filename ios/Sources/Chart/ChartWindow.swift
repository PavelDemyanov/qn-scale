import Foundation

/// Окно просмотра графика — В ДОЛЯХ ДОМЕНА 0…1, а не парой «ширина в днях +
/// правый край».
///
/// Порт `ChartWindow` из EUC Logger. Долями — потому что домен меняется сам:
/// пришло взвешивание, и правый край уехал. У пары `(windowDays, endDate)`
/// зажимы живут в жестах, а не в типе, и это уже стоило скачка масштаба
/// посреди протяжки.
struct ChartWindow: Equatable {

    /// Минимальная ширина окна В ЯЧЕЙКАХ. Ячейка — ЧАС (`WeightTimeline.cellsPerDay`),
    /// значит 48 ячеек это двое суток — ровно `WeightSnapshot.gapDays`: окно уже
    /// разрыва не показывает вообще ничего.
    ///
    /// Пол задан в ячейках, а не в долях, намеренно: доля относительна, и на
    /// двухлетней истории «двое суток» превратились бы в неделю, а на
    /// двухнедельной — в три часа. Эта ошибка уже оплачена в EUC Logger.
    static let minCells = 48

    /// Страховка от деления на ноль на сколь угодно подробной сетке.
    static let minSpanFloor: Double = 0.0002

    static func minSpan(cells: Int) -> Double {
        guard cells > 1 else { return 1 }
        return Swift.min(1, Swift.max(Double(minCells) / Double(cells - 1), minSpanFloor))
    }

    let w0: Double
    let w1: Double

    static let full = ChartWindow(raw0: 0, raw1: 1)
    private init(raw0: Double, raw1: Double) { w0 = raw0; w1 = raw1 }

    /// Чинит вход МОЛЧА: перевёрнутые края меняет местами, зажимает в 0…1,
    /// слишком узкое окно расширяет ОТ ЦЕНТРА и вдвигает в границы. Это не
    /// ошибка вызывающего, а обычное движение пальца (край протащили мимо
    /// соседнего), и падать тут нечестно. Расширение именно от центра — чтобы
    /// окно не прыгало к краю истории из-под пальца.
    ///
    /// `cells` — параметр ОБЯЗАТЕЛЬНЫЙ, без значения по умолчанию: забытая
    /// сетка означала бы окно с неизвестным полом.
    init(w0: Double, w1: Double, cells: Int) {
        var a = w0.isFinite ? w0 : 0
        var b = w1.isFinite ? w1 : 1
        if a > b { swap(&a, &b) }
        a = Swift.min(Swift.max(a, 0), 1)
        b = Swift.min(Swift.max(b, 0), 1)
        let floor = Self.minSpan(cells: cells)
        if b - a < floor {
            let c = (a + b) / 2
            a = c - floor / 2
            b = c + floor / 2
            if a < 0 { b -= a; a = 0 }
            if b > 1 { a -= (b - 1); b = 1 }
            a = Swift.max(a, 0)
            b = Swift.min(b, 1)
        }
        self.w0 = a
        self.w1 = b
    }

    var span: Double { w1 - w0 }
    var isFull: Bool { w0 <= 0.0001 && w1 >= 0.9999 }

    // MARK: Жесты по графику — чистые O(1)-функции ОТ БАЗЫ ЖЕСТА

    /// `scale` — соглашение `UIPinchGestureRecognizer`: во сколько раз картинка
    /// стала КРУПНЕЕ. Звать надо от окна НА НАЧАЛО ЖЕСТА: распознаватель шлёт
    /// масштаб, НАКОПЛЕННЫЙ от начала, и покадровое применение к текущему окну
    /// возвело бы его в степень числа кадров.
    func zoomed(by scale: Double, around anchor: Double, cells: Int) -> ChartWindow {
        guard scale.isFinite, scale > 0 else { return self }
        let a0 = anchor.isFinite ? Swift.min(Swift.max(anchor, 0), 1) : 0.5
        let floor = Self.minSpan(cells: cells)
        // `min` снаружи гасит и бесконечность от исчезающе малого масштаба.
        let s = Swift.min(1, Swift.max(floor, span / scale))
        // Глобальная доля точки под пальцами обязана лечь ровно на свою же
        // локальную долю в новом окне — в этом весь смысл якоря.
        let g = w0 + a0 * span
        var a = g - a0 * s
        var b = a + s
        if a < 0 { a = 0; b = s }        // у края окно ЕДЕТ, а не ужимается
        if b > 1 { b = 1; a = 1 - s }
        return ChartWindow(w0: a, w1: b, cells: cells)
    }

    /// Сдвиг в долях СВОЕЙ ширины: палец прошёл треть графика — история под ним
    /// уехала на треть экрана, и неважно, неделя в окне или год.
    func panned(byWindowFraction dx: Double, cells: Int) -> ChartWindow {
        guard dx.isFinite, dx != 0 else { return self }
        let s = span
        var a = w0 + dx * s
        var b = a + s
        if a < 0 { a = 0; b = s }
        if b > 1 { b = 1; a = 1 - s }
        return ChartWindow(w0: a, w1: b, cells: cells)
    }

    // MARK: Щётка

    enum Grab: Equatable {
        /// `offset` — насколько правее левого края окна стоит палец. Смещение
        /// обязательно и у краёв: зона захвата 44 pt, палец берётся за край в
        /// двух десятках пунктов от него, и без запомненного смещения край
        /// прыгнул бы под палец в момент захвата.
        case left(offset: Double)
        case right(offset: Double)
        /// `span` — ширина НА МОМЕНТ ЗАХВАТА: пересчитывать по ходу нельзя,
        /// иначе у краёв истории окно «дышит» — упирается, ужимается и не
        /// возвращает прежнюю ширину при движении назад.
        case pan(offset: Double, span: Double)
    }

    /// `width` — ширина полосы щётки В ПУНКТАХ, параметр обязательный: цель
    /// пальца — величина физическая. Попадание считает ТА ЖЕ `BrushLayout`,
    /// которой щётка рисуется; два независимых расчёта развели бы «где ручка»
    /// и «куда попадаешь».
    static func begin(at f: Double, in window: ChartWindow, cells: Int,
                      width: Double) -> (window: ChartWindow, grab: Grab) {
        let x = Swift.min(Swift.max(f, 0), 1)
        let layout = BrushLayout(window: window, width: width)
        switch layout.hit(x * layout.width) {
        case .left:  return (window, .left(offset: x - window.w0))
        case .right: return (window, .right(offset: x - window.w1))
        case .pan:   return (window, .pan(offset: x - window.w0, span: window.span))
        case nil:
            // Тап МИМО бегунка — не «ничего не делать»: окно переносится
            // центром под палец и возвращается уже перенесённым, чтобы жест
            // продолжился без рывка. На длинной истории недельное окно занимает
            // пару миллиметров полосы, попасть в него пальцем нельзя.
            let s = window.span
            var a = x - s / 2
            var b = x + s / 2
            if a < 0 { b -= a; a = 0 }
            if b > 1 { a -= (b - 1); b = 1 }
            return (ChartWindow(w0: a, w1: b, cells: cells), .pan(offset: s / 2, span: s))
        }
    }

    func dragging(_ grab: Grab, to f: Double, cells: Int) -> ChartWindow {
        let x = Swift.min(Swift.max(f, 0), 1)
        let floor = Self.minSpan(cells: cells)
        switch grab {
        case .left(let o):
            // Пол применяем ЯВНЫМ зажимом движимого края: расширение от центра
            // в `init` увело бы и неподвижный край тоже.
            return ChartWindow(w0: Swift.min(w1 - floor, x - o), w1: w1, cells: cells)
        case .right(let o):
            return ChartWindow(w0: w0, w1: Swift.max(w0 + floor, x - o), cells: cells)
        case .pan(let o, let s):
            var a = x - o
            var b = a + s
            if a < 0 { a = 0; b = s }
            if b > 1 { b = 1; a = 1 - s }
            return ChartWindow(w0: a, w1: b, cells: cells)
        }
    }
}

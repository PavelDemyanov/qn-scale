import SwiftUI
import Observation

/// Окно, метка и сводка графика.
///
/// `@Observable` следит ПОСВОЙСТВЕННО, и в этом весь фокус: карточка графика
/// читает `window` и перестраивается кадр в кадр, а `HistoryView` читает только
/// `digest` — и на кадрах жеста не перестраивается вовсе. Прежде правый край
/// окна был `@State` всего экрана, тело которого — список с восемнадцатью
/// строками.
@MainActor @Observable
final class WeightChartModel {
    private(set) var snapshot = WeightSnapshot.empty
    private(set) var window = ChartWindow.full        // ЖИВОЕ
    private(set) var digest = WindowDigest.empty      // ОСЕВШЕЕ
    private(set) var markedDate: Date?
    private(set) var markerHeld = false
    private(set) var gesturing = false
    private(set) var resetToken = 0

    var brushGrab: ChartWindow.Grab?
    private var version = 0

    /// `kind` нужен, чтобы конец ОДНОГО жеста не убирал базу ДРУГОГО: панорама
    /// заканчивается вторым пальцем ровно тогда, когда начинается щипок, и
    /// порядок этих событий не гарантирован.
    private struct Base {
        enum Kind { case pan, zoom }
        let kind: Kind
        let window: ChartWindow
        let anchor: Double
    }
    private var base: Base?

    var timeline: WeightTimeline { snapshot.timeline }
    var period: WeightPeriod? { timeline.period(of: window) }
    var visibleDays: Int { Int(timeline.dataDays(window).rounded()) }
    var windowLabel: String {
        "\(Fmt.shortDayMonth(timeline.date(at: window.w0))) – \(Fmt.shortDayMonth(timeline.date(at: window.w1)))"
    }

    /// Цель нужна только для решения «втягивать ли её в шкалу», и решение
    /// принимается по ЗАФИКСИРОВАННОМУ окну: порог переключался прямо при
    /// панорамировании и дёргал масштаб на ровном месте.
    var digestGoal: Double = 78 {
        didSet { if digestGoal != oldValue { commit(force: true) } }
    }

    /// Прогноз входит в размах кадра, значит и в решение о цели.
    var digestForecast = true {
        didSet { if digestForecast != oldValue { commit(force: true) } }
    }

    // MARK: Данные

    func reload(items: [WeighIn], settings: AppSettings) {
        let hadData = !snapshot.isEmpty
        let keptPeriod = hadData ? period : nil
        let keptDates = hadData ? (timeline.date(at: window.w0), timeline.date(at: window.w1)) : nil
        version &+= 1
        snapshot = WeightSnapshot.build(items: items, profile: settings.profile,
                                        goal: settings.goalWeight,
                                        showForecast: settings.showForecast,
                                        version: version)
        // Домен растёт при каждом взвешивании, значит те же доли означают уже
        // другой отрезок времени. Правило: пресет держим пресетом, своё окно —
        // по АБСОЛЮТНЫМ датам.
        if let p = keptPeriod {
            window = timeline.window(for: p)
        } else if let d = keptDates, !snapshot.isEmpty {
            window = ChartWindow(w0: timeline.fraction(of: d.0),
                                 w1: timeline.fraction(of: d.1), cells: timeline.cells)
        } else {
            window = timeline.window(for: .d30)
        }
        commit(force: true)
    }

    /// Переключатель → окно.
    func apply(_ p: WeightPeriod) {
        set(timeline.window(for: p))
        commit()
    }

    // MARK: Жесты по графику

    func handle(_ e: ChartGestureEvent, plot: WeightPlot) {
        switch e {
        case .tapped:
            if markedDate != nil { markedDate = nil }
        case .markerBegan(let x), .markerMoved(let x):
            if !markerHeld { markerHeld = true }
            // Метка ЛИПНЕТ к измерению и только в пределах 44 pt.
            if let hit = plot.nearest(toX: x), hit.date != markedDate { markedDate = hit.date }
        case .markerEnded:
            if markerHeld { markerHeld = false }   // линия ОСТАЁТСЯ: это замер
        case .panBegan:
            base = Base(kind: .pan, window: window, anchor: 0)
            if !gesturing { gesturing = true }
        case .panChanged(let dx):
            guard let b = base, b.kind == .pan else { return }
            // Знак обратный: палец вправо тянет ленту вправо, окно едет в прошлое.
            // Считаем ОТ БАЗЫ: распознаватель шлёт НАКОПЛЕННЫЙ сдвиг.
            set(b.window.panned(byWindowFraction: -dx, cells: timeline.cells))
        case .zoomBegan(let a):
            base = Base(kind: .zoom, window: window, anchor: a)
            if !gesturing { gesturing = true }
        case .zoomChanged(let s):
            guard let b = base, b.kind == .zoom else { return }
            set(b.window.zoomed(by: s, around: b.anchor, cells: timeline.cells))
        case .glide(let dx):
            // Инерция идёт ОТ ТЕКУЩЕГО окна, а не от базы: база — положение на
            // момент, когда палец лёг, и отсчитывать от неё затухающие кадры
            // значит складывать одно движение дважды.
            set(window.panned(byWindowFraction: -dx, cells: timeline.cells))
        case .panEnded:
            if base?.kind == .pan || base == nil { endGesture() }
        case .zoomEnded:
            if base?.kind == .zoom { endGesture() }
        }
    }

    private func endGesture() {
        if gesturing { gesturing = false }
        base = nil
        commit()
    }

    /// Все записи идемпотентны: SwiftUI равенство сам не проверяет, а
    /// безусловная запись перерисовывает экран на каждом кадре жеста.
    private func set(_ next: ChartWindow) { if next != window { window = next } }

    // MARK: Щётка

    func beginBrush(at f: Double, width: Double) {
        let begun = ChartWindow.begin(at: f, in: window, cells: timeline.cells, width: width)
        set(begun.window)
        brushGrab = begun.grab
    }

    func dragBrush(to f: Double) {
        guard let g = brushGrab else { return }
        set(window.dragging(g, to: f, cells: timeline.cells))
    }

    func endBrush() {
        guard brushGrab != nil else { return }
        brushGrab = nil
        commit()
    }

    // MARK: Фиксация

    /// Пересчёт сводки и списка — ТОЛЬКО по окончании (и по отмене) жеста.
    /// Ключ — само окно, поэтому звать можно из нескольких мест без опаски:
    /// повторный пересчёт на то же окно бесплатен.
    func commit(force: Bool = false) {
        guard force || (digest.window != window && !gesturing) else { return }
        var d = WindowDigest()
        d.window = window
        let s = snapshot.range(window)
        d.count = s.count
        let ws = s.map(\.kg)
        d.lo = ws.min()
        d.hi = ws.max()
        if let f = s.first, let l = s.last, s.count > 1 { d.change = l.kg - f.kg }
        d.rows = Array(s.reversed().prefix(18))
        d.pullGoal = WeightPlot.goalFits(snapshot, window: window, goal: digestGoal,
                                         showForecast: digestForecast)
        digest = d
    }

    /// Аварийный выход: уход в фон посреди жеста — UIKit может не прислать
    /// терминальное состояние вовсе, и флаги залипнут.
    func abortGestures() {
        resetToken &+= 1
        if markerHeld { markerHeld = false }
        brushGrab = nil
        if gesturing { gesturing = false }
        base = nil
        commit()
    }
}

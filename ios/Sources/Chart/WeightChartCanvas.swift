import SwiftUI

/// Полотно графика. Ничего не считает: всё приезжает готовым в `plot`.
/// Порядок слоёв — прежний, до отрезка.
struct WeightChartCanvas: View, Equatable {
    let plot: WeightPlot
    let palette: Palette
    let markerX: CGFloat?
    let markerPoint: CGPoint?
    /// Та же метка на кривой жира — иначе непонятно, к какой её точке относится
    /// процент в шапке.
    var markerFatPoint: CGPoint?
    let markerHeld: Bool
    let showGoalLine: Bool
    let showForecast: Bool
    let showAxis: Bool
    /// Плашки с изменением веса у каждой засечки. Включаются точечно: на
    /// спарклайне размером в две строки им негде поместиться.
    var showDeltas = false
    var lineWidth: CGFloat = 2.3

    /// Сравнение по ШТАМПУ: движение тултипа полотно не трогает.
    static func == (a: Self, b: Self) -> Bool {
        a.plot.stamp == b.plot.stamp && a.palette == b.palette
            && a.markerX == b.markerX && a.markerPoint == b.markerPoint
            && a.markerFatPoint == b.markerFatPoint
            && a.markerHeld == b.markerHeld && a.lineWidth == b.lineWidth
            && a.showDeltas == b.showDeltas
            && a.showAxis == b.showAxis && a.showGoalLine == b.showGoalLine
            && a.showForecast == b.showForecast
    }

    var body: some View {
        Canvas { ctx, size in
            guard plot.plot.width > 1, plot.hi > plot.lo else { return }
            let ticks = WeightAxis.ticks(lo: plot.lo, hi: plot.hi, step: plot.step)

            // Засечки идут первыми — иначе серые волоски ложатся поверх кривой.
            if showAxis {
                for v in ticks {
                    let y = plot.y(v)
                    var g = Path()
                    // От начала ПОЛОСЫ ЛИНИИ, а не от края кадра: слева стоит
                    // колонка подписей жира, и волоски шли сквозь цифры.
                    g.move(to: CGPoint(x: plot.plot.minX, y: y))
                    g.addLine(to: CGPoint(x: plot.plot.maxX, y: y))
                    ctx.stroke(g, with: .color(palette.sep), lineWidth: 0.5)
                }
                // Подписи рисуются ЗДЕСЬ, а не отдельными Text: иначе на каждом
                // кадре протяжки идёт форматирование и перелэйаут восьми вьюх.
                for v in ticks {
                    let t = ctx.resolve(Text(Fmt.n(v, 1))
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(palette.fg3))
                    ctx.draw(t, at: CGPoint(x: size.width - 2, y: plot.y(v)), anchor: .trailing)
                }
                if showGoalLine, plot.goalInRange {
                    let t = ctx.resolve(Text(Fmt.n(plot.stamp.goal, 1))
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(palette.green))
                    ctx.draw(t, at: CGPoint(x: size.width - 2, y: plot.goalY), anchor: .trailing)
                }
                // Шкала жира — СЛЕВА и оранжевым, чтобы её не спутать с
                // килограммами справа. Своих засечек она не рисует: вторая
                // сетка поверх первой превращает кадр в клетку.
                if plot.hasFat {
                    for v in WeightAxis.ticks(lo: plot.fatLo, hi: plot.fatHi, step: plot.fatStep) {
                        let t = ctx.resolve(Text(Fmt.n(v, 1))
                            .font(.system(size: 10.5).monospacedDigit())
                            .foregroundStyle(palette.orange.opacity(0.85)))
                        ctx.draw(t, at: CGPoint(x: 2, y: plot.fatY(v)), anchor: .leading)
                    }
                }
                for i in 0..<3 {
                    let d = plot.t0.addingTimeInterval(plot.t1.timeIntervalSince(plot.t0) * Double(i) / 2)
                    let t = ctx.resolve(Text(Fmt.shortDayMonth(d))
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.fg3))
                    // Отсчёт от НАЧАЛА полосы линии: с включённым жиром слева
                    // стоит своя колонка подписей, и прежний абсолютный порог
                    // 27 клал первую дату прямо на проценты.
                    let lead = plot.plot.minX + 25
                    let x = Swift.min(Swift.max(plot.x(d), lead), Swift.max(lead, plot.plot.maxX - 7))
                    ctx.draw(t, at: CGPoint(x: x, y: size.height - 8), anchor: .center)
                }
            }

            // ОТСЕЧКА по полосе линии. Кривая берётся ШИРЕ окна ради плавности,
            // и без отсечки крайние точки заезжают на колонку подписей, а при
            // пустом окне прямая между закадровыми соседями уходит на сотни
            // пунктов за пределы карточки.
            var c = ctx
            c.clip(to: Path(CGRect(x: plot.plot.minX, y: 0,
                                   width: plot.plot.width, height: size.height)))

            // Заливка под данными — синяя, под интерполяцией — серая, той же
            // формы и с тем же затуханием: цвет фона обязан говорить о том же,
            // о чём говорит цвет линии.
            let top = CGPoint(x: 0, y: plot.areaTop * size.height)
            let bottom = CGPoint(x: 0, y: plot.areaBottom * size.height)
            c.fill(plot.areaGap, with: .linearGradient(
                Gradient(colors: [palette.fg3.opacity(0.22), palette.fg3.opacity(0)]),
                startPoint: top, endPoint: bottom))
            c.fill(plot.areaSolid, with: .linearGradient(
                Gradient(colors: [palette.blue.opacity(0.3), palette.blue.opacity(0)]),
                startPoint: top, endPoint: bottom))

            if showGoalLine, plot.goalInRange {
                var g = Path()
                g.move(to: CGPoint(x: 0, y: plot.goalY))
                g.addLine(to: CGPoint(x: plot.plot.maxX, y: plot.goalY))
                c.stroke(g, with: .color(palette.green),
                         style: StrokeStyle(lineWidth: 1.3, dash: [5, 4]))
            }
            if showForecast {
                c.stroke(plot.forecast, with: .color(palette.fg3),
                         style: StrokeStyle(lineWidth: 1.9, lineCap: .round, dash: [3, 4]))
            }
            // Жир — ПОД весом: вес главный, и перекрывать его вторым рядом
            // нельзя. Заливки у жира нет намеренно — две заливки на одном
            // кадре мешают читать обе.
            if plot.hasFat {
                c.stroke(plot.fatLine, with: .color(palette.orange),
                         style: StrokeStyle(lineWidth: lineWidth * 0.8, lineCap: .round, lineJoin: .round))
            }
            // Интерполяция — серым и тоньше: на этом отрезке взвешиваний не
            // было, и выдавать домысел за данные нельзя.
            c.stroke(plot.gap, with: .color(palette.fg3),
                     style: StrokeStyle(lineWidth: lineWidth * 0.8, lineCap: .round, lineJoin: .round))
            c.stroke(plot.solid, with: .color(palette.blue),
                     style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            c.fill(plot.dots, with: .color(palette.blue))

            // Плашки с изменением: набрал — красная «+», сбросил — зелёная «−».
            // Тот же язык цвета, что у столбиков недели.
            //
            // Рисуются НЕ у каждой засечки: на месяце их два десятка, и подписи
            // легли бы одна на другую. Порядок — по ВЕЛИЧИНЕ изменения: место
            // достаётся сначала заметным скачкам, а мелочь занимает остатки.
            // Проверять надо против ВСЕХ уже поставленных, а не против одной
            // предыдущей: набор рисуется над точкой, сброс под ней, и соседи
            // через одного ложились друг на друга.
            if showDeltas {
                let font = Font.system(size: 10, weight: .semibold).monospacedDigit()
                // Коробка меряется ОДИН раз по образцу, а не под каждую
                // подпись: цифры моноширинные, ширина у всех одинаковая, а
                // раскладка текста стоит дороже остальной отрисовки — и шла
                // она даже для тех засечек, что потом отбрасывались.
                let gauge = c.resolve(Text(L("%@ kg", Fmt.signed(-8.88))).font(font))
                let gs = gauge.measure(in: CGSize(width: 200, height: 40))
                let w = gs.width + 12, h = gs.height + 5
                // Поле от края полотна: без него прижатая плашка упиралась в
                // самый край экрана, тогда как у всего остального поле 16.
                let edge: CGFloat = 6
                var drawn: [CGRect] = []
                for sm in plot.samples.sorted(by: { abs($0.delta ?? 0) > abs($1.delta ?? 0) }) {
                    // Нулевое изменение не подписываем: «+0,00» — это шум,
                    // а сама засечка на месте и так видна.
                    guard let d = sm.delta, abs(d) >= 0.005 else { continue }
                    let up = d > 0
                    // Набор — над точкой, сброс — под ней: направление плашки
                    // повторяет направление веса, как у столбиков недели.
                    var y = up ? sm.point.y - 11 - h / 2 : sm.point.y + 11 + h / 2
                    y = Swift.min(Swift.max(y, plot.padding.top + h / 2),
                                  size.height - plot.padding.bottom - h / 2)
                    let x = Swift.min(Swift.max(sm.point.x, plot.plot.minX + edge + w / 2),
                                      plot.plot.maxX - edge - w / 2)
                    let rect = CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h)
                    if drawn.contains(where: { $0.insetBy(dx: -3, dy: -3).intersects(rect) }) { continue }
                    drawn.append(rect)
                    c.fill(Path(roundedRect: rect, cornerRadius: h / 2),
                           with: .color(up ? palette.red : palette.green))
                    // Текст ТЁМНЫЙ: белый на светло-зелёном давал контраст
                    // около двух к одному — на десяти пунктах это не читается.
                    c.draw(c.resolve(Text(L("%@ kg", Fmt.signed(d)))
                                        .font(font)
                                        .foregroundStyle(Color.black)),
                           at: CGPoint(x: x, y: y), anchor: .center)
                }
            }

            if let mx = markerX {
                var v = Path()
                v.move(to: CGPoint(x: mx, y: 8))
                v.addLine(to: CGPoint(x: mx, y: Swift.max(8, size.height - 28)))
                c.stroke(v, with: .color(palette.fg3), lineWidth: 1)
            }
            if let fp = markerFatPoint {
                let r: CGFloat = markerHeld ? 5.5 : 4
                let box = CGRect(x: fp.x - r, y: fp.y - r, width: r * 2, height: r * 2)
                c.fill(Path(ellipseIn: box), with: .color(palette.orange))
                c.stroke(Path(ellipseIn: box), with: .color(palette.card), lineWidth: 2)
            }
            if let mp = markerPoint {
                let r: CGFloat = markerHeld ? 7 : 5
                let box = CGRect(x: mp.x - r, y: mp.y - r, width: r * 2, height: r * 2)
                c.fill(Path(ellipseIn: box), with: .color(palette.blue))
                c.stroke(Path(ellipseIn: box), with: .color(palette.card), lineWidth: 2.5)
            }
        }
    }
}

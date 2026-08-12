import SwiftUI

/// Полотно графика. Ничего не считает: всё приезжает готовым в `plot`.
/// Порядок слоёв — прежний, до отрезка.
struct WeightChartCanvas: View, Equatable {
    let plot: WeightPlot
    let palette: Palette
    let markerX: CGFloat?
    let markerPoint: CGPoint?
    let markerHeld: Bool
    let showGoalLine: Bool
    let showForecast: Bool
    let showAxis: Bool
    var lineWidth: CGFloat = 2.3

    /// Сравнение по ШТАМПУ: движение тултипа полотно не трогает.
    static func == (a: Self, b: Self) -> Bool {
        a.plot.stamp == b.plot.stamp && a.palette == b.palette
            && a.markerX == b.markerX && a.markerPoint == b.markerPoint
            && a.markerHeld == b.markerHeld && a.lineWidth == b.lineWidth
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
                    g.move(to: CGPoint(x: 0, y: y))
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
                for i in 0..<3 {
                    let d = plot.t0.addingTimeInterval(plot.t1.timeIntervalSince(plot.t0) * Double(i) / 2)
                    let t = ctx.resolve(Text(Fmt.shortDayMonth(d))
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.fg3))
                    let x = Swift.min(Swift.max(plot.x(d), 27), Swift.max(27, plot.plot.maxX - 7))
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
            // Интерполяция — серым и тоньше: на этом отрезке взвешиваний не
            // было, и выдавать домысел за данные нельзя.
            c.stroke(plot.gap, with: .color(palette.fg3),
                     style: StrokeStyle(lineWidth: lineWidth * 0.8, lineCap: .round, lineJoin: .round))
            c.stroke(plot.solid, with: .color(palette.blue),
                     style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            c.fill(plot.dots, with: .color(palette.blue))

            if let mx = markerX {
                var v = Path()
                v.move(to: CGPoint(x: mx, y: 8))
                v.addLine(to: CGPoint(x: mx, y: Swift.max(8, size.height - 28)))
                c.stroke(v, with: .color(palette.fg3), lineWidth: 1)
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

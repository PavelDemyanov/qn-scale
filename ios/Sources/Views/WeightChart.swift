import SwiftUI

/// Кривая веса целиком: заливка, линия, прогноз, линия цели, точки и, если
/// нужно, точка «вы здесь» на конце.
///
/// Геометрия строится ОДИН раз и здесь же отдаётся точке конца: раньше главный
/// экран собирал её отдельно ради одного `lastPoint`, с параметрами,
/// продублированными вручную в двух местах.
struct WeightChart: View {
    @Environment(\.palette) private var palette

    let snapshot: WeightSnapshot
    let window: ChartWindow
    let goal: Double
    let size: CGSize
    let padding: WeightPlot.Padding

    var pullGoal = true
    var showGoalLine = true
    var showForecast = true
    var showDots = false
    var showAxis = false
    /// Плашки «+0,45 / −0,30» у засечек — только там, где под них есть место.
    var showDeltas = false
    var endDotRing: Color?
    var lineWidth: CGFloat = 2.3

    var body: some View {
        let plot = WeightPlot.build(snapshot, window: window, goal: goal,
                                    pullGoal: pullGoal, showGoalLine: showGoalLine,
                                    showForecast: showForecast, showDots: showDots,
                                    size: size, padding: padding, niceScale: showAxis,
                                    showDeltas: showDeltas)
        ZStack(alignment: .topLeading) {
            WeightChartCanvas(plot: plot, palette: palette,
                              markerX: nil, markerPoint: nil, markerHeld: false,
                              showGoalLine: showGoalLine, showForecast: showForecast,
                              showAxis: showAxis, showDeltas: showDeltas, lineWidth: lineWidth)
                .equatable()
            if let ring = endDotRing, let end = plot.lastPoint {
                ChartEndDot(point: end, ringColor: ring)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

/// Точка «вы здесь» на конце кривой — для спарклайна на главном экране.
struct ChartEndDot: View {
    @Environment(\.palette) private var palette
    let point: CGPoint
    var ringColor: Color

    var body: some View {
        Circle()
            .fill(palette.blue)
            .overlay(Circle().stroke(ringColor, lineWidth: 2))
            .frame(width: 7.2, height: 7.2)
            .position(point)
    }
}

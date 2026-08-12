import SwiftUI

/// Одна фигура графика. Всё рисуется из одних и тех же параметров окна,
/// а `animatableData` — это само окно: при смене периода SwiftUI плавно
/// интерполирует его, и кривая, заливка, точки и пунктир едут вместе.
struct WeightCurve: Shape {
    enum Kind { case line, area, forecast, dots, goalLine }

    let items: [WeighIn]
    let goal: Double
    let slope: Double?
    let padding: ChartGeometry.Padding
    let forecastFraction: Double
    let includeGoal: Bool
    let kind: Kind
    var windowDays: Double
    var endTime: TimeInterval

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(windowDays, endTime) }
        set { windowDays = newValue.first; endTime = newValue.second }
    }

    func geometry(in size: CGSize) -> ChartGeometry {
        ChartGeometry.build(items: items, goal: goal,
                            windowDays: max(1, windowDays),
                            endDate: Date(timeIntervalSinceReferenceDate: endTime),
                            size: size, padding: padding,
                            forecastDays: max(1, windowDays) * forecastFraction,
                            slope: slope, includeGoal: includeGoal)
    }

    func path(in rect: CGRect) -> Path {
        let geo = geometry(in: rect.size)
        switch kind {
        case .line:     return geo.line
        case .area:     return geo.area
        case .forecast: return geo.forecast
        case .dots:
            var p = Path()
            for sample in geo.samples {
                p.addEllipse(in: CGRect(x: sample.point.x - 2.6, y: sample.point.y - 2.6,
                                        width: 5.2, height: 5.2))
            }
            return p
        case .goalLine:
            var p = Path()
            guard geo.goalInRange else { return p }
            p.move(to: CGPoint(x: 0, y: geo.goalY))
            p.addLine(to: CGPoint(x: rect.width - padding.trailing, y: geo.goalY))
            return p
        }
    }
}

/// Кривая веса целиком: заливка, линия, прогноз, линия цели и точки.
struct WeightChart: View {
    @Environment(\.palette) private var palette

    let items: [WeighIn]
    let goal: Double
    let slope: Double?
    let size: CGSize
    let padding: ChartGeometry.Padding
    let windowDays: Double
    let endDate: Date

    var forecastFraction: Double = 0
    var includeGoal = true
    var showGoalLine = true
    var showForecast = true
    var showDots = false
    var lineWidth: CGFloat = 2.3

    private func curve(_ kind: WeightCurve.Kind) -> WeightCurve {
        WeightCurve(items: items, goal: goal, slope: slope, padding: padding,
                    forecastFraction: showForecast ? forecastFraction : 0,
                    includeGoal: includeGoal, kind: kind,
                    windowDays: windowDays,
                    endTime: endDate.timeIntervalSinceReferenceDate)
    }

    /// Границы заливки — чтобы градиент гас у основания кривой, как в макете
    /// (в SVG это objectBoundingBox), а не по всей высоте вью.
    private var areaBounds: (top: CGFloat, bottom: CGFloat) {
        let rect = curve(.area).path(in: CGRect(origin: .zero, size: size)).boundingRect
        guard size.height > 0, !rect.isEmpty else { return (0, 1) }
        return (max(0, rect.minY / size.height), min(1, rect.maxY / size.height))
    }

    var body: some View {
        let bounds = areaBounds
        ZStack(alignment: .topLeading) {
            curve(.area)
                .fill(LinearGradient(
                    colors: [palette.blue.opacity(0.3), palette.blue.opacity(0)],
                    startPoint: UnitPoint(x: 0.5, y: bounds.top),
                    endPoint: UnitPoint(x: 0.5, y: bounds.bottom)))

            if showGoalLine {
                curve(.goalLine)
                    .stroke(palette.green, style: StrokeStyle(lineWidth: 1.3, dash: [5, 4]))
            }

            if showForecast {
                curve(.forecast)
                    .stroke(palette.fg3, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, dash: [3, 4]))
            }

            curve(.line)
                .stroke(palette.blue, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

            if showDots {
                curve(.dots).fill(palette.blue)
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

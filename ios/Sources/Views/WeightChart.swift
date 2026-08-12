import SwiftUI

/// Обёртка, чтобы отдать уже посчитанный путь в Shape.
struct PrebuiltPath: Shape {
    let path: Path
    func path(in rect: CGRect) -> Path { path }
}

/// Кривая веса: заливка, линия, пунктир прогноза, линия цели и точки.
struct WeightChart: View {
    @Environment(\.palette) private var palette

    let geometry: ChartGeometry
    var showGoalLine = true
    var showDots = false
    var lineWidth: CGFloat = 2.3
    var selected: CGPoint? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            PrebuiltPath(path: geometry.area)
                .fill(LinearGradient(colors: [palette.blue.opacity(0.3), palette.blue.opacity(0)],
                                     startPoint: .top, endPoint: .bottom))

            if showGoalLine && geometry.goalInRange {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: geometry.goalY))
                    p.addLine(to: CGPoint(x: geometry.size.width - geometry.padding.trailing, y: geometry.goalY))
                }
                .stroke(palette.green, style: StrokeStyle(lineWidth: 1.3, dash: [5, 4]))
            }

            PrebuiltPath(path: geometry.forecast)
                .stroke(palette.fg3, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, dash: [3, 4]))

            PrebuiltPath(path: geometry.line)
                .stroke(palette.blue, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

            if showDots {
                ForEach(geometry.samples) { sample in
                    Circle()
                        .fill(palette.blue)
                        .frame(width: 5.2, height: 5.2)
                        .position(sample.point)
                }
            }

            if let selected {
                Path { p in
                    p.move(to: CGPoint(x: selected.x, y: geometry.padding.top - 6))
                    p.addLine(to: CGPoint(x: selected.x, y: geometry.size.height - geometry.padding.bottom))
                }
                .stroke(palette.fg3, lineWidth: 1)
                Circle()
                    .fill(palette.blue)
                    .overlay(Circle().stroke(palette.card, lineWidth: 2.5))
                    .frame(width: 10, height: 10)
                    .position(selected)
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
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

import SwiftUI

/// Карточка графика — ЕДИНСТВЕННАЯ вьюха, читающая живое `model.window`.
/// Кадры жеста дальше неё не выходят.
struct HistoryChartCard: View {
    @Environment(\.palette) private var palette
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase

    let model: WeightChartModel

    private let chartHeight: CGFloat = 240
    private let axisWidth: CGFloat = 40
    private var padding: WeightPlot.Padding {
        .init(top: 14, bottom: 28, leading: 2, trailing: axisWidth)
    }

    /// Выбранный период для системного переключателя. `nil` — окно не совпадает
    /// ни с одним пресетом (щипок или щётка), и тогда не подсвечен ни один
    /// сегмент: подсветить наугад значит соврать ровно там, где щётка говорит
    /// правду.
    private var periodBinding: Binding<WeightPeriod?> {
        Binding(get: { model.period },
                set: { if let p = $0 { model.apply(p) } })
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            GeometryReader { proxy in
                // РОВНО ОДНА сборка геометрии на кадр — её видят и полотно, и
                // метка, и жестовый слой.
                let plot = WeightPlot.build(model.snapshot, window: model.window,
                                            goal: settings.goalWeight,
                                            pullGoal: model.digest.pullGoal,
                                            showGoalLine: settings.showGoalLine,
                                            showForecast: settings.showForecast,
                                            showDots: model.visibleDays <= 45,
                                            size: CGSize(width: proxy.size.width,
                                                         height: chartHeight),
                                            padding: padding, niceScale: true)
                let mark = marker(plot)
                ZStack(alignment: .topLeading) {
                    WeightChartCanvas(plot: plot, palette: palette,
                                      markerX: mark?.point.x, markerPoint: mark?.point,
                                      markerHeld: model.markerHeld,
                                      showGoalLine: settings.showGoalLine,
                                      showForecast: settings.showForecast,
                                      showAxis: true)
                        .equatable()

                    if let m = mark {
                        tooltip(m.sample)
                            .offset(x: Swift.min(Swift.max(0, m.point.x - 50),
                                                 Swift.max(0, plot.plot.maxX - 116)), y: 2)
                            .allowsHitTesting(false)
                    }

                    // Жестовому слою передаётся ПОЛОСА ЛИНИИ, а не весь кадр:
                    // иначе доля касания в колонке подписей считается неверно.
                    ChartTouchLayer(plot: plot.plot, resetToken: model.resetToken) {
                        model.handle($0, plot: plot)
                    }
                }
            }
            .frame(height: chartHeight)

            WeightBrush(model: model)
                .padding(.top, 10)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.abortGestures() }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                Text(L("range · %d d", model.visibleDays))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.fg2)
                HStack(alignment: .lastTextBaseline, spacing: 5) {
                    // Перекатывание цифр СНЯТО: оно запускало анимацию на
                    // каждом кадре протяжки.
                    Text(spanLabel)
                        .font(.system(size: 24, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(palette.fg)
                    Text(L("kg"))
                        .font(.system(size: 13))
                        .foregroundStyle(palette.fg2)
                }
            }
            Spacer()
            Text(L("press and hold — marker\npinch — zoom"))
                .font(.system(size: 10))
                .multilineTextAlignment(.trailing)
                .foregroundStyle(palette.fg3)
                .padding(.top, 3)
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 8)
    }

    /// Размах берётся из ОСЕВШЕГО окна: на кадрах жеста цифра не пляшет.
    private var spanLabel: String {
        guard let lo = model.digest.lo, let hi = model.digest.hi else { return "—" }
        return "\(Fmt.n(lo, 1)) – \(Fmt.n(hi, 1))"
    }

    /// Метка хранится ДАТОЙ, поэтому при смене окна остаётся на своей секунде
    /// сама. Уехала за край — не рисуем: это замер, и показывать его над чужим
    /// местом нельзя.
    private func marker(_ plot: WeightPlot) -> (sample: WeightPlot.Sample, point: CGPoint)? {
        // В окне проверяется САМА метка. Проверять найденную засечку —
        // тавтология: она и так выбрана из видимых, поэтому метка не пропадала
        // за краем окна, а перепрыгивала на чужое измерение.
        guard let d = model.markedDate, d >= plot.t0, d <= plot.t1,
              let s = plot.samples.min(by: {
                  abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d))
              }) else { return nil }
        return (s, s.point)
    }

    private func tooltip(_ s: WeightPlot.Sample) -> some View {
        // Дельта берётся ГОТОВОЙ из снимка, а не поиском по всей истории.
        let d = model.snapshot.deltas[s.id]
        return VStack(alignment: .leading, spacing: 1) {
            Text(Fmt.dayLabel(s.date) + ", " + Fmt.time(s.date))
                .font(.system(size: 11))
                .foregroundStyle(palette.fg2)
            Text(L("%@ kg", Fmt.n(s.kg)))
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(palette.fg)
            Text(d.map { L("%@ kg", Fmt.signed($0)) } ?? L("first"))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(d.map { palette.delta($0) } ?? palette.fg3)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(palette.card2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 7, y: 4)
    }
}

import SwiftUI

/// Карточка графика — ЕДИНСТВЕННАЯ вьюха, читающая живое `model.window`.
/// Кадры жеста дальше неё не выходят.
struct HistoryChartCard: View {
    @Environment(\.palette) private var palette
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase

    let model: WeightChartModel
    /// Высота полотна. В портрете фиксированная, в альбоме карточке отдают всё,
    /// что осталось от экрана.
    var chartHeight: CGFloat = 240
    /// Альбомный режим: списка и таббара нет, кнопка разворота меняет смысл.
    var fullscreen = false
    var onToggleFullscreen: (() -> Void)?

    /// Всё, что карточка занимает помимо полотна: шапка, щётка и ряд кнопок.
    /// Одним числом и в одном месте — из него альбомная раскладка считает
    /// высоту графика, и разъехаться этим двум нельзя.
    static let chromeHeight: CGFloat = 146

    private let axisWidth: CGFloat = 40

    /// Колонка слева появляется ТОЛЬКО под шкалу жира: без второго ряда это
    /// просто отнятая у кривой ширина.
    private var padding: WeightPlot.Padding {
        .init(top: 14, bottom: 28,
              leading: settings.showFatSeries ? 30 : 2, trailing: axisWidth)
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
                                                         height: proxy.size.height),
                                            padding: padding, niceScale: true,
                                            showFat: settings.showFatSeries,
                                            smooth: settings.smoothCurve)
                let mark = marker(plot)
                ZStack(alignment: .topLeading) {
                    WeightChartCanvas(plot: plot, palette: palette,
                                      markerX: mark?.point.x, markerPoint: mark?.point,
                                      markerFatPoint: mark?.fatPoint,
                                      markerHeld: model.markerHeld,
                                      showGoalLine: settings.showGoalLine,
                                      showForecast: settings.showForecast,
                                      showAxis: true)
                        .equatable()

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

            controls
                .padding(.top, 12)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.abortGestures() }
        }
    }

    // MARK: Шапка

    /// Показания метки живут ЗДЕСЬ, а не выноской над полотном.
    ///
    /// Выноска висела рядом с пальцем и закрывала ровно тот участок кривой,
    /// ради которого её и вызывали (заказ владельца 24.08.2026). Место в шапке
    /// постоянное: цифры не прыгают, кадр не перекрыт, а высота строки одна и
    /// та же с меткой и без неё — от появления подписи ничего не съезжает.
    private var header: some View {
        let marked = model.marked
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                Text(marked.map { Fmt.dayLabel($0.date) + ", " + Fmt.time($0.date) }
                     ?? L("range · %d d", model.visibleDays))
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .foregroundStyle(palette.fg2)
                HStack(alignment: .lastTextBaseline, spacing: 5) {
                    // Перекатывание цифр СНЯТО: оно запускало анимацию на
                    // каждом кадре протяжки.
                    Text(marked.map { Fmt.n($0.kg) } ?? spanLabel)
                        .font(.system(size: 24, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(palette.fg)
                    Text(L("kg"))
                        .font(.system(size: 13))
                        .foregroundStyle(palette.fg2)
                }
            }
            Spacer(minLength: 8)
            if let m = marked {
                readout(m)
            } else {
                Text(L("press and hold — marker\npinch — zoom"))
                    .font(.system(size: 10))
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(palette.fg3)
                    .padding(.top, 3)
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 8)
    }

    /// Правая колонка шапки при поднятой метке: дельта и, если включён второй
    /// ряд, процент жира того же измерения.
    private func readout(_ m: WeightPoint) -> some View {
        // Дельта берётся ГОТОВОЙ из снимка, а не поиском по всей истории.
        let d = model.snapshot.deltas[m.id]
        return VStack(alignment: .trailing, spacing: 1) {
            Text(d.map { L("%@ kg", Fmt.signed($0)) } ?? L("first"))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(d.map { palette.delta($0) } ?? palette.fg3)
            if settings.showFatSeries {
                // Прочерк, а не пропуск строки: у ручной записи жира нет, и
                // молчание читалось бы как «не измерено сегодня».
                Text(m.fat.map { L("body fat %@ %%", Fmt.n($0, 1)) } ?? L("no body fat"))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(m.fat == nil ? palette.fg3 : palette.orange)
            }
        }
        .padding(.top, 2)
    }

    // MARK: Кнопки под графиком

    private var controls: some View {
        @Bindable var s = settings
        return HStack(spacing: 8) {
            chip(L("Body fat"), symbol: "percent", isOn: $s.showFatSeries, tint: palette.orange)
            chip(L("Smooth"), symbol: "point.topleft.down.to.point.bottomright.curvepath",
                 isOn: $s.smoothCurve, tint: palette.blue)

            Spacer(minLength: 0)

            if let toggle = onToggleFullscreen {
                Button(fullscreen ? L("Exit full screen") : L("Full screen"),
                       systemImage: fullscreen
                       ? "arrow.down.right.and.arrow.up.left"
                       : "arrow.up.left.and.arrow.down.right") {
                    toggle()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 6)
    }

    /// Кнопка-тумблер со значком и подписью ОДНОГО цвета и размера. Системный
    /// `Label` внутри такой кнопки красил значок в цвет акцента приложения, а
    /// не в цвет тумблера, и рисовал его крупнее слова — «%» выходил синим и
    /// большим рядом с оранжевым «Жир».
    private func chip(_ title: String, symbol: String, isOn: Binding<Bool>, tint: Color) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                Text(title)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(isOn.wrappedValue ? tint : palette.fg2)
        }
        .toggleStyle(.button)
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(tint)
    }

    /// Размах берётся из ОСЕВШЕГО окна: на кадрах жеста цифра не пляшет.
    private var spanLabel: String {
        guard let lo = model.digest.lo, let hi = model.digest.hi else { return "—" }
        return "\(Fmt.n(lo, 1)) – \(Fmt.n(hi, 1))"
    }

    /// Метка хранится ДАТОЙ, поэтому при смене окна остаётся на своей секунде
    /// сама. Уехала за край — не рисуем: это замер, и показывать его над чужим
    /// местом нельзя.
    ///
    /// Измерение выбирает `model.marked` — ОДИН раз и по снимку; здесь берётся
    /// ровно оно, по идентификатору. Два независимых поиска «ближайшего» (один
    /// по снимку для шапки, другой по засечкам кадра для кружка) на краю окна
    /// расходились: шапка показывала бы одно измерение, кружок стоял бы на
    /// другом.
    private func marker(_ plot: WeightPlot) -> (sample: WeightPlot.Sample, point: CGPoint,
                                                fatPoint: CGPoint?)? {
        guard let m = model.marked, m.date >= plot.t0, m.date <= plot.t1,
              let s = plot.samples.first(where: { $0.id == m.id }) else { return nil }
        let fat = plot.hasFat ? s.fat.map { CGPoint(x: s.point.x, y: plot.fatY($0)) } : nil
        return (s, s.point, fat)
    }
}

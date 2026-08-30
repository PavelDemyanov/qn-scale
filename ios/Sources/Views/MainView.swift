import SwiftUI

/// Главный экран. Три компоновки из макета — переключаются тут же, сверху.
struct MainView: View {
    @Environment(\.palette) private var palette
    @Environment(AppSettings.self) private var settings

    let items: [WeighIn]
    let onManualAdd: () -> Void
    let onGoal: () -> Void
    let onOpenHistory: () -> Void
    let onOpenDay: (WeighIn) -> Void
    let onLoadSample: () -> Void
    let onRemoveSample: () -> Void
    let onImportHealth: () -> Void

    private var stats: Stats { Stats(items: items, goal: settings.goalWeight) }

    /// Снимок данных графика строится ОДИН раз на смену истории и раздаётся
    /// вниз: обращения к объектам хранилища из тела кривой стоят дороже самой
    /// отрисовки.
    @State private var snapshot = WeightSnapshot.empty
    @State private var snapshotVersion = 0

    private struct SnapshotKey: Equatable {
        var count: Int
        var first: Date?
        var last: Date?
        var goal: Double
        var forecast: Bool
        var profile: Profile
    }

    private var key: SnapshotKey {
        SnapshotKey(count: items.count, first: items.first?.date, last: items.last?.date,
                    goal: settings.goalWeight, forecast: settings.showForecast,
                    profile: settings.profile)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Компоновку выбирают ГЛАЗАМИ, сравнивая экраны между собой, —
            // значит и переключатель обязан быть здесь, а не в настройках:
            // прежде на каждое сравнение приходилось идти в другой раздел и
            // возвращаться обратно.
            if !items.isEmpty { layoutPicker }

            Group {
                if items.isEmpty {
                    EmptyState(onManualAdd: onManualAdd,
                               onLoadSample: onLoadSample,
                               onImportHealth: onImportHealth)
                } else {
                    switch settings.mainLayout {
                    case .numbers: LayoutNumbers(stats: stats, items: items, snapshot: snapshot,
                                                 onManualAdd: onManualAdd,
                                                 onGoal: onGoal, onOpenHistory: onOpenHistory)
                    case .chart:   LayoutChart(stats: stats, items: items, snapshot: snapshot,
                                               onGoal: onGoal, onOpenDay: onOpenDay)
                    case .goal:    LayoutGoal(stats: stats, items: items, onManualAdd: onManualAdd, onGoal: onGoal)
                    }
                }
            }
        }
        .safeAreaInset(edge: .top) {
            // Пример видно всегда, пока он лежит в истории: иначе демонстрация
            // незаметно притворяется настоящими измерениями.
            if items.contains(where: { $0.isSample }) {
                SampleBanner(onRemove: onRemoveSample)
            }
        }
        .padding(.bottom, 24)
        .onChange(of: key, initial: true) { _, _ in
            snapshotVersion &+= 1
            snapshot = WeightSnapshot.build(items: items, profile: settings.profile,
                                            goal: settings.goalWeight,
                                            showForecast: settings.showForecast,
                                            version: snapshotVersion)
        }
    }

    /// Системный сегментный переключатель — той же ширины, что карточки под ним.
    private var layoutPicker: some View {
        @Bindable var s = settings
        return Picker(L("Main screen"), selection: $s.mainLayout) {
            ForEach(MainLayout.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .cardInset()
        .padding(.bottom, 4)
    }
}

// MARK: - Пустая история

private struct EmptyState: View {
    let onManualAdd: () -> Void
    let onLoadSample: () -> Void
    let onImportHealth: () -> Void

    var body: some View {
        // Три равноправных пути к данным. Раньше был один — «встаньте на
        // весы», и человек без весов упирался в пустой экран, не понимая, что
        // приложение вообще умеет.
        ContentUnavailableView {
            Label(L("First weigh-in"), systemImage: "scalemass")
        } description: {
            Text(L("Step on the scale and the weight is recorded by itself. No scale yet — add a weight by hand, import your history from Health, or look at a sample."))
        } actions: {
            VStack(spacing: 10) {
                Button(L("Add weight manually"), action: onManualAdd)
                    .buttonStyle(.borderedProminent)
                Button(L("Import history from Health"), action: onImportHealth)
                Button(L("Load sample history"), action: onLoadSample)
            }
        }
    }
}

/// Полоса «это пример». Висит поверх содержимого, пока в истории есть
/// демонстрационные записи, и убирается той же кнопкой.
private struct SampleBanner: View {
    @Environment(\.palette) private var palette
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
            Text(L("Sample history"))
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button(L("Remove"), action: onRemove)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(palette.orange.opacity(0.18))
        .foregroundStyle(palette.orange)
    }
}

// MARK: - Компоновка «Числа»

private struct LayoutNumbers: View {
    @Environment(\.palette) private var palette
    @Environment(AppSettings.self) private var settings
    let stats: Stats
    let items: [WeighIn]
    let snapshot: WeightSnapshot
    let onManualAdd: () -> Void
    let onGoal: () -> Void
    let onOpenHistory: () -> Void

    var body: some View {
        VStack(spacing: 9) {
            // Крупный вес и дельта за день
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .lastTextBaseline, spacing: 7) {
                    Text(Fmt.n(stats.last?.weightKg))
                        .font(.system(size: 50, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(palette.fg)
                    Text(L("kg"))
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(palette.fg2)
                }
                HStack(spacing: 8) {
                    if let day = stats.dayDelta {
                        HStack(spacing: 5) {
                            Text(Fmt.arrow(day))
                            Text(L("%@ kg", Fmt.n(abs(day)))).monospacedDigit()
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.delta(day))
                        .padding(.leading, 9)
                        .padding(.trailing, 11)
                        .padding(.vertical, 5)
                        .background(palette.deltaTint(day), in: Capsule())
                        Text(L("since yesterday"))
                            .font(.system(size: 14))
                            .foregroundStyle(palette.fg2)
                    } else {
                        Text(L("first measurement"))
                            .font(.system(size: 14))
                            .foregroundStyle(palette.fg2)
                    }
                    Spacer()
                    if let fat = stats.last?.fatPercent(for: settings.profile) {
                        Text(L("body fat %@ %%", Fmt.n(fat, 1)))
                            .font(.system(size: 14))
                            .monospacedDigit()
                            .foregroundStyle(palette.fg2)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 15)
            .padding(.bottom, 13)
            .card()
            .cardInset()

            HStack(spacing: 11) {
                DeltaTile(caption: L("THIS WEEK"), value: stats.weekDelta)
                DeltaTile(caption: L("THIS MONTH"), value: stats.monthDelta)
            }
            .cardInset()

            SparkCard(stats: stats, snapshot: snapshot, onTap: onOpenHistory)

            // Те же столбики недели, что и в компоновке «Цель»: по ним видно,
            // как прошла именно ЭТА неделя, а счётчики «дней с весами» и
            // «дней подряд» об этом не говорили ничего.
            WeekBarsCard(stats: stats)

            forecastSection
        }
        .padding(.top, 8)
    }

    private var lastLabel: String {
        guard let last = stats.last else { return "" }
        return Fmt.dayLabel(last.date) + ", " + Fmt.time(last.date)
    }

    private var goalSubtitle: String {
        guard settings.showForecast else { return L("left to goal") }
        return stats.ratePerWeek.map { L("%@ kg per week", Fmt.signed($0)) } ?? L("rate not available yet")
    }

    private var forecastSection: some View {
        VStack(spacing: 0) {
            // Период в заголовке: без него «текущий темп» — величина ниоткуда,
            // и непонятно, что за история стоит за прогнозом.
            SectionHeader(text: settings.showForecast ? L("FORECAST FROM THE LAST 30 DAYS") : L("GOAL"), top: 2)
            VStack(spacing: 0) {
                ForEach(settings.showForecast
                        ? [(7.0, L("In a week")), (14.0, L("In 2 weeks")), (30.0, L("In a month"))]
                        : [], id: \.0) { days, label in
                    Row(title: label, minHeight: 41) {
                        Text(stats.forecast(days: days).map { L("%@ kg", Fmt.n($0)) } ?? "—")
                            .font(.body.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(palette.fg2)
                    }
                    RowSeparator()
                }
                Button(action: onGoal) {
                    Row(title: L("Goal %@ kg", Fmt.n(settings.goalWeight, 1)),
                        subtitle: goalSubtitle, minHeight: 52) {
                        // Дата достижения цели — главное в строке, и ужиматься
                        // она не должна: подпись про темп длинная, и без
                        // приоритета «2 октября» обрезалось до «…ября».
                        Text(settings.showForecast
                             ? stats.goalDateLabel
                             : (stats.toGoal.map { L("%@ kg", Fmt.n($0)) } ?? "—"))
                            .font(.body.weight(.semibold))
                            // Зелёным — только настоящая дата. Пометка «не
                            // снижается» зелёной быть не должна: цвет читается
                            // как «всё идёт по плану».
                            .foregroundStyle(stats.goalDate != nil || !settings.showForecast
                                             ? palette.green : palette.fg2)
                            .lineLimit(1)
                            .fixedSize()
                            .layoutPriority(1)
                    }
                }
                .buttonStyle(.plain)
            }
            .card()
            .cardInset()
        }
    }
}

/// Карточка со спарклайном за 30 дней.
private struct SparkCard: View {
    @Environment(\.palette) private var palette
    @Environment(AppSettings.self) private var settings
    let stats: Stats
    let snapshot: WeightSnapshot
    let onTap: () -> Void

    private let height: CGFloat = 86

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                HStack {
                    Text(L("Last 30 days"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.fg)
                    Spacer()
                    if settings.showGoalLine {
                    HStack(spacing: 6) {
                        // Пунктир, как линия цели на самом графике
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: 0.75))
                            p.addLine(to: CGPoint(x: 14, y: 0.75))
                        }
                        .stroke(palette.green, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .frame(width: 14, height: 1.5)
                        Text(L("goal %@", Fmt.n(settings.goalWeight, 1)))
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(palette.fg2)
                    }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 8)

                GeometryReader { proxy in
                    let size = CGSize(width: proxy.size.width, height: height)
                    WeightChart(snapshot: snapshot,
                                window: snapshot.timeline.window(for: .d30),
                                goal: settings.goalWeight, size: size,
                                padding: .init(top: 5, bottom: 5, leading: 3, trailing: 3),
                                // Цель втягиваем в кадр по тому же правилу, что
                                // и на большом графике, а не безусловно.
                                pullGoal: WeightPlot.goalFits(snapshot,
                                                              window: snapshot.timeline.window(for: .d30),
                                                              goal: settings.goalWeight,
                                                              showForecast: settings.showForecast),
                                showGoalLine: settings.showGoalLine,
                                showForecast: settings.showForecast,
                                endDotRing: palette.card, lineWidth: 2.2)
                }
                .frame(height: height)

                HStack {
                    Text(firstVisibleLabel)
                    Spacer()
                    Text(L("today"))
                }
                .font(.system(size: 11))
                .foregroundStyle(palette.fg3)
                .padding(.horizontal, 4)
                .padding(.top, 2)
            }
            .padding(.horizontal, 14)
            .padding(.top, 13)
            .padding(.bottom, 7)
            .card()
        }
        .buttonStyle(.plain)
        .cardInset()
    }

    /// Дата первого измерения в окне 30 дней — подпись слева под спарклайном.
    private var firstVisibleLabel: String {
        let from = (stats.last?.date ?? Date()).addingTimeInterval(-30 * 86_400)
        guard let first = snapshot.points.first(where: { $0.date >= from }) else { return "" }
        return Fmt.shortDayMonth(first.date)
    }
}

// MARK: - Компоновка «График»

private struct LayoutChart: View {
    @Environment(\.palette) private var palette
    @Environment(AppSettings.self) private var settings
    let stats: Stats
    let items: [WeighIn]
    let snapshot: WeightSnapshot
    let onGoal: () -> Void
    let onOpenDay: (WeighIn) -> Void

    /// Период — ЭНУМ, а не число суток: у тегов-`Double` «Всё» совпадало с
    /// другим сегментом на короткой истории и менялось после каждого
    /// взвешивания, отчего выбор слетал сам собой.
    @State private var period: WeightPeriod = .d30

    /// На главном экране пресеты покрупнее, но и они показываются, только пока
    /// означают разное (см. `WeightTimeline.availablePeriods`).
    private var heroPeriods: [WeightPeriod] {
        snapshot.timeline.availablePeriods.filter { $0 != .d7 }
    }

    /// Выбранный пресет мог исчезнуть из списка (история короче) — тогда
    /// показываем всю историю, а не пустой переключатель.
    private var effectivePeriod: WeightPeriod {
        heroPeriods.contains(period) ? period : .all
    }

    var body: some View {
        VStack(spacing: 13) {
            hero
            deltaRow
            goalCard
            recentList
        }
    }

    private var hero: some View {
        GeometryReader { proxy in
            let size = CGSize(width: proxy.size.width, height: 322)

            ZStack(alignment: .topLeading) {
                WeightChart(snapshot: snapshot,
                            window: snapshot.timeline.window(for: effectivePeriod),
                            goal: settings.goalWeight, size: size,
                            padding: .init(top: 120, bottom: 64, leading: 0, trailing: 0),
                            pullGoal: false, showGoalLine: false,
                            showForecast: settings.showForecast,
                            // Засечки — только пока они различимы. То же
                            // правило, что в «Истории»: на трёх месяцах
                            // кружки по 5 пунктов смыкаются, и линия
                            // превращается в цепочку бусин.
                            showDots: snapshot.timeline.dataDays(
                                snapshot.timeline.window(for: effectivePeriod)) <= 45,
                            showDeltas: settings.showDeltaPills,
                            endDotRing: palette.bg, lineWidth: 2.4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(lastLabel)
                        .font(.system(size: 13))
                        .foregroundStyle(palette.fg2)
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(Fmt.n(stats.last?.weightKg))
                            .font(.system(size: 52, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(palette.fg)
                        Text(L("kg"))
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(palette.fg2)
                    }
                    if let day = stats.dayDelta {
                        HStack(spacing: 6) {
                            Text(L("%@ %@ kg", Fmt.arrow(day), Fmt.n(abs(day))))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(palette.delta(day))
                            Text(L("since last time"))
                                .font(.system(size: 15))
                                .foregroundStyle(palette.fg3)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.leading, 20)
                .padding(.top, 8)

                // Читаем ДЕЙСТВУЮЩИЙ период: выбранный мог исчезнуть из списка
                // на короткой истории, и переключатель стоял бы вовсе без
                // выделения. Записываем по-прежнему в `period`, чтобы выбор
                // вернулся сам, когда история дорастёт.
                // Период и выключатель подписей — ОДНОЙ строкой. Прежде это
                // были две независимые накладки со своими отступами, и центры
                // у них не совпадали: кнопка сидела выше переключателя.
                // Выравнивание в строке считает сам HStack, вручную его
                // подгонять не приходится.
                HStack(spacing: 10) {
                    Picker(L("Period"), selection: Binding(get: { effectivePeriod },
                                                        set: { period = $0 })) {
                        ForEach(heroPeriods) { p in
                            Text(p == .d90 ? L("3 months") : p.title).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)

                    pillsToggle
                }
                .padding(.horizontal, 16)
                .frame(width: proxy.size.width, height: 44, alignment: .bottom)
                .offset(y: 322 - 52)
            }
        }
        .frame(height: 322)
    }

    /// Кнопка «показать/скрыть подписи изменений». Системный тумблер-кнопка:
    /// нажатое состояние он рисует сам, и объяснять его отдельной подписью не
    /// приходится.
    private var pillsToggle: some View {
        @Bindable var s = settings
        return Toggle(isOn: $s.showDeltaPills) {
            Image(systemName: "plusminus")
                .font(.system(size: 13, weight: .semibold))
                // Значок в своей рамке: вместе с полями обычного размера
                // кнопки это даёт зону нажатия около 44 пунктов. Кружок «по
                // размеру значка» выходил вдвое меньше нормы, а рядом стоит
                // переключатель периода — промахнуться было легко.
                .frame(width: 26, height: 26)
        }
        .toggleStyle(.button)
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .tint(palette.blue)
        .accessibilityLabel(L("Change labels"))
    }

    private var lastLabel: String {
        guard let last = stats.last else { return "" }
        return Fmt.dayLabel(last.date) + ", " + Fmt.time(last.date)
    }

    private var deltaRow: some View {
        HStack(spacing: 0) {
            column(L("DAY"), stats.dayDelta)
            verticalSeparator
            column(L("THIS WEEK"), stats.weekDelta)
            verticalSeparator
            column(L("THIS MONTH"), stats.monthDelta)
        }
        .card(radius: 20)
        .cardInset()
    }

    /// Волосяная линия во всю высоту. RowSeparator тут не годится: у него
    /// зафиксирована высота 0,5, и вертикальный разделитель вырождается в точку.
    private var verticalSeparator: some View {
        Rectangle()
            .fill(palette.sep)
            .frame(width: 0.5)
            .frame(maxHeight: .infinity)
            .padding(.vertical, 12)
    }

    private func column(_ caption: String, _ value: Double?) -> some View {
        VStack(spacing: 3) {
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(palette.fg2)
            Text(value.map { Fmt.signed($0) } ?? "—")
                .font(.system(size: 21, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(value.map { palette.delta($0) } ?? palette.fg2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    private var goalCard: some View {
        Button(action: onGoal) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(goalHeadline)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.fg)
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(palette.fg2)
                }
                Spacer()
                trendSpark
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .card(radius: 20)
        }
        .buttonStyle(.plain)
        .cardInset()
    }

    /// С датой — «2 октября — 77,0 кг». Без даты порядок обратный: сначала сама
    /// цель, потом причина, иначе получалось «не снижается — 77,0 кг».
    /// Причина — коротко: рядом со спарклайном фраза целиком занимала три
    /// строки, а темп всё равно написан подписью ниже.
    private var goalHeadline: String {
        guard stats.goalDate != nil else {
            return L("Goal %@ kg — %@", Fmt.n(settings.goalWeight, 1), stats.goalDateLabel)
        }
        return L("%@ — %@ kg", stats.goalDateLabel, Fmt.n(settings.goalWeight, 1))
    }

    private var subtitle: String {
        let rate = stats.ratePerWeek.map { L("rate %@ kg/week", Fmt.signed($0)) } ?? L("rate not available yet")
        let left = stats.toGoal.map { " · " + L("%@ kg to goal", Fmt.n($0)) } ?? ""
        return rate + left
    }

    private var trendSpark: some View {
        let drop = min(24, abs((stats.ratePerWeek ?? 0)) * 32)
        return Path { p in
            p.move(to: CGPoint(x: 3, y: 28))
            p.addLine(to: CGPoint(x: 73, y: 28 - drop))
        }
        .stroke(palette.green, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        .frame(width: 76, height: 32)
    }

    private var recentList: some View {
        VStack(spacing: 0) {
            SectionHeader(text: L("BY DAY"), top: 4)
            VStack(spacing: 0) {
                let recent = Array(items.suffix(5).reversed())
                ForEach(recent) { item in
                    Button { onOpenDay(item) } label: {
                        Row(title: Fmt.dayLabel(item.date), minHeight: 48) {
                            HStack(spacing: 12) {
                                Text(Fmt.n(item.weightKg))
                                    .font(.body.weight(.medium))
                                    .monospacedDigit()
                                    .foregroundStyle(palette.fg)
                                Text(deltaString(for: item))
                                    .font(.system(size: 15, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(deltaColor(for: item))
                                    .frame(minWidth: 62, alignment: .trailing)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    if item.id != recent.last?.id { RowSeparator() }
                }
            }
            .card(radius: 20)
            .cardInset()

            Text(L("%@ · %@ with the scale · %@ in a row",
                   Ln(items.count, "weigh-in"), Ln(stats.daysWithScale, "day"),
                   Ln(stats.streak, "day")))
                .font(.system(size: 12))
                .foregroundStyle(palette.fg3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 36)
                .padding(.top, 8)
        }
    }

    private func delta(for item: WeighIn) -> Double? {
        guard let idx = items.firstIndex(where: { $0.id == item.id }), idx > 0 else { return nil }
        return item.weightKg - items[idx - 1].weightKg
    }
    private func deltaString(for item: WeighIn) -> String { delta(for: item).map { Fmt.signed($0) } ?? "—" }
    private func deltaColor(for item: WeighIn) -> Color { delta(for: item).map { palette.delta($0) } ?? palette.fg3 }
}

// MARK: - Компоновка «Цель»

private struct LayoutGoal: View {
    @Environment(\.palette) private var palette
    @Environment(AppSettings.self) private var settings
    let stats: Stats
    let items: [WeighIn]
    let onManualAdd: () -> Void
    let onGoal: () -> Void

    var body: some View {
        VStack(spacing: 13) {
            ring
            WeekBarsCard(stats: stats)
            if settings.showForecast { forecastCard }

            HStack(spacing: 11) {
                DeltaTile(caption: L("THIS WEEK"), value: stats.weekDelta)
                DeltaTile(caption: L("THIS MONTH"), value: stats.monthDelta)
                fatTile
            }
            .cardInset()
        }
        .padding(.top, 8)
    }

    private var fatTile: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L("BODY FAT"))
                .font(.system(size: 12))
                .foregroundStyle(palette.fg2)
            Text(stats.last?.fatPercent(for: settings.profile).map { Fmt.n($0, 1) } ?? "—")
                .font(.system(size: 22, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(palette.fg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .card(radius: 18)
    }

    private var ring: some View {
        ZStack {
            // Пропорции макета: радиус 108 при вьюбоксе 250 и толщине 14 —
            // в пунктах это радиус 92,5 и толщина 12.
            Circle()
                .stroke(palette.card2, lineWidth: 12)
                .padding(14.5)
            Circle()
                .trim(from: 0, to: stats.goalProgress)
                .stroke(palette.blue, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .padding(14.5)
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text(lastLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.fg2)
                HStack(alignment: .lastTextBaseline, spacing: 5) {
                    Text(Fmt.n(stats.last?.weightKg))
                        .font(.system(size: 44, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(palette.fg)
                    Text(L("kg"))
                        .font(.body.weight(.medium))
                        .foregroundStyle(palette.fg2)
                }
                if let day = stats.dayDelta {
                    Text(L("%@ %@ kg since yesterday", Fmt.arrow(day), Fmt.n(abs(day))))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.delta(day))
                        .padding(.top, 2)
                }
                if let toGoal = stats.toGoal {
                    Text(L("%@ kg to goal", Fmt.n(toGoal)))
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.fg3)
                        .padding(.top, 6)
                }
            }
        }
        .frame(width: 214, height: 214)
        // В макете подписи стартового и целевого веса привязаны к краям экрана
        // (left:24 / right:24, bottom:14), а не к краям кольца.
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottomLeading) {
            Text(Fmt.n(stats.startWeight, 1))
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(palette.fg3)
                .padding(.leading, 24)
                .padding(.bottom, 14)
        }
        .overlay(alignment: .bottomTrailing) {
            Text(Fmt.n(settings.goalWeight, 1))
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(palette.green)
                .padding(.trailing, 24)
                .padding(.bottom, 14)
        }
    }

    private var lastLabel: String {
        guard let last = stats.last else { return "" }
        return Fmt.dayLabel(last.date) + ", " + Fmt.time(last.date)
    }

    private var forecastCard: some View {
        Button(action: onGoal) {
            VStack(alignment: .leading, spacing: 0) {
                Text(headline)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.fg)
                    .lineSpacing(3)
                    .multilineTextAlignment(.leading)
                Text(stats.ratePerWeek.map { L("%@ kg per week over the last 30 days", Fmt.signed($0)) }
                     ?? L("The rate appears after a few measurements"))
                    .font(.system(size: 13))
                    .foregroundStyle(palette.fg2)
                    .padding(.top, 5)

                HStack(spacing: 10) {
                    ForEach([(7.0, L("+1 wk")), (14.0, L("+2 wk")), (30.0, L("+1 mo"))], id: \.0) { days, label in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(label)
                                .font(.system(size: 11))
                                .foregroundStyle(palette.fg2)
                            Text(stats.forecast(days: days).map { Fmt.n($0) } ?? "—")
                                .font(.system(size: 19, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(palette.fg)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 10)
                        .background(palette.card2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(.top, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .card()
        }
        .buttonStyle(.plain)
        .cardInset()
    }

    private var headline: String {
        guard stats.goalDate != nil else {
            return L("Goal %@ kg — %@", Fmt.n(settings.goalWeight, 1), stats.goalHint)
        }
        return L("If the rate holds, %@ kg on %@", Fmt.n(settings.goalWeight, 1), stats.goalDateLabel)
    }
}

// MARK: - Столбики недели

/// Дельты по дням ТЕКУЩЕЙ недели, понедельник — воскресенье.
///
/// Одна карточка на две компоновки: «Числа» и «Цель» рисовали бы одно и то же
/// двумя копиями кода, и они бы разошлись на первой правке.
private struct WeekBarsCard: View {
    @Environment(\.palette) private var palette
    let stats: Stats

    /// Полувысота поля столбиков: столько места отведено набору вверх и
    /// снижению вниз по отдельности.
    private let half: CGFloat = 46
    /// Килограммы, при которых столбик достаёт до края. Обычная суточная
    /// разница — доли килограмма, поэтому шкала мелкая, а всё, что больше,
    /// упирается в край.
    private let fullScale: Double = 0.8

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("This week"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.fg)
                Spacer()
                Text(L("kg per day"))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.fg2)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 10)

            HStack(alignment: .top, spacing: 6) {
                ForEach(stats.currentWeek) { bar in
                    column(bar)
                }
            }
            // Нулевой линии нет намеренно: направление столбика и его цвет
            // говорят всё сами, а лишняя линейка только дробила карточку.
            // Ноль и пропущенный день по-прежнему видны короткой меткой —
            // она и держит уровень отсчёта.
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .card()
        .cardInset()
    }

    private func column(_ bar: Stats.DayBar) -> some View {
        let delta = bar.delta ?? 0
        let gained = delta > 0.0049
        let lost = delta < -0.0049
        return VStack(spacing: 0) {
            // Верхняя половина: набор веса растёт вверх от линии.
            VStack(spacing: 3) {
                Spacer(minLength: 0)
                if gained {
                    Text(Fmt.signed(delta, 1))
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(palette.red)
                    bodyBar(delta, color: palette.red)
                }
            }
            .frame(height: half)

            // Нижняя половина: снижение уходит вниз от линии.
            VStack(spacing: 3) {
                if lost {
                    bodyBar(delta, color: palette.green)
                    Text(Fmt.signed(delta, 1))
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(palette.green)
                } else if !gained {
                    // Ноль, пропуск и будущий день — короткая метка на линии,
                    // чтобы колонка не выглядела потерянной.
                    Capsule()
                        .fill(bar.isFuture ? palette.seg : palette.fg3.opacity(0.5))
                        .frame(height: 3)
                        .padding(.horizontal, 2)
                    if !bar.isFuture, bar.delta != nil {
                        Text(Fmt.signed(0, 1))
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(palette.fg3)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(height: half)

            Text(bar.weekday)
                .font(.system(size: 11, weight: bar.isToday ? .semibold : .regular))
                .textCase(.uppercase)
                .foregroundStyle(bar.isToday ? palette.fg : palette.fg3)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private func bodyBar(_ delta: Double, color: Color) -> some View {
        // 16 пунктов оставлено подписи, остальное — столбику.
        let room = half - 16
        let height = Swift.max(5, Swift.min(room, CGFloat(abs(delta) / fullScale) * room))
        return RoundedRectangle(cornerRadius: 5)
            .fill(color)
            .frame(height: height)
    }
}

import SwiftUI

/// История: график с щёткой, итоги за окно и список измерений.
///
/// Живое окно живёт в `WeightChartModel` и читается ТОЛЬКО карточкой графика.
/// Этот экран читает `digest` — сводку по зафиксированному окну, — поэтому на
/// кадрах жеста список не перестраивается вовсе.
struct HistoryView: View {
    @Environment(\.palette) private var palette
    @Environment(AppSettings.self) private var settings
    /// Телефон на боку — компактная высота. Именно по ней, а не по
    /// `UIDevice.orientation`: последняя врёт, когда телефон лежит на столе.
    @Environment(\.verticalSizeClass) private var vClass

    let items: [WeighIn]
    let onOpenDay: (WeighIn) -> Void
    let onManualAdd: () -> Void
    let onLoadSample: () -> Void
    let onImportHealth: () -> Void

    @State private var model = WeightChartModel()

    /// Ключ пересборки снимка. Взвешивания только добавляются и удаляются —
    /// правки веса в середине истории в приложении нет, поэтому количество и
    /// крайние даты ключ исчерпывают.
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

    private var landscape: Bool { vClass == .compact }

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else if landscape {
                fullscreenChart
            } else {
                List {
                    Section {
                        // Переключатель — ОТДЕЛЬНОЙ строкой, а не внутри карточки:
                        // внутри он рисовался, но в область нажатия строки не
                        // попадал и молча не работал, пока список не прокрутят.
                        Picker(L("Period"), selection: periodBinding) {
                            // Только те пресеты, что на этой истории означают
                            // разное: на трёхдневной «30 дней» и «Всё» — одно
                            // и то же окно.
                            ForEach(model.timeline.availablePeriods) { p in
                                Text(p.title).tag(Optional(p))
                            }
                        }
                        .pickerStyle(.segmented)

                        HistoryChartCard(model: model,
                                         onToggleFullscreen: {
                            // Замок поворота в Пункте управления держат
                            // включённым многие: без явной кнопки альбом был бы
                            // им недоступен вовсе.
                            OrientationLock.unlock()
                            OrientationLock.rotate(to: .landscapeRight)
                        })
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

                    summarySection
                    measurementsSection
                }
                // Прокрутку гасим только на время жеста ПО ГРАФИКУ и метки.
                // Для щётки — НЕ гасим: переключение `scrollDisabled` посреди
                // жеста само способно его отменить, а от отмены щётку защищает
                // `@GestureState`.
                .scrollDisabled(model.gesturing || model.markerHeld)
            }
        }
        // Тулбары гасятся ЗДЕСЬ, а не внутри альбомной ветки: модификатор на
        // всём экране переживает смену ветки, и таббар не мигает на повороте.
        .toolbar(landscape ? .hidden : .visible, for: .navigationBar)
        .toolbar(landscape ? .hidden : .visible, for: .tabBar)
        .statusBarHidden(landscape)
        .persistentSystemOverlays(landscape ? .hidden : .automatic)
        // Поворот сносит ветку вместе с жестовым слоем, и терминального
        // события от распознавателей может не прийти вовсе: флаги залипнут, а
        // с ними — заблокированная прокрутка списка.
        .onChange(of: landscape) { _, _ in model.abortGestures() }
        .onChange(of: key, initial: true) { _, k in
            model.digestGoal = k.goal
            model.digestForecast = k.forecast
            model.reload(items: items, settings: settings)
        }
        // Альбом разрешён РОВНО на этом экране: маску отдаёт делегат
        // приложения, и вне «Истории» она снова портретная — иначе на боку
        // оказывались бы и весы, и настройки, под которые раскладки нет.
        // Пустой истории поворот тоже ни к чему: там показывать нечего.
        .onChange(of: items.isEmpty, initial: true) { _, empty in
            empty ? OrientationLock.relock() : OrientationLock.unlock()
        }
        .onDisappear { OrientationLock.relock() }
    }

    /// Альбом: график во весь экран, без списка, шапки и таббара.
    ///
    /// Модель та же самая, поэтому окно, метка и включённый ряд жира
    /// переживают поворот — человек продолжает смотреть ровно то место, на
    /// которое смотрел до того, как повернул телефон.
    private var fullscreenChart: some View {
        GeometryReader { proxy in
            HistoryChartCard(model: model,
                             // Из высоты вычтено то, что карточка занимает
                             // сама: шапка, щётка и ряд кнопок.
                             chartHeight: Swift.max(160, proxy.size.height - HistoryChartCard.chromeHeight),
                             fullscreen: true,
                             onToggleFullscreen: { OrientationLock.relock() })
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .background(palette.bg)
    }

    /// Выбранный период. `nil` — окно не совпадает ни с одним пресетом (щипок
    /// или щётка), и тогда не подсвечен ни один сегмент: подсветить наугад
    /// значит соврать ровно там, где щётка говорит правду.
    private var periodBinding: Binding<WeightPeriod?> {
        Binding(get: { model.period },
                set: { if let p = $0 { model.apply(p) } })
    }

    private var emptyState: some View {
        ContentUnavailableView(L("Nothing here yet"),
                               systemImage: "chart.xyaxis.line",
                               description: Text(L("Step on the scale — your first measurement will show up here.")))
    }

    private var summarySection: some View {
        let d = model.digest
        return Section(L("Period summary")) {
            LabeledContent(L("Change")) {
                // Прочерк, а не «0,00 кг»: в окне без измерений менятьcя нечему.
                Text(d.change.map { L("%@ kg", Fmt.signed($0)) } ?? "—")
                    .foregroundStyle(d.change.map { palette.delta($0) } ?? Color.secondary)
            }
            LabeledContent(L("Minimum"), value: d.lo.map { L("%@ kg", Fmt.n($0)) } ?? "—")
            LabeledContent(L("Maximum"), value: d.hi.map { L("%@ kg", Fmt.n($0)) } ?? "—")
            LabeledContent(L("Weigh-ins"), value: "\(d.count)")
        }
    }

    private var measurementsSection: some View {
        Section {
            ForEach(model.digest.rows) { p in
                Button { open(p) } label: { row(p) }
                    .buttonStyle(.plain)
            }
        } header: {
            Text(L("Measurements"))
        } footer: {
            Text(model.digest.count > 18
                 ? L("Showing the last 18 of %d for the period", model.digest.count)
                 : L("%@ for the period", Ln(model.digest.count, "measurement")))
        }
    }

    private func row(_ p: WeightPoint) -> some View {
        // Дельта из готовой таблицы: прежде на КАЖДУЮ строку шёл линейный поиск
        // по всей истории.
        let d = model.snapshot.deltas[p.id]
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Fmt.dayLabel(p.date))
                Text(p.fat.map { L("%@ · body fat %@ %%", Fmt.time(p.date), Fmt.n($0, 1)) } ?? Fmt.time(p.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(Fmt.n(p.kg))
                .monospacedDigit()
            Text(d.map { Fmt.signed($0) } ?? "—")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(d.map { palette.delta($0) } ?? Color.secondary)
                .frame(minWidth: 58, alignment: .trailing)
        }
        .contentShape(Rectangle())
    }

    /// Строка хранит СНИМОК, а не ссылку на объект хранилища: удалённая запись
    /// иначе доживает до отрисовки. Настоящий объект ищем только по тапу.
    private func open(_ p: WeightPoint) {
        guard let item = items.first(where: { $0.persistentModelID == p.id }) else { return }
        onOpenDay(item)
    }
}

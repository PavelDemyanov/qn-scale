import SwiftUI

/// История: график с щёткой, итоги за окно и список измерений.
///
/// Живое окно живёт в `WeightChartModel` и читается ТОЛЬКО карточкой графика.
/// Этот экран читает `digest` — сводку по зафиксированному окну, — поэтому на
/// кадрах жеста список не перестраивается вовсе.
struct HistoryView: View {
    @Environment(\.palette) private var palette
    @Environment(AppSettings.self) private var settings

    let items: [WeighIn]
    let onOpenDay: (WeighIn) -> Void

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

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        // Переключатель — ОТДЕЛЬНОЙ строкой, а не внутри карточки:
                        // внутри он рисовался, но в область нажатия строки не
                        // попадал и молча не работал, пока список не прокрутят.
                        Picker("Период", selection: periodBinding) {
                            // Только те пресеты, что на этой истории означают
                            // разное: на трёхдневной «30 дней» и «Всё» — одно
                            // и то же окно.
                            ForEach(model.timeline.availablePeriods) { p in
                                Text(p.title).tag(Optional(p))
                            }
                        }
                        .pickerStyle(.segmented)

                        HistoryChartCard(model: model)
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
        .onChange(of: key, initial: true) { _, k in
            model.digestGoal = k.goal
            model.digestForecast = k.forecast
            model.reload(items: items, settings: settings)
        }
    }

    /// Выбранный период. `nil` — окно не совпадает ни с одним пресетом (щипок
    /// или щётка), и тогда не подсвечен ни один сегмент: подсветить наугад
    /// значит соврать ровно там, где щётка говорит правду.
    private var periodBinding: Binding<WeightPeriod?> {
        Binding(get: { model.period },
                set: { if let p = $0 { model.apply(p) } })
    }

    private var emptyState: some View {
        ContentUnavailableView("Пока пусто",
                               systemImage: "chart.xyaxis.line",
                               description: Text("Встаньте на весы — первое измерение появится здесь."))
    }

    private var summarySection: some View {
        let d = model.digest
        return Section("Итог за период") {
            LabeledContent("Изменение") {
                // Прочерк, а не «0,00 кг»: в окне без измерений менятьcя нечему.
                Text(d.change.map { "\(Fmt.signed($0)) кг" } ?? "—")
                    .foregroundStyle(d.change.map { palette.delta($0) } ?? Color.secondary)
            }
            LabeledContent("Минимум", value: d.lo.map { "\(Fmt.n($0)) кг" } ?? "—")
            LabeledContent("Максимум", value: d.hi.map { "\(Fmt.n($0)) кг" } ?? "—")
            LabeledContent("Взвешиваний", value: "\(d.count)")
        }
    }

    private var measurementsSection: some View {
        Section {
            ForEach(model.digest.rows) { p in
                Button { open(p) } label: { row(p) }
                    .buttonStyle(.plain)
            }
        } header: {
            Text("Измерения")
        } footer: {
            Text(model.digest.count > 18
                 ? "Показаны последние 18 из \(model.digest.count) за период"
                 : "\(model.digest.count) измерений за период")
        }
    }

    private func row(_ p: WeightPoint) -> some View {
        // Дельта из готовой таблицы: прежде на КАЖДУЮ строку шёл линейный поиск
        // по всей истории.
        let d = model.snapshot.deltas[p.id]
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Fmt.dayLabel(p.date))
                Text(p.fat.map { "\(Fmt.time(p.date)) · жир \(Fmt.n($0, 1)) %" } ?? Fmt.time(p.date))
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

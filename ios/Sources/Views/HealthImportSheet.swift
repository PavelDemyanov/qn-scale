import SwiftUI
import SwiftData

/// Импорт истории веса из «Здоровья».
struct HealthImportSheet: View {
    @Environment(\.palette) private var palette
    @Environment(AppSettings.self) private var settings
    @Environment(HealthStore.self) private var health
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let items: [WeighIn]

    @State private var stage = Stage.preparing
    @State private var skipDuplicates = true
    @State private var preview = HealthStore.ImportResult()
    @State private var progress: Double = 0
    @State private var importedCount = 0
    @State private var skippedCount = 0

    private enum Stage { case preparing, options, running, done }

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.fg)
                Text(subtitle)
                    .font(.system(size: 14))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.fg2)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            if stage == .options {
                optionsCard.padding(.top, 22)
            }
            // На финальном шаге полоса остаётся заполненной — иначе содержимое
            // прыгает в момент, когда импорт закончился.
            if stage == .running || stage == .done {
                progressBar.padding(.top, 28)
            }

            Spacer()

            PrimaryButton(title: buttonTitle,
                          background: buttonEnabled ? palette.blue : palette.card2,
                          foreground: buttonEnabled ? .white : palette.fg3) {
                if stage == .options { runImport() } else if stage == .done { dismiss() }
            }
            .disabled(!buttonEnabled)
            .padding(.horizontal, 16)
            .padding(.bottom, 34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.sheet)
        // Отступ 34 у кнопки — от края экрана, как в макете
        .ignoresSafeArea(edges: .bottom)
        .task { await loadPreview() }
    }

    private var header: some View {
        HStack {
            Button("Отмена") { dismiss() }
                .font(.system(size: 17))
                .foregroundStyle(palette.blue)
                .frame(width: 80, alignment: .leading)
            Spacer()
            Text("«Здоровье»")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.fg)
            Spacer()
            // Не Color: он растягивается по вертикали и раздувает шапку на всю шторку.
            Spacer().frame(width: 80)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var title: String {
        switch stage {
        case .preparing: return "Читаю «Здоровье»…"
        case .options: return "Найдено \(preview.found) записей о весе"
        case .running: return "Импортирую"
        case .done: return "Импортировано \(importedCount) измерений"
        }
    }

    private var subtitle: String {
        switch stage {
        case .preparing:
            return "Смотрю, какие записи о весе там есть."
        case .options:
            guard preview.found > 0 else {
                return "В «Здоровье» нет записей о весе от других приложений."
            }
            let earliest = preview.earliest.map { "Самая ранняя — \(Fmt.dayMonth($0)) \(Calendar.current.component(.year, from: $0)). " } ?? ""
            return earliest + "Импеданса в «Здоровье» нет, поэтому процент жира у этих записей будет пустым."
        case .running:
            return "Читаю записи и считаю дельты по дням…"
        case .done:
            return skippedCount > 0
                ? "\(skippedCount) записей пропущены как дубликаты уже сохранённых измерений."
                : "Дубликатов не нашлось."
        }
    }

    private var buttonTitle: String {
        switch stage {
        case .preparing: return "Читаю…"
        case .options: return preview.found > 0 ? "Импортировать" : "Закрыть"
        case .running: return "Импортирую…"
        case .done: return "Готово"
        }
    }

    private var buttonEnabled: Bool { stage == .options || stage == .done }

    private var optionsCard: some View {
        VStack(spacing: 0) {
            Row(title: "Пропускать дубликаты", minHeight: 52) {
                Toggle("", isOn: $skipDuplicates)
                    .labelsHidden()
                    .tint(palette.green)
            }
            RowSeparator()
            Row(title: "Период", minHeight: 48) {
                Text("вся история")
                    .font(.system(size: 16))
                    .foregroundStyle(palette.fg2)
            }
        }
        .sheetCard(radius: 20)
        .cardInset()
    }

    private var progressBar: some View {
        VStack(spacing: 10) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.seg)
                    Capsule().fill(palette.blue)
                        .frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 6)
            Text("\(Int(progress * 100)) %")
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(palette.fg2)
        }
        .padding(.horizontal, 20)
    }

    private func loadPreview() async {
        guard stage == .preparing else { return }
        guard await health.requestAuthorization() else {
            preview = HealthStore.ImportResult()
            stage = .options
            return
        }
        preview = await health.previewImport(existing: items, skipDuplicates: skipDuplicates)
        stage = .options
    }

    private func runImport() {
        guard preview.found > 0 else { dismiss(); return }
        stage = .running
        Task {
            let samples = await health.fetchWeightSamples()
            var imported = 0, skipped = 0
            for (index, sample) in samples.enumerated() {
                if skipDuplicates, HealthStore.isDuplicate(sample, in: items) {
                    skipped += 1
                } else {
                    context.insert(WeighIn(date: sample.date, weightKg: sample.kg,
                                           impedance1: 0, impedance2: 0, fromHealth: true))
                    imported += 1
                }
                if index % 20 == 0 {
                    progress = Double(index) / Double(max(samples.count, 1))
                    try? await Task.sleep(for: .milliseconds(1))
                }
            }
            try? context.save()
            progress = 1
            importedCount = imported
            skippedCount = skipped
            settings.importedFromHealth = imported
            stage = .done
        }
    }
}

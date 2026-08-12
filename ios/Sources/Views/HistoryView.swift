import SwiftUI
import SwiftData
import Charts

struct HistoryView: View {
    @Environment(ProfileStore.self) private var profileStore
    @Environment(\.modelContext) private var context
    @Query(sort: \WeighIn.date, order: .reverse) private var history: [WeighIn]

    @State private var range: Range = .month

    enum Range: String, CaseIterable, Identifiable {
        case month = "Месяц", quarter = "3 месяца", year = "Год", all = "Всё"
        var id: String { rawValue }
        var days: Int? {
            switch self {
            case .month: return 30
            case .quarter: return 90
            case .year: return 365
            case .all: return nil
            }
        }
    }

    private var visible: [WeighIn] {
        guard let days = range.days,
              let from = Calendar.current.date(byAdding: .day, value: -days, to: Date())
        else { return history }
        return history.filter { $0.date >= from }
    }

    var body: some View {
        NavigationStack {
            Group {
                if history.isEmpty {
                    ContentUnavailableView("Пока пусто",
                                           systemImage: "scalemass",
                                           description: Text("Встаньте на весы — первое измерение появится здесь."))
                } else {
                    List {
                        Section {
                            chart
                                .frame(height: 220)
                                .listRowInsets(EdgeInsets(top: 12, leading: 8, bottom: 8, trailing: 12))
                        } header: {
                            Picker("Период", selection: $range) {
                                ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .textCase(nil)
                            .padding(.bottom, 6)
                        }

                        if !visible.isEmpty {
                            Section("Итог за период") { summary }
                        }

                        Section("Измерения") {
                            ForEach(visible) { item in
                                row(for: item)
                            }
                            .onDelete(perform: delete)
                        }
                    }
                }
            }
            .navigationTitle("История")
        }
    }

    private var chart: some View {
        Chart(visible.reversed()) { item in
            LineMark(x: .value("Дата", item.date), y: .value("Вес", item.weightKg))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.accentColor)
            PointMark(x: .value("Дата", item.date), y: .value("Вес", item.weightKg))
                .foregroundStyle(Color.accentColor)
                .symbolSize(20)
            AreaMark(x: .value("Дата", item.date), y: .value("Вес", item.weightKg))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(LinearGradient(colors: [Color.accentColor.opacity(0.25), .clear],
                                                startPoint: .top, endPoint: .bottom))
        }
        .chartYScale(domain: .automatic(includesZero: false))
    }

    @ViewBuilder
    private var summary: some View {
        let weights = visible.map(\.weightKg)
        if let first = weights.last, let last = weights.first, let min = weights.min(), let max = weights.max() {
            LabeledContent("Изменение", value: String(format: "%+.2f кг", last - first))
            LabeledContent("Минимум", value: String(format: "%.2f кг", min))
            LabeledContent("Максимум", value: String(format: "%.2f кг", max))
            LabeledContent("Взвешиваний", value: "\(weights.count)")
        }
    }

    private func row(for item: WeighIn) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(String(format: "%.2f кг", item.weightKg))
                    .font(.headline.monospacedDigit())
                Spacer()
                Text(item.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let composition = item.composition(for: profileStore.profile), !composition.fatPercent.isNaN {
                Text(String(format: "жир %.1f%% · мышцы %.1f кг · вода %.1f%%",
                            composition.fatPercent, composition.muscleMassKg, composition.waterPercent))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { context.delete(visible[index]) }
        try? context.save()
    }
}

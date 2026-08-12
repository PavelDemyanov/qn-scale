import SwiftUI

/// Подробности одного взвешивания.
struct DaySheet: View {
    @Environment(\.palette) private var palette
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    let item: WeighIn
    let delta: Double?
    let onDelete: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .lastTextBaseline, spacing: 7) {
                        Text(Fmt.n(item.weightKg))
                            .font(.system(size: 44, weight: .semibold))
                            .monospacedDigit()
                        Text("кг")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(delta.map { "\(Fmt.signed($0)) кг" } ?? "первое")
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(delta.map { palette.delta($0) } ?? .secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    LabeledContent("Время", value: Fmt.time(item.date))
                    LabeledContent("Жир",
                                   value: item.fatPercent(for: settings.profile)
                                       .map { "\(Fmt.n($0, 1)) %" } ?? "—")
                    LabeledContent("Импеданс",
                                   value: item.impedance1 > 0 ? "\(item.impedance1) Ом" : "нет данных")
                    LabeledContent("В «Здоровье»", value: item.syncedToHealth ? "записано" : "нет")
                }

                Section {
                    Button("Удалить измерение", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
            .navigationTitle(Fmt.fullDate(item.date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
        }
    }
}

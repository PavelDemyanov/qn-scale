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
        VStack(spacing: 0) {
            Capsule()
                .fill(palette.fg3)
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.fullDate(item.date))
                    .font(.system(size: 13))
                    .foregroundStyle(palette.fg2)
                HStack(alignment: .lastTextBaseline, spacing: 7) {
                    Text(Fmt.n(item.weightKg))
                        .font(.system(size: 44, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(palette.fg)
                    Text("кг")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(palette.fg2)
                    Spacer()
                    Text(delta.map { "\(Fmt.signed($0)) кг" } ?? "первое")
                        .font(.system(size: 17, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(delta.map { palette.delta($0) } ?? palette.fg3)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            VStack(spacing: 0) {
                row("Время", Fmt.time(item.date))
                RowSeparator()
                row("Жир", item.fatPercent(for: settings.profile).map { "\(Fmt.n($0, 1)) %" } ?? "—")
                RowSeparator()
                row("Импеданс", item.impedance1 > 0 ? "\(item.impedance1) Ом" : "нет данных")
                RowSeparator()
                row("В «Здоровье»", item.syncedToHealth ? "записано" : "нет")
            }
            .sheetCard(radius: 20)
            .cardInset()
            .padding(.top, 18)

            ActionButton(title: "Удалить измерение", kind: .destructive) {
                onDelete()
                dismiss()
            }
            .padding(.horizontal, 16)
            .padding(.top, 22)
            .padding(.bottom, 34)
        }
        // БЕЗ maxHeight: .infinity — шторка ровно по содержимому
        // (`measuringSheetHeight` на стороне вызова).
        .frame(maxWidth: .infinity, alignment: .top)
        .background(palette.sheet)
        // Отступ 34 у кнопки — от края экрана, как в макете
        .ignoresSafeArea(edges: .bottom)
    }

    private func row(_ label: String, _ value: String) -> some View {
        Row(title: label, minHeight: 46) {
            Text(value)
                .font(.system(size: 16, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(palette.fg2)
        }
    }
}

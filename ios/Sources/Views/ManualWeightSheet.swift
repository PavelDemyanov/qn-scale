import SwiftUI

/// Ручной ввод веса — когда взвесились не на своих весах или правите пропуск.
struct ManualWeightSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let lastWeight: Double?
    let onSave: (Double, Date) -> Void

    @State private var text = ""
    @State private var date = Date()
    @FocusState private var focused: Bool

    private var weight: Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), (20...300).contains(value) else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
        VStack(spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 7) {
                TextField(lastWeight.map { Fmt.n($0) } ?? "0,00", text: $text)
                    .font(.system(size: 56, weight: .semibold))
                    .monospacedDigit()
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .fixedSize()
                    .focused($focused)
                Text("кг")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(palette.fg2)
            }
            .padding(.top, 24)

            VStack(spacing: 0) {
                Row(title: "Когда", minHeight: 52) {
                    DatePicker("", selection: $date, in: ...Date())
                        .labelsHidden()
                }
            }
            .sheetCard(radius: 20)
            .cardInset()
            .padding(.top, 26)

            Text("Импеданса у такой записи нет, поэтому процент жира для неё не считается.")
                .font(.system(size: 12))
                .lineSpacing(4)
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.fg3)
                .padding(.horizontal, 36)
                .padding(.top, 12)

            Spacer()

            ActionButton(title: "Сохранить") {
                if let weight {
                    onSave(weight, date)
                    dismiss()
                }
            }
            .disabled(weight == nil)
            .padding(.horizontal, 16)
            .padding(.bottom, 34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.sheet)
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle("Вес вручную")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
        }
        }
        .onAppear { focused = true }
    }
}

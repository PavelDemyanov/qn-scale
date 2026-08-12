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
        VStack(spacing: 0) {
            HStack {
                Button("Отмена") { dismiss() }
                    .font(.system(size: 17))
                    .foregroundStyle(palette.blue)
                    .frame(width: 80, alignment: .leading)
                Spacer()
                Text("Вес вручную")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.fg)
                Spacer()
                Spacer().frame(width: 80)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 10)

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

            PrimaryButton(title: "Сохранить",
                          background: weight == nil ? palette.card2 : palette.blue,
                          foreground: weight == nil ? palette.fg3 : .white) {
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
        .onAppear { focused = true }
    }
}

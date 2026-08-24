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
            Form {
                Section {
                    HStack(alignment: .lastTextBaseline, spacing: 7) {
                        Spacer(minLength: 0)
                        TextField(lastWeight.map { Fmt.n($0) } ?? L("0.00"), text: $text)
                            .font(.system(size: 56, weight: .semibold))
                            .monospacedDigit()
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .fixedSize()
                            .focused($focused)
                        Text(L("kg"))
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color.clear)

                Section {
                    DatePicker(L("When"), selection: $date, in: ...Date())
                } footer: {
                    Text(L("A manual entry has no impedance, so body fat is not calculated for it."))
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(L("Manual weight"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save")) {
                        if let weight {
                            onSave(weight, date)
                            dismiss()
                        }
                    }
                    .disabled(weight == nil)
                }
                // Цифровая клавиатура без «Готово» не убирается — кнопка
                // обязана быть. По ЦЕНТРУ, а не у края: шторка короткая, и
                // прижатую вправо плашку подрезал её закруглённый угол.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L("Done")) { focused = false }
                    Spacer()
                }

            }
        }
        .onAppear { focused = true }
    }
}

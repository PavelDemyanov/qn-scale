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
                        Text(L("kg"))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(delta.map { L("%@ kg", Fmt.signed($0)) } ?? L("first"))
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(delta.map { palette.delta($0) } ?? .secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    LabeledContent(L("Time"), value: Fmt.time(item.date))
                    LabeledContent(L("Body fat"),
                                   value: item.fatPercent(for: settings.profile)
                                       .map { "\(Fmt.n($0, 1)) %" } ?? "—")
                    LabeledContent(L("Impedance"),
                                   value: item.impedance1 > 0 ? L("%d Ω", item.impedance1) : L("no data"))
                    LabeledContent(L("In Health"), value: item.syncedToHealth ? L("saved") : L("not saved"))
                }

                Section {
                    Button(L("Delete measurement"), role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
            .navigationTitle(Fmt.fullDate(item.date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } }
            }
        }
    }
}

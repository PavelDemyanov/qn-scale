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
        NavigationStack {
        VStack(spacing: 0) {
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

            ActionButton(title: buttonTitle) {
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
        .navigationTitle(L("Health"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(L("Cancel")) { dismiss() } }
        }
        }
        .task { await loadPreview() }
    }

    private var title: String {
        switch stage {
        case .preparing: return L("Reading Health…")
        case .options: return L("Found %@ of weight", Ln(preview.found, "record"))
        case .running: return L("Importing")
        case .done: return L("Imported %@", Ln(importedCount, "measurement"))
        }
    }

    private var subtitle: String {
        switch stage {
        case .preparing:
            return L("Checking what weight records are there.")
        case .options:
            guard preview.found > 0 else {
                return L("There are no weight records in Health.")
            }
            let earliest = preview.earliest.map { L("The earliest is %@, %d.", Fmt.dayMonth($0), Calendar.current.component(.year, from: $0)) + " " } ?? ""
            return earliest + L("Body fat comes along where Health has it; impedance stays only with measurements taken on the scale.")
        case .running:
            return L("Reading records and computing daily deltas…")
        case .done:
            return skippedCount > 0
                ? L("%@ skipped as duplicates of measurements already saved.", Ln(skippedCount, "record"))
                : L("No duplicates found.")
        }
    }

    private var buttonTitle: String {
        switch stage {
        case .preparing: return L("Reading…")
        case .options: return preview.found > 0 ? L("Import") : L("Close")
        case .running: return L("Importing…")
        case .done: return L("Done")
        }
    }

    private var buttonEnabled: Bool { stage == .options || stage == .done }

    private var optionsCard: some View {
        List {
            Toggle(L("Skip duplicates"), isOn: $skipDuplicates)
            LabeledContent(L("Period"), value: L("all history"))
        }
        .scrollDisabled(true)
        .frame(height: 140)
    }

    private var progressBar: some View {
        ProgressView(value: progress) {
            Text(L("Importing"))
        } currentValueLabel: {
            Text(progress.formatted(.percent.precision(.fractionLength(0))))
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
                                           impedance1: 0, impedance2: 0, fromHealth: true,
                                           healthFatPercent: sample.fatPercent))
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

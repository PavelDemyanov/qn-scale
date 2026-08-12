import SwiftUI
import SwiftData

/// Главный экран: встал — увидел вес.
struct WeighView: View {
    @Environment(ScaleManager.self) private var scale
    @Environment(ProfileStore.self) private var profileStore
    @Environment(HealthStore.self) private var health
    @Environment(\.modelContext) private var context

    @Query(sort: \WeighIn.date, order: .reverse) private var history: [WeighIn]

    private var displayedWeight: Double? { scale.liveWeightKg }
    private var isFinal: Bool { scale.state == .finished }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.10), Color(white: 0.03)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                statusRow

                weightDisplay

                if let reading = scale.lastReading, isFinal {
                    compositionGrid(for: reading)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    deltaHint
                }

                Spacer()
            }
            .padding(.top, 32)
            .padding(.horizontal, 20)
        }
        .animation(.smooth, value: scale.state)
        .animation(.smooth, value: scale.liveWeightKg)
        .onAppear { hookUpSaving() }
    }

    // MARK: - Части экрана

    private var statusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isFinal ? .green : .orange)
                .frame(width: 8, height: 8)
                .opacity(isFinal ? 1 : 0.6)
            Text(scale.state.caption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var weightDisplay: some View {
        VStack(spacing: 4) {
            Text(displayedWeight.map { String(format: "%.2f", $0) } ?? "—")
                .font(.system(size: 84, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(isFinal ? Color.primary : Color.primary.opacity(0.65))
            Text("килограммы")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var deltaHint: some View {
        if let previous = history.first {
            VStack(spacing: 6) {
                Text("Прошлое взвешивание")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                Text("\(String(format: "%.2f", previous.weightKg)) кг · \(previous.date.formatted(.relative(presentation: .named)))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func compositionGrid(for reading: QNProtocol.Reading) -> some View {
        let composition = BodyComposition.compute(weightKg: reading.weightKg,
                                                  impedanceOhm: reading.impedance1,
                                                  profile: profileStore.profile)
        let delta = history.dropFirst().first.map { reading.weightKg - $0.weightKg }

        return VStack(spacing: 12) {
            if let delta {
                Label(String(format: "%+.2f кг к прошлому разу", delta),
                      systemImage: delta > 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(delta > 0 ? .orange : .green)
            }

            if let composition {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MetricTile(title: "Жир", value: composition.fatPercent, unit: "%")
                    MetricTile(title: "Мышцы", value: composition.muscleMassKg, unit: "кг")
                    MetricTile(title: "Вода", value: composition.waterPercent, unit: "%")
                    MetricTile(title: "Кости", value: composition.boneMassKg, unit: "кг")
                    MetricTile(title: "ИМТ", value: composition.bmi, unit: "")
                    MetricTile(title: "Обмен", value: composition.basalMetabolismKcal, unit: "ккал", decimals: 0)
                }
            }

            if let composition {
                Text("Жир — оценка с разбросом в несколько процентных пунктов. У среднего человека с такими ростом, весом и возрастом было бы \(String(format: "%.0f", composition.fatPercentByBMI))%.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }

            Text("Импеданс \(reading.impedance1) / \(reading.impedance2) Ом")
                .font(.caption2)
                .foregroundStyle(.quaternary)
        }
    }

    // MARK: - Сохранение

    private func hookUpSaving() {
        scale.onStableReading = { reading in
            // Не плодим дубликаты, если весы прислали то же самое измерение ещё раз.
            if let last = history.first,
               abs(last.weightKg - reading.weightKg) < 0.01,
               Date().timeIntervalSince(last.date) < 120 {
                return
            }
            let weighIn = WeighIn(weightKg: reading.weightKg,
                                  impedance1: reading.impedance1,
                                  impedance2: reading.impedance2)
            context.insert(weighIn)
            try? context.save()

            Task { await health.save(weighIn: weighIn, profile: profileStore.profile) }
        }
    }
}

struct MetricTile: View {
    let title: String
    let value: Double
    let unit: String
    var decimals: Int = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value.isNaN ? "—" : String(format: "%.\(decimals)f", value))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}

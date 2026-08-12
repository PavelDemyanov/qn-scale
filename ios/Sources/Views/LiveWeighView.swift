import SwiftUI

/// Полноэкранное взвешивание: пульсирующий индикатор, живая цифра, итог.
struct LiveWeighView: View {
    @Environment(\.palette) private var palette
    @Environment(AppSettings.self) private var settings
    @Environment(ScaleManager.self) private var scale

    let items: [WeighIn]
    let onClose: () -> Void

    @State private var pulse = false

    private var isDone: Bool { scale.state == .finished }
    private var reading: QNProtocol.Reading? { scale.lastReading }

    var body: some View {
        VStack(spacing: 0) {
            indicator
                .padding(.bottom, 34)

            Text(scale.state.caption)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.fg)
            Text(scale.state.hint)
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.fg2)
                .frame(maxWidth: 280)
                .padding(.top, 6)

            HStack(alignment: .lastTextBaseline, spacing: 7) {
                Text(scale.liveWeightKg.map { Fmt.n($0) } ?? "—")
                    .font(.system(size: 72, weight: .semibold))
                    .tracking(-2)
                    .monospacedDigit()
                    .foregroundStyle(isDone ? palette.fg : palette.fg2)
                    .contentTransition(.numericText())
                Text("кг")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(palette.fg2)
            }
            .frame(height: 80)
            .padding(.top, 30)

            if isDone, let reading {
                resultCard(reading)
                    .transition(.opacity)
            }

            Spacer()

            ActionButton(title: isDone ? "Готово" : "Отменить",
                         kind: isDone ? .primary : .secondary,
                         action: onClose)
        }
        .padding(.horizontal, 24)
        .padding(.top, 96)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.bg)
        // Отступы 96 сверху и 34 снизу в макете — от краёв экрана.
        .ignoresSafeArea()
        .animation(.smooth, value: scale.state)
        .animation(.smooth, value: scale.liveWeightKg)
        .onAppear { pulse = true }
    }

    private var indicator: some View {
        ZStack {
            // Кольца пульсируют только пока ждём, что на весы встанут (фаза 0).
            if scale.state.phase == 0 {
                ForEach(0..<2, id: \.self) { i in
                    Circle()
                        .stroke(palette.blue, lineWidth: 2)
                        .frame(width: 128, height: 128)
                        .scaleEffect(pulse ? 1.7 : 0.55)
                        .opacity(pulse ? 0 : 0.5)
                        .animation(.easeOut(duration: 1.9).repeatForever(autoreverses: false)
                            .delay(Double(i) * 0.95), value: pulse)
                }
            }
            Circle()
                .fill(isDone ? palette.green.opacity(0.18) : palette.seg)
                .frame(width: 82, height: 82)
            ScaleDialIcon(size: 40, lineWidth: 2)
                .foregroundStyle(isDone ? palette.green : palette.blue)
        }
        .frame(width: 128, height: 128)
    }

    private func resultCard(_ reading: QNProtocol.Reading) -> some View {
        let previous = items.count >= 2 ? items[items.count - 2] : nil
        let delta = previous.map { reading.weightKg - $0.weightKg }
        let fat = items.last?.fatPercent(for: settings.profile)

        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                Row(title: "С прошлого раза", minHeight: 48) {
                    Text(delta.map { "\(Fmt.signed($0)) кг" } ?? "первое измерение")
                        .font(.system(size: 16, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(delta.map { palette.delta($0) } ?? palette.fg2)
                }
                RowSeparator()
                Row(title: "Жир", minHeight: 48) {
                    Text(fat.map { "\(Fmt.n($0, 1)) %" } ?? "—")
                        .font(.system(size: 16, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(palette.fg2)
                }
                RowSeparator()
                Row(title: "Импеданс", minHeight: 48) {
                    Text("\(reading.impedance1) / \(reading.impedance2) Ом")
                        .font(.system(size: 16, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(palette.fg2)
                }
            }
            .card()

            Text(settings.healthEnabled ? "Записано в «Здоровье»" : "«Здоровье» выключено в настройках")
                .font(.system(size: 13))
                .foregroundStyle(palette.fg3)
                .padding(.top, 12)
        }
        .padding(.top, 22)
    }
}

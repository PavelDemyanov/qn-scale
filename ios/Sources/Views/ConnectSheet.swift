import SwiftUI

/// Поиск и подключение весов. Шаги рукопожатия — настоящие, из ScaleManager.
struct ConnectSheet: View {
    @Environment(\.palette) private var palette
    @Environment(AppSettings.self) private var settings
    @Environment(ScaleManager.self) private var scale
    @Environment(\.dismiss) private var dismiss

    @State private var pulse = false

    private enum Step { case searching, found, handshake, done }

    private var step: Step {
        if scale.handshake.allDone { return .done }
        if !scale.pairingMode { return .handshake }
        return scale.candidateName == nil ? .searching : .found
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(spacing: 0) {
                indicator
                    .padding(.top, 10)
                    .padding(.bottom, 18)
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.fg)
                Text(subtitle)
                    .font(.system(size: 14))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.fg2)
                    .frame(maxWidth: 300)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            if step == .found {
                foundCard.padding(.top, 20)
            }
            if step == .handshake || step == .done {
                stepsCard.padding(.top, 20)
            }

            Spacer()

            PrimaryButton(title: buttonTitle,
                          background: buttonEnabled ? palette.blue : palette.card,
                          foreground: buttonEnabled ? .white : palette.fg3) {
                switch step {
                case .found: scale.confirmPairing()
                case .done: dismiss()
                default: break
                }
            }
            .disabled(!buttonEnabled)
            .padding(.horizontal, 16)
            .padding(.bottom, 34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.sheet)
        .onAppear {
            pulse = true
            scale.startPairing()
        }
        .onDisappear {
            if scale.pairingMode { scale.cancelPairing() }
        }
        .onChange(of: scale.scaleMAC) { _, mac in
            if let mac { settings.knownScaleMAC = mac }
        }
    }

    private var header: some View {
        HStack {
            Button("Отмена") { dismiss() }
                .font(.system(size: 17))
                .foregroundStyle(palette.blue)
                .frame(width: 80, alignment: .leading)
            Spacer()
            Text("Поиск весов")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.fg)
            Spacer()
            Color.clear.frame(width: 80)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var indicator: some View {
        ZStack {
            if step == .searching {
                Circle()
                    .stroke(palette.blue, lineWidth: 2)
                    .frame(width: 96, height: 96)
                    .scaleEffect(pulse ? 1.7 : 0.55)
                    .opacity(pulse ? 0 : 0.5)
                    .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false), value: pulse)
            }
            Circle()
                .fill(palette.seg)
                .frame(width: 62, height: 62)
            Image(systemName: step == .done ? "checkmark" : "dot.radiowaves.left.and.right")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(step == .done ? palette.green : palette.blue)
        }
        .frame(width: 96, height: 96)
    }

    private var title: String {
        switch step {
        case .searching: return "Ищу весы…"
        case .found: return "Найдены весы"
        case .handshake: return "Подключаюсь"
        case .done: return "Весы запомнены"
        }
    }

    private var subtitle: String {
        switch step {
        case .searching: return "Наступите на весы, чтобы они проснулись — в спящем режиме их не видно в эфире."
        case .found: return "Это те самые, если на дисплее сейчас горят нули."
        case .handshake: return "Настраиваю единицы и синхронизирую время — без этого весы не начнут передавать вес."
        case .done: return "Приложение будет подключаться к ним само, как только вы встанете."
        }
    }

    private var buttonTitle: String {
        switch step {
        case .searching: return "Ищу…"
        case .found: return "Подключить"
        case .handshake: return "Подключаюсь…"
        case .done: return "Готово"
        }
    }

    private var buttonEnabled: Bool { step == .found || step == .done }

    private var foundCard: some View {
        Row(title: scale.candidateName ?? "QN-Scale",
            subtitle: [settings.knownScaleMAC ?? scale.scaleMAC,
                       scale.candidateRSSI.map { "\($0) dBm" }]
                .compactMap { $0 }.joined(separator: " · "),
            minHeight: 58) {
            Button("Выбрать") { scale.confirmPairing() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(palette.blue, in: Capsule())
                .buttonStyle(.plain)
        }
        .card(radius: 20)
        .cardInset()
    }

    private var stepsCard: some View {
        VStack(spacing: 0) {
            stepRow("Сервис FFF0 найден", "0x12", scale.handshake.serviceFound)
            RowSeparator()
            stepRow("Единицы — килограммы", "0x13", scale.handshake.unitsConfigured)
            RowSeparator()
            stepRow("Синхронизация времени", "0x20", scale.handshake.timeSynced)
            RowSeparator()
            stepRow("Поток измерений", "0x10", scale.handshake.streaming)
        }
        .card(radius: 20)
        .cardInset()
    }

    private func stepRow(_ label: String, _ code: String, _ done: Bool) -> some View {
        HStack(spacing: 0) {
            Text(done ? "✓" : "·")
                .font(.system(size: 15))
                .foregroundStyle(done ? palette.green : palette.fg3)
                .frame(width: 22, alignment: .leading)
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(palette.fg)
            Spacer()
            Text(code)
                .font(.system(size: 12))
                .monospaced()
                .foregroundStyle(palette.fg3)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 44)
    }
}

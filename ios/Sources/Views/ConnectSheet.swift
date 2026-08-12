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
        NavigationStack {
        VStack(spacing: 0) {
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

            ActionButton(title: buttonTitle) {
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
        // alignment: .top тут — страховка на случай, если исчезнет Spacer выше;
        // сама раскладка ломалась не из-за него, а из-за распорки в шапке (см. header).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.sheet)
        // Отступ 34 у кнопки — от края экрана, как в макете
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle("Поиск весов")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
        }
        }
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
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .sheetCard(radius: 20)
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
        .sheetCard(radius: 20)
        .cardInset()
    }

    private func stepRow(_ label: String, _ code: String, _ done: Bool) -> some View {
        // Галочка и «ещё не сделано» — системными символами, а не значками
        // из текста: они сами тянутся за размером шрифта.
        Label {
            HStack {
                Text(label).foregroundStyle(palette.fg)
                Spacer()
                Text(code)
                    .font(.caption2.monospaced())
                    .foregroundStyle(palette.fg3)
            }
        } icon: {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dotted")
                .foregroundStyle(done ? palette.green : palette.fg3)
        }
        .font(.subheadline)
        .padding(.horizontal, 18)
        .frame(minHeight: 44)
    }
}

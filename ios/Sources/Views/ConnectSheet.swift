import SwiftUI
import UIKit

/// Поиск и подключение весов. Шаги рукопожатия — настоящие, из ScaleManager.
struct ConnectSheet: View {
    @Environment(\.palette) private var palette
    @Environment(AppSettings.self) private var settings
    @Environment(ScaleManager.self) private var scale
    @Environment(\.dismiss) private var dismiss

    @State private var pulse = false
    /// Поиск шёл вечно: ни таймаута, ни состояния «не нашлось». Человек без
    /// весов упирался в бесконечный спиннер и неактивную кнопку.
    @State private var searchedTooLong = false
    @State private var timeout: Task<Void, Never>?

    private enum Step { case blocked, searching, notFound, found, handshake, done }

    private var step: Step {
        if scale.handshake.allDone { return .done }
        if !scale.pairingMode { return .handshake }
        if scale.state == .bluetoothOff || scale.state == .unauthorized { return .blocked }
        if scale.candidateName != nil { return .found }
        return searchedTooLong ? .notFound : .searching
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
            if step == .notFound || step == .blocked {
                waysOut.padding(.top, 22)
            }
            if step == .handshake || step == .done {
                stepsCard.padding(.top, 20)
            }

            Spacer()

            if step != .notFound && step != .blocked {
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
        }
        // alignment: .top тут — страховка на случай, если исчезнет Spacer выше;
        // сама раскладка ломалась не из-за него, а из-за распорки в шапке (см. header).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.sheet)
        // Отступ 34 у кнопки — от края экрана, как в макете
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(L("Find scale"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(L("Cancel")) { dismiss() } }
        }
        }
        .onAppear {
            pulse = true
            scale.startPairing()
            timeout?.cancel()
            timeout = Task { @MainActor in
                // Двадцати секунд хватает: весы просыпаются за секунду-две,
                // если на них наступить.
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                searchedTooLong = true
            }
        }
        .onDisappear {
            timeout?.cancel()
            if scale.pairingMode { scale.cancelPairing() }
        }
        .onChange(of: scale.candidateName) { _, name in
            if name != nil { searchedTooLong = false }
        }
        .onChange(of: scale.scaleMAC) { _, mac in
            if let mac { settings.knownScaleMAC = mac }
        }
    }

    /// Что делать, если весов нет под рукой. Раньше из этого экрана вёл
    /// единственный выход — «Отмена», и приложение оставалось пустым.
    private var waysOut: some View {
        VStack(spacing: 10) {
            Button(L("Search again")) {
                searchedTooLong = false
                scale.startPairing()
                timeout?.cancel()
                timeout = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(20))
                    guard !Task.isCancelled else { return }
                    searchedTooLong = true
                }
            }
            .buttonStyle(.bordered)

            if step == .blocked {
                Button(L("Open iOS Settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }

            Button(L("Continue without a scale")) { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
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
        case .blocked:   return scale.state.caption
        case .notFound:  return L("No scale found")
        case .searching: return L("Searching for scale…")
        case .found: return L("Scale found")
        case .handshake: return L("Connecting")
        case .done: return L("Scale saved")
        }
    }

    private var subtitle: String {
        switch step {
        case .blocked:   return scale.state.hint
        case .notFound:  return L("Step on the scale so it wakes up, and keep the phone nearby. No scale at hand? You can add weights by hand and look at a sample history — the app works without one.")
        case .searching: return L("Step on the scale to wake it up — while it's asleep it stays invisible over Bluetooth.")
        case .found: return L("This is the one if zeros are lit on its display right now.")
        case .handshake: return L("Setting the units and syncing the time — without this the scale won't start sending weight.")
        case .done: return L("The app will connect to it on its own as soon as you step on it.")
        }
    }

    private var buttonTitle: String {
        switch step {
        case .blocked, .notFound: return L("Searching…")
        case .searching: return L("Searching…")
        case .found: return L("Connect")
        case .handshake: return L("Connecting…")
        case .done: return L("Done")
        }
    }

    private var buttonEnabled: Bool { step == .found || step == .done }

    private var foundCard: some View {
        Row(title: scale.candidateName ?? "QN-Scale",
            subtitle: [settings.knownScaleMAC ?? scale.scaleMAC,
                       scale.candidateRSSI.map { "\($0) dBm" }]
                .compactMap { $0 }.joined(separator: " · "),
            minHeight: 58) {
            Button(L("Select")) { scale.confirmPairing() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .sheetCard(radius: 20)
        .cardInset()
    }

    private var stepsCard: some View {
        VStack(spacing: 0) {
            stepRow(L("FFF0 service found"), "0x12", scale.handshake.serviceFound)
            RowSeparator()
            stepRow(L("Units — kilograms"), "0x13", scale.handshake.unitsConfigured)
            RowSeparator()
            stepRow(L("Time sync"), "0x20", scale.handshake.timeSynced)
            RowSeparator()
            stepRow(L("Measurement stream"), "0x10", scale.handshake.streaming)
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

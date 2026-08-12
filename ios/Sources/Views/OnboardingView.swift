import SwiftUI

/// Первый запуск: весы, профиль, цель. Те же три шага, что в макете,
/// но списки не декоративные — их можно править прямо здесь.
struct OnboardingView: View {
    @Environment(\.palette) private var palette
    @Environment(AppSettings.self) private var settings

    let sheetHeight: CGFloat
    let onFinish: () -> Void

    @State private var step = 0
    @State private var editingProfile = false
    @State private var searchingScale = false

    var body: some View {
        @Bindable var s = settings

        VStack(alignment: .leading, spacing: 0) {
            Text("ШАГ \(step + 1) ИЗ 3")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.blue)
                .padding(.bottom, 14)

            Text(title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(palette.fg)
            Text(bodyText)
                .font(.system(size: 16))
                .lineSpacing(3)
                .foregroundStyle(palette.fg2)
                .padding(.top, 12)

            if step == 1 { profileCard.padding(.top, 24) }
            if step == 2 { goalCard.padding(.top, 24) }

            Spacer()

            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i == step ? palette.blue : palette.fg3)
                        .frame(width: 7, height: 7)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 22)

            PrimaryButton(title: buttonTitle) {
                switch step {
                case 0: searchingScale = true
                case 1: step = 2
                default: finish()
                }
            }

            Button("Пропустить") { finish() }
                .font(.system(size: 15))
                .foregroundStyle(palette.fg2)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
        }
        .padding(.horizontal, 24)
        .padding(.top, 104)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(palette.bg)
        // Отступы 104 и 34 в макете отсчитываются от краёв экрана, а не от безопасной зоны.
        .ignoresSafeArea()
        .animation(.smooth, value: step)
        .sheet(isPresented: $editingProfile) {
            ProfileEditorView().environment(settings)
        }
        .sheet(isPresented: $searchingScale, onDismiss: { if step == 0 { step = 1 } }) {
            ConnectSheet()
                .presentationDetents([.height(sheetHeight)])
                .presentationCornerRadius(22)
        }
    }

    private func finish() {
        settings.onboardingDone = true
        Task {
            await Reminders.reschedule(enabled: settings.remindersEnabled,
                                       time: settings.reminderTime, lastWeighIn: nil)
        }
        onFinish()
    }

    private var title: String {
        switch step {
        case 0: return "Найдём ваши весы"
        case 1: return "Пара цифр о вас"
        default: return "Цель и напоминание"
        }
    }

    private var bodyText: String {
        switch step {
        case 0: return "Наступите на весы и держитесь рядом с телефоном. Приложение запомнит их и в следующий раз подключится само."
        case 1: return "Рост, дата рождения и пол нужны, чтобы посчитать процент жира по импедансу."
        default: return "Цель появится линией на графике, а пуш придёт в выбранное время, если в этот день вы ещё не взвешивались."
        }
    }

    private var buttonTitle: String {
        switch step {
        case 0: return "Искать весы"
        case 1: return "Дальше"
        default: return "Начать"
        }
    }

    private var profileCard: some View {
        Button { editingProfile = true } label: {
            VStack(spacing: 0) {
                onbRow("Рост", "\(Int(settings.profile.heightCm)) см")
                RowSeparator()
                onbRow("Дата рождения", settings.profile.birthDate.formatted(.dateTime.day().month().year()))
                RowSeparator()
                onbRow("Пол", settings.profile.isMale ? "Мужской" : "Женский")
            }
            .card(radius: 20)
        }
        .buttonStyle(.plain)
    }

    private var goalCard: some View {
        @Bindable var s = settings
        return VStack(spacing: 0) {
            Row(title: "Желаемый вес", minHeight: 48) {
                HStack(spacing: 12) {
                    Text("\(Fmt.n(settings.goalWeight, 1)) кг")
                        .font(.system(size: 16))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(palette.fg2)
                    HStack(spacing: 0) {
                        Button { settings.goalWeight = max(40, settings.goalWeight - 0.5) } label: {
                            Text("−").font(.system(size: 20)).foregroundStyle(palette.fg)
                                .frame(width: 40, height: 30).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Rectangle().fill(palette.sep).frame(width: 0.5, height: 30)
                        Button { settings.goalWeight = min(200, settings.goalWeight + 0.5) } label: {
                            Text("+").font(.system(size: 18)).foregroundStyle(palette.fg)
                                .frame(width: 40, height: 30).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .background(palette.seg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            RowSeparator()
            Row(title: "Напоминание", minHeight: 48) {
                Toggle("", isOn: $s.remindersEnabled)
                    .labelsHidden()
                    .tint(palette.green)
            }
            RowSeparator()
            Row(title: "Записывать в «Здоровье»", minHeight: 48) {
                Toggle("", isOn: $s.healthEnabled)
                    .labelsHidden()
                    .tint(palette.green)
            }
        }
        .card(radius: 20)
    }

    private func onbRow(_ label: String, _ value: String) -> some View {
        Row(title: label, minHeight: 48) {
            HStack(spacing: 8) {
                Text(value)
                    .font(.system(size: 16))
                    .monospacedDigit()
                    .foregroundStyle(palette.fg2)
                Chevron()
            }
        }
    }
}
